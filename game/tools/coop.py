"""Isolated bank co-op builds and launchers; never launches historical sandbox worlds."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'game/runtime/coop'
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def godot() -> Path:
    config = json.loads((ROOT / 'workspace.json').read_text(encoding='utf8'))
    path = Path(os.environ.get('GODOT_BIN', ROOT / config['godot']))
    if not path.is_file():
        raise FileNotFoundError('Set GODOT_BIN to the project-pinned Godot executable.')
    return path.resolve()


def stage(destination: Path | None = None, reference: bool = False) -> Path:
    """Copy a closed dependency set; unrelated single-player assets stay untouched."""
    if destination is None:
        stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]
        destination = ROOT / 'build/bank/coop' / stamp / 'project'
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    (destination / 'coop').mkdir()
    for path in SOURCE.iterdir():
        if path.name in {'main.gd','main.tscn','world.gd','session.gd','player.gd','avatar.gd','ui.gd','bank_layout.json','movement_prediction.gd'}:
            shutil.copy2(path, destination / 'coop' / path.name)
    if reference:
        folder=SOURCE/'local_reference'
        metadata=json.loads((folder/'manifest.json').read_text(encoding='utf8'))
        model=(folder/Path(metadata['resource']).name).resolve()
        if model.parent!=folder.resolve() or not model.is_file():raise ValueError('Invalid local reference manifest')
        target=destination/'coop/local_reference';target.mkdir()
        # GLB is self-contained. Never copy Godot's extracted image/import caches.
        shutil.copy2(model,target/model.name);shutil.copy2(folder/'manifest.json',target/'manifest.json')
    (destination / 'project.godot').write_text('''config_version=5
[application]
config/name="Bank Crisis Co-op"
run/main_scene="res://coop/main.tscn"
run/flush_stdout_on_print=true
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
[physics]
common/physics_ticks_per_second=60
3d/physics_engine="Jolt Physics"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''', encoding='utf8')
    return destination


def run(command: list[str], log: Path, timeout=180) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w', encoding='utf8') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, cwd=ROOT,
                                creationflags=HIDDEN, timeout=timeout)
    text = log.read_text(encoding='utf8', errors='replace')
    if result.returncode or 'SCRIPT ERROR:' in text or 'Parse Error:' in text:
        raise RuntimeError(f'Godot failed; see {log}\n{text[-4000:]}')


def import_project(project: Path) -> None:
    run([str(godot()), '--headless', '--path', str(project), '--editor', '--import'], project.parent / 'import.log')


def templates(platform: str) -> tuple[Path, Path]:
    config = json.loads((ROOT / 'workspace.json').read_text(encoding='utf8'))
    folder = ROOT / config['templates']
    names = ('linux_debug.x86_64', 'linux_release.x86_64') if platform == 'linux' else ('windows_debug_x86_64.exe', 'windows_release_x86_64.exe')
    missing = [name for name in names if not (folder / name).is_file()]
    if missing:
        archive = ROOT / '.tools/Godot_v4.7.2-stable_export_templates.tpz'
        if not archive.is_file():
            raise FileNotFoundError('Install matching Godot 4.7.2 export templates in .tools/templates.')
        with zipfile.ZipFile(archive) as source:
            for name in missing:
                (folder / name).write_bytes(source.read('templates/' + name))
    return tuple(folder / name for name in names)


def export(platform: str, server: bool, reference: bool) -> Path:
    project = stage(reference=reference and not server)
    debug, release = templates(platform)
    preset = 'Linux' if platform == 'linux' else 'Windows Desktop'
    executable = ('BankCoopServer.exe' if platform == 'windows' else 'bank-coop-server.x86_64') if server else ('BankCoop.exe' if platform == 'windows' else 'bank-coop.x86_64')
    output = project.parent / 'package'; output.mkdir()
    cfg = f'''[preset.0]
name="Coop"
platform="{preset}"
runnable=false
dedicated_server={str(server).lower()}
custom_features="{'dedicated_server' if server else ''}"
export_filter="all_resources"
include_filter="coop/*.json"
exclude_filter=""
export_path="../package/{executable}"
[preset.0.options]
custom_template/debug="{debug.as_posix()}"
custom_template/release="{release.as_posix()}"
binary_format/architecture="x86_64"
binary_format/embed_pck=true
application/modify_resources=false
'''
    (project / 'export_presets.cfg').write_text(cfg, encoding='utf8')
    import_project(project)
    run([str(godot()), '--headless', '--path', str(project), '--export-release', 'Coop'], project.parent / 'export.log')
    if server and platform == 'linux':
        shutil.copy2(ROOT / 'game/deploy/bank-coop.service', output)
    source_hashes = {p.relative_to(project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in (project / 'coop').rglob('*') if p.is_file() and p.suffix not in ('.import', '.uid')}
    manifest = {'project': 'bank', 'server': server, 'platform': platform, 'protocol': 2,
                'scope': '2–4 player structural bank movement slice; no combat or interactive doors',
                'local_reference': reference and not server, 'sources': source_hashes,
                'executable': executable, 'sha256': hashlib.sha256((output / executable).read_bytes()).hexdigest()}
    (output / 'build.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
    shutil.make_archive(str(project.parent / (('server-' if server else 'client-') + platform)), 'zip', output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', choices=['bank'], required=True)
    sub = parser.add_subparsers(dest='command', required=True)
    for command in ['server', 'client']:
        child = sub.add_parser(command)
        child.add_argument('--port', type=int, default=24567)
        child.add_argument('--host', default='127.0.0.1')
        child.add_argument('--name', default='Player')
        child.add_argument('--max-players', type=int, choices=[2, 3, 4], default=4)
        child.add_argument('--reference', action='store_true')
    child = sub.add_parser('export')
    child.add_argument('--platform', choices=['windows', 'linux'], required=True)
    child.add_argument('--server', action='store_true')
    child.add_argument('--reference', action='store_true')
    args = parser.parse_args()
    if args.command == 'export':
        print(export(args.platform, args.server, args.reference)); return
    if not 1024 <= args.port <= 65535:
        parser.error('port must be 1024–65535')
    project = stage(reference=args.reference and args.command == 'client')
    import_project(project)
    cmd = [str(godot()), '--path', str(project)]
    if args.command == 'server':
        cmd += ['--headless', '--', '--server', f'--port={args.port}', f'--max-players={args.max_players}']
    else:
        cmd += ['--', f'--connect={args.host}', f'--port={args.port}', f'--name={args.name}']
    # Deliberate interactive launcher; children are owned by this terminal.
    try:
        raise SystemExit(subprocess.call(cmd, cwd=ROOT))
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
