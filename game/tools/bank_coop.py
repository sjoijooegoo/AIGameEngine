"""Launch or export the actual bank co-op scene (not the structural prototype)."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from game.tools.coop import ROOT, HIDDEN, godot, templates, run


def export(platform: str) -> Path:
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    folder=ROOT/'build/bank/combat-coop'/stamp/platform
    project=folder/'project';project.parent.mkdir(parents=True,exist_ok=True)
    # Immutable staging leaves the user's project/export presets untouched.
    shutil.copytree(ROOT/'game/runtime',project,ignore=shutil.ignore_patterns('.godot','.git','*.tmp'))
    # Reuse imported resources; export still scans source hashes for changed files.
    cache=ROOT/'game/runtime/.godot/imported'
    if cache.exists():shutil.copytree(cache,project/'.godot/imported')
    debug,release=templates(platform)
    package=folder/'package';package.mkdir()
    filename='bank-coop-server.x86_64' if platform=='linux' else 'BankCoop.exe'
    (project/'export_presets.cfg').write_text(f'''[preset.0]
name="Bank Co-op"
platform="{'Linux' if platform=='linux' else 'Windows Desktop'}"
runnable=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="data/*.json,coop/local_reference/*.json"
exclude_filter="tools/*"
export_path="../package/{filename}"
[preset.0.options]
custom_template/debug="{debug.as_posix()}"
custom_template/release="{release.as_posix()}"
binary_format/architecture="x86_64"
binary_format/embed_pck=true
application/modify_resources=false
''',encoding='utf8')
    # Keep mesh/animation data on Linux: native hitboxes and ragdoll gameplay
    # need it even with headless rendering. Godot resource stripping isn't used.
    run([str(godot()),'--headless','--path',str(project),'--editor','--import'],folder/'import.log',900)
    run([str(godot()),'--headless','--path',str(project),'--export-release','Bank Co-op'],folder/'export.log',900)
    if platform=='linux':shutil.copy2(ROOT/'game/deploy/bank-coop.service',package)
    else:
        (package/'Play Co-op.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nstart "" BankCoop.exe -- --coop\r\n',encoding='ascii')
    hashes={str(p.relative_to(project)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
            for sub in ['coop','scripts','data','ui','scenes'] for p in (project/sub).rglob('*')
            if p.is_file() and p.suffix in ['.gd','.json','.tscn']}
    hashes['project.godot']=hashlib.sha256((project/'project.godot').read_bytes()).hexdigest()
    manifest={'scope':'actual bank co-op combat','platform':platform,'engine':'4.7.2','sources':hashes,
              'local_reference_assets':True,'executable':filename,'sha256':hashlib.sha256((package/filename).read_bytes()).hexdigest()}
    (package/'build.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    shutil.make_archive(str(folder/f'bank-coop-{platform}'),'zip',package)
    return package


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True)
    sub=parser.add_subparsers(dest='command',required=True)
    for name in ['server','client']:
        p=sub.add_parser(name);p.add_argument('--port',type=int,default=24567)
        p.add_argument('--host');p.add_argument('--name',default='Player');p.add_argument('--max-players',type=int,choices=[2,3,4],default=4)
    p=sub.add_parser('export');p.add_argument('--platform',choices=['windows','linux'],required=True)
    args=parser.parse_args()
    if args.command=='export':print(export(args.platform));return
    if not 1024<=args.port<=65535:parser.error('port must be 1024–65535')
    cmd=[str(godot()),'--path',str(ROOT/'game/runtime')]
    if args.command=='server':cmd+=['--headless','--','--server',f'--port={args.port}',f'--max-players={args.max_players}']
    else:
        cmd+=['--','--coop',f'--port={args.port}',f'--name={args.name}']
        if args.host:cmd+=[f'--connect={args.host}']
    raise SystemExit(subprocess.call(cmd,cwd=ROOT,creationflags=HIDDEN))


if __name__=='__main__':main()
