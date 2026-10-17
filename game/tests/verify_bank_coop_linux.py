"""Actual bank Linux release in WSL Ubuntu, four real-time Windows clients."""
import argparse
import datetime
import json
import math
import shlex
import subprocess
import time
from pathlib import Path
from game.tools.coop import ROOT,HIDDEN
from game.tests.verify_bank_coop import BankPeer
from game.tests.verify_coop import until


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True);parser.add_argument('--server-package',type=Path,required=True);args=parser.parse_args()
    binary=(args.server_package/'bank-coop-server.x86_64').resolve();assert binary.is_file()
    folder=ROOT/'logs/sessions'/('bank-combat-linux-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    linux='/mnt/'+binary.drive[0].lower()+binary.as_posix()[2:]
    launch=folder/'launch.sh';launch.write_text('#!/bin/sh\necho $$\nexec '+shlex.quote(linux)+' --headless -- --server --port=24751 --max-players=4\n',encoding='utf8',newline='\n')
    log=(folder/'server.log').open('w',encoding='utf8');script='/mnt/'+launch.drive[0].lower()+launch.as_posix()[2:]
    process=subprocess.Popen(['wsl','-d','Ubuntu','--','sh',script],stdout=log,stderr=subprocess.STDOUT,creationflags=HIDDEN)
    clients=[];pid=None;report={'passed':False,'checks':[]}
    try:
        until(lambda:(folder/'server.log').stat().st_size>0,timeout=15)
        pid=int((folder/'server.log').read_text(encoding='utf8').splitlines()[0])
        until(lambda:'COOP_STATUS' in (folder/'server.log').read_text(encoding='utf8'),timeout=90)
        pid=int((folder/'server.log').read_text(encoding='utf8').splitlines()[0])
        host=subprocess.check_output(['wsl','-d','Ubuntu','--','hostname','-I'],text=True).split()[0]
        for name in ['Alpha','Bravo','Charlie','Delta']:
            clients.append(BankPeer(folder/name,['--connect='+host,'--port=24751','--name='+name,'--real-time']))
        until(lambda:all(len(c.state()['combat'])==4 for c in clients),30)
        first=clients[0];aid=first.state()['local_id']
        assert first.state()['leader']==aid
        until(lambda:all(c.state()['started'] for c in clients))
        def row(client):return next(p for p in client.state()['players'] if p['id']==aid)
        before=row(first)['position'];first.call('input',keys=['S']);time.sleep(.7);first.call('input');time.sleep(.5)
        after=row(first)['position'];distance=math.dist(before,after);assert 1.3<distance<3.1,(before,after,distance)
        for c in clients[1:]:assert math.dist(row(c)['target'],after)<.1
        report['checks'].append({'name':'bank_linux_four_clients_and_movement','status':'pass','metres':distance})
        first.call('input',buttons=['left']);time.sleep(.15);first.call('input');time.sleep(.5)
        assert first.state()['combat'][str(aid)]['shots']==1
        for c in clients[1:]:assert c.state()['combat'][str(aid)]['shots']==1
        report['checks'].append({'name':'bank_linux_authoritative_weapon_state','status':'pass'})
        last=clients[-1];last.call('menu');last.call('click',control='leave_button')
        until(lambda:all(len(c.state()['players'])==3 for c in clients[:-1]))
        report['checks'].append({'name':'bank_linux_leave_cleanup','status':'pass'})
        last.call('click',control='join_button');until(lambda:all(len(c.state()['players'])==4 for c in clients),30)
        report['checks'].append({'name':'bank_linux_cli_address_rejoin','status':'pass'})
        (folder/'proc-status.txt').write_text(subprocess.check_output(['wsl','-d','Ubuntu','--','cat',f'/proc/{pid}/status'],text=True),encoding='utf8')
        report.update(passed=True,server_build=json.loads((args.server_package/'build.json').read_text()),scope='WSL Ubuntu release + four Windows debug clients; local UDP, not VPS/WAN performance')
        print('BANK_LINUX_PASS',flush=True)
    finally:
        for c in clients:c.close()
        if pid:subprocess.run(['wsl','-d','Ubuntu','--','kill','-TERM',str(pid)],creationflags=HIDDEN,check=False)
        try:process.wait(timeout=8)
        except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
        log.close();(folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')


if __name__=='__main__':main()
