"""Optional local WSL Ubuntu release-server + Windows client interoperability check."""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import shlex
import subprocess
import time
from game.tools.coop import ROOT,HIDDEN,stage,import_project
from game.tests.verify_coop import Peer,until


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--server-package',type=Path,required=True)
    args=parser.parse_args()
    binary=(args.server_package/'bank-coop-server.x86_64').resolve()
    assert binary.is_file()
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    evidence=ROOT/'logs/sessions'/('bank-coop-linux-'+stamp);evidence.mkdir(parents=True)
    project=stage();(project/'tests').mkdir()
    shutil.copy2(ROOT/'game/tests/coop_peer_driver.gd',project/'tests')
    import_project(project)
    linux='/mnt/'+binary.drive[0].lower()+binary.as_posix()[2:]
    stream=(evidence/'server.log').open('w',encoding='utf8')
    launcher=evidence/'launch.sh'
    launcher.write_text('#!/bin/sh\necho $$\nexec '+shlex.quote(linux)+' --headless -- --server --port=24751 --max-players=4\n',encoding='utf8',newline='\n')
    script='/mnt/'+launcher.drive[0].lower()+launcher.as_posix()[2:]
    command=['wsl','-d','Ubuntu','--','sh',script]
    process=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,creationflags=HIDDEN)
    clients=[];report={'passed':False};pid=None
    try:
        until(lambda:'COOP_STATUS' in (evidence/'server.log').read_text(encoding='utf8'),timeout=20)
        pid=int((evidence/'server.log').read_text(encoding='utf8').splitlines()[0])
        host=subprocess.check_output(['wsl','-d','Ubuntu','--','hostname','-I'],text=True).split()[0]
        for name in ['win-a','win-b','win-c','win-d']:
            clients.append(Peer(project,evidence/name,['--connect='+host,'--port=24751','--name='+name,'--real-time']))
        until(lambda:all(len(c.state()['players'])==4 for c in clients))
        first=clients[0];id=first.state()['local_id']
        def row(client):return next(p for p in client.state()['players'] if p['id']==id)
        before=row(first)['position']
        first.call('input',keys=['W']);time.sleep(.7);first.call('input',keys=[]);time.sleep(.5)
        after=row(first)['position'];distance=after[2]-before[2]
        assert 1.5<distance<3.0,(before,after,distance)
        for client in clients[1:]:assert abs(row(client)['target'][2]-after[2])<.05
        clients[-1].call('menu');clients[-1].call('click',control='leave_button')
        until(lambda:all(len(c.state()['players'])==3 for c in clients[:-1]))
        memory=subprocess.check_output(['wsl','-d','Ubuntu','--','cat',f'/proc/{pid}/status'],text=True)
        (evidence/'proc-status.txt').write_text(memory,encoding='utf8')
        report={'passed':True,'platform':'WSL Ubuntu x86_64 release server + 4 Windows debug clients',
                'checks':['linux_release_start','cross_os_four_clients','real_time_authoritative_movement','cross_os_leave'],
                'movement_metres':distance,'server_build':json.loads((args.server_package/'build.json').read_text()),
                'scope':'Real-time production scheduling over local UDP; not remote VPS capacity/latency validation'}
        print('COOP_LINUX_PASSED',evidence)
    except BaseException as error:
        report['error']=repr(error)
        raise
    finally:
        for client in clients:client.close()
        if pid:subprocess.run(['wsl','-d','Ubuntu','--','kill','-TERM',str(pid)],creationflags=HIDDEN,check=False)
        try:process.wait(timeout=8)
        except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
        stream.close()
        (evidence/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')


if __name__=='__main__':main()
