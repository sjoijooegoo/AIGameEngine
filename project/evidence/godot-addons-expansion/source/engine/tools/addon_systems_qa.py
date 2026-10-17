"""Bounded real-input and editor checks for the optional dialogue / AI / puzzle tools."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

from PIL import Image, ImageChops
from engine.core.io import atomic_json
from engine.core.paths import ROOT, PROJECT_ID, PROJECT_ROOT, LOGS, godot_path
from engine.core.process import HIDDEN
from engine.tools.lab import Client
from engine.tools.sequence import build as sequence_viewer


def editor_check(headless):
    directory = LOGS / 'runs' / ('addon-editor-' + uuid.uuid4().hex[:8])
    directory.mkdir(parents=True)
    env = dict(os.environ, AIGE_ADDON_EDITOR_SESSION=directory.as_posix())
    command = [str(godot_path()), '--path', str(PROJECT_ROOT), '--editor', '--resolution', '1440x900']
    if headless:
        command.append('--headless')
    with (directory / 'engine.log').open('w', encoding='utf-8') as log:
        proc = subprocess.run(command, env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=55, creationflags=HIDDEN)
    report = json.loads((directory / 'editor-report.json').read_text(encoding='utf-8'))
    text = (directory / 'engine.log').read_text(encoding='utf-8', errors='replace')
    report['engine_log_clean'] = not re.search(r'SCRIPT ERROR|^ERROR:|Parse Error', text, re.M)
    report['passed'] = (proc.returncode == 0 and report['engine_log_clean'] and report['puzzle_view_loaded']
                        and report['dialogue_editor_enabled'] and report['limboai_loaded']
                        and report.get('things') == 3 and report.get('connections') == 2
                        and (headless or report.get('capture_error') == 0))
    atomic_json(directory / 'editor-report.json', report)
    print(json.dumps({'report': str(directory / 'editor-report.json'), **report}, ensure_ascii=False, indent=2))
    return report['passed']


def runtime_check(headless):
    client = Client.launch(rendered=not headless, scene='systems')
    report = {'session': str(client.session), 'headless': headless, 'checks': [], 'limits': ['Fixture only, no production navigation or complete checkpoints']}

    def check(name, ok, detail=None):
        report['checks'].append(dict(name=name, status='pass' if ok else 'fail', detail=detail))
        atomic_json(client.session / 'systems-report.json', report)

    def settled():
        for _ in range(100):
            state = client.call('state')
            if not state['busy']:
                return state
            time.sleep(0.02)
        raise TimeoutError('Dialogue failed to settle')

    def freeze(name):
        before = settled()
        if not headless:
            client.call('capture', name=name + '_before')
        time.sleep(0.6)
        check(name + '_state_frozen', before == settled())
        if not headless:
            client.call('capture', name=name + '_after')
            a = Image.open(client.session / (name + '_before.png')).convert('RGB')
            b = Image.open(client.session / (name + '_after.png')).convert('RGB')
            check(name + '_pixels_frozen', ImageChops.difference(a, b).getbbox() is None)

    try:
        initial = client.call('step', frames=30)
        check('limboai_manual_steps', initial['manual_ai'] and initial['ai_ticks'] == 30)
        client.call('act', keys=['E'], frames=1)
        locked = settled()
        check('dialogue_locked_branch', '门禁锁定' in locked['text'] and locked['responses'] == 2)
        freeze('dialogue')
        ui = client.call('ui')
        check('controls_inside_viewport', all(c['inside_viewport'] for c in ui['controls'].values() if c['visible']))
        client.call('click', control='choice_1')
        hint = settled()
        check('real_click_selects_response', '先验证门卡' in hint['text'], hint)
        client.call('act', keys=['E'], frames=1)
        check('dialogue_ends', settled()['dialogue_id'] == '')
        client.call('act', keys=['K'], frames=1)
        client.call('act', keys=['E'], frames=1)
        unlocked = settled()
        check('game_owned_state_changes_branch', unlocked['has_keycard'] and '门卡有效' in unlocked['text'], unlocked)
        if not headless:
            client.call('capture', name='unlocked_dialogue')
        client.call('act', keys=['2'], frames=1)
        check('keyboard_selects_response', settled()['dialogue_id'] == '')
        alerted = client.call('act', keys=['F'], frames=30)
        check('blackboard_drives_action', alerted['alert'] and alerted['ai_mode'] == '警戒')
        freeze('ai')
        if not headless:
            client.call('sequence', name='ai_progress', count=9, interval=6)
            report['sequence'] = sequence_viewer(client.session / 'ai_progress.sequence.json', speed=0.25)
        paused = client.call('act', keys=['SPACE'], frames=1)
        later = client.call('step', frames=60)
        check('pause_stops_ai', later['paused'] and later['ai_ticks'] == paused['ai_ticks'] and later['ai_progress'] == paused['ai_progress'])
        resumed = client.call('act', keys=['SPACE'], frames=10)
        check('resume_advances_ai', not resumed['paused'] and resumed['ai_ticks'] == paused['ai_ticks'] + 10)
    except Exception as error:
        check('harness_exception', False, repr(error))
    finally:
        client.close()
        text = (client.session / 'engine.log').read_text(encoding='utf-8', errors='replace')
        check('engine_log_clean', not re.search(r'SCRIPT ERROR|^ERROR:|Parse Error', text, re.M))
        report['passed'] = all(c['status'] == 'pass' for c in report['checks'])
        atomic_json(client.session / 'systems-report.json', report)
        print(json.dumps({'report': str(client.session / 'systems-report.json'), 'passed': report['passed'], 'checks': report['checks']}, ensure_ascii=False, indent=2))
    return report['passed']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--editor', action='store_true')
    args = parser.parse_args()
    if PROJECT_ID != 'addon_probe':
        raise ValueError('Select --project addon_probe')
    raise SystemExit(0 if (editor_check(args.headless) if args.editor else runtime_check(args.headless)) else 1)


if __name__ == '__main__':
    main()
