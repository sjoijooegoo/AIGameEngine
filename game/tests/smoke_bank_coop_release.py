"""Release-only server + two release clients; verify joins and disabled debug bridge."""
import argparse
import datetime
import json
from pathlib import Path
import socket
import subprocess
import time
from game.tools.coop import ROOT,HIDDEN
from game.tests.verify_coop import until


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.add_argument('--package',type=Path,required=True);args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-coop-release-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    exe=(args.package/'BankCoop.exe').resolve();processes=[];logs=[];checks=[]
    with socket.socket(type=socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    try:
        for name in ['server','Alpha','Bravo']:
            path=folder/name;path.mkdir();log=(path/'engine.log').open('w',encoding='utf8');logs.append(log)
            flags=['--server',f'--port={port}'] if name=='server' else ['--connect=127.0.0.1',f'--port={port}',f'--name={name}']
            cmd=[str(exe),'--headless','--',*flags,f'--ai-session={path.as_posix()}']
            process=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,creationflags=HIDDEN);processes.append(process)
            (path/'launch.json').write_text(json.dumps({'command':cmd,'pid':process.pid},indent=2),encoding='utf8')
            until(lambda:'COOP_STATUS' in (path/'engine.log').read_text(encoding='utf8'),30)
        until(lambda:'players=2' in (folder/'server/engine.log').read_text(encoding='utf8'),30)
        time.sleep(2)
        for name,process in zip(['server','Alpha','Bravo'],processes):
            text=(folder/name/'engine.log').read_text(encoding='utf8');assert process.poll() is None
            assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-2000:]
            assert not (folder/name/'ready.json').exists()
        checks=[{'name':'bank_release_two_clients','status':'pass'},{'name':'bank_release_debug_bridge_disabled','status':'pass'}]
        print('BANK_RELEASE_PASS',flush=True)
    finally:
        for p in processes:
            if p.poll() is None:p.terminate();p.wait(timeout=8)
        for log in logs:log.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'build':json.loads((args.package/'build.json').read_text())},indent=2),encoding='utf8')


if __name__=='__main__':main()
