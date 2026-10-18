"""Packaged Windows clients against the VPS, then optional service recovery.

This is a connection soak, not an automated combat or rendered-FPS measurement.
It never restarts an occupied service. Killing clients deliberately exercises the
existing bounded slot reservation before the empty-service restart check.
"""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import time
from game.tools.coop import ROOT,HIDDEN
from game.tools.local_bank_server import query
from game.tests.verify_coop import until
from game.tests.benchmark_vps_coop import ssh


def check_service_recovery(folder):
    report={'failure':None}
    def status():return query('207.57.124.243',timeout=2)
    try:
        until(lambda:(s:=status()) and s['occupied']==0,75)
        before=ssh('systemctl show bank-coop -p MainPID -p NRestarts')
        assert status()['occupied']==0
        ssh('sudo -n systemctl kill --kill-whom=main --signal=SIGKILL bank-coop.service')
        until(lambda:(s:=status()) and s['occupied']==0,120)
        after=ssh('systemctl show bank-coop -p MainPID -p NRestarts; systemctl is-enabled bank-coop; systemctl is-active bank-coop')
        old=dict(line.split('=',1) for line in before.splitlines() if '=' in line)
        new=dict(line.split('=',1) for line in after.splitlines() if '=' in line)
        assert new['MainPID']!=old['MainPID'] and int(new['NRestarts'])>int(old['NRestarts'])
        report.update(name='vps_systemd_crash_recovery',status='pass',before=before,after=after,discovery=status())
    except Exception as exc:report['failure']=repr(exc);raise
    finally:(folder/'service-recovery.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',required=True,choices=['bank'])
    parser.add_argument('--package',required=True,type=Path)
    parser.add_argument('--seconds',type=int,default=120)
    parser.add_argument('--players',type=int,choices=[2,4],default=2)
    parser.add_argument('--transport',choices=['udp','tcp'],default='udp')
    parser.add_argument('--skip-service-recovery',action='store_true',help='For an isolated candidate process, not a systemd service')
    args=parser.parse_args();assert 30<=args.seconds<=600
    folder=ROOT/'logs/sessions'/('bank-vps-release-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    folder.mkdir(parents=True);print(folder,flush=True)
    peers=[];logs=[];report={'checks':[],'samples':[],'failure':None,'discovery_missed_datagrams':0}
    def mark(name,**values):report['checks'].append({'name':name,'status':'pass',**values});print(name,flush=True)
    def status():
        # A lost UDP discovery datagram is not a disconnected TCP game peer.
        # Retry within the previous 2s observation budget; retain every miss.
        # Any received wrong population/reservation fails as before, and client
        # logs must still contain no reconnection across the entire soak.
        for _ in range(3):
            value=query('207.57.124.243',timeout=.6)
            if value:return value
            report['discovery_missed_datagrams']+=1
        return None
    def save():(folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    try:
        assert status()['occupied']==0
        if not args.skip_service_recovery:(folder/'service-before.txt').write_text(ssh('systemctl show bank-coop -p MainPID -p NRestarts -p MemoryCurrent -p CPUUsageNSec; free -m'),encoding='utf8')
        for number in range(1,args.players+1):
            path=folder/f'client-{number}';path.mkdir();log=(path/'engine.log').open('w',encoding='utf8');logs.append(log)
            command=[str((args.package/'BankCoop.exe').resolve()),'--headless','--max-fps','60','--','--connect=207.57.124.243','--port=24567','--transport='+args.transport,f'--name=Release{number}',f'--ai-session={path.as_posix()}']
            p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,creationflags=HIDDEN);peers.append(p)
            (path/'launch.json').write_text(json.dumps({'command':command,'pid':p.pid}),encoding='utf8')
        until(lambda:(s:=status()) and s['players']==args.players,120)
        mark('vps_packaged_clients_join')
        start=time.monotonic()
        while time.monotonic()-start<args.seconds:
            s=status();report['samples'].append({'seconds':time.monotonic()-start,'status':s})
            assert all(p.poll() is None for p in peers),'Release process exited'
            time.sleep(2)
        assert all(s['status'] and s['status']['players']==args.players and s['status']['reserved']==0 for s in report['samples']),'Population changed during soak'
        for number in range(1,args.players+1):
            path=folder/f'client-{number}';text=(path/'engine.log').read_text(encoding='utf8')
            assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-3000:]
            assert '自动重连' not in text and '连接中断' not in text,text[-3000:]
            assert not (path/'ready.json').exists(),'Release debug bridge enabled'
            lighting=[json.loads(x.split('BANK_LIGHTING ',1)[1]) for x in text.splitlines() if x.startswith('BANK_LIGHTING ')]
            assert lighting and lighting[-1]['loaded'] and lighting[-1]['meshes']==481
        mark('vps_release_connection_soak',seconds=args.seconds,players=args.players,transport=args.transport)
        mark('vps_release_bake_and_disabled_bridge')
    except Exception as exc:report['failure']=repr(exc);raise
    finally:
        for p in peers:
            if p.poll() is None:p.terminate();p.wait(timeout=15)
        for log in logs:log.close()
        try:
            until(lambda:(s:=status()) and s['occupied']==0,75)
            report['status_after_clients']=status()
            if not args.skip_service_recovery:(folder/'service-after.txt').write_text(ssh('systemctl show bank-coop -p MainPID -p NRestarts -p MemoryCurrent -p CPUUsageNSec; free -m'),encoding='utf8')
        finally:save()
    # Explicitly scoped process-crash recovery, only after every slot is empty.
    if not args.skip_service_recovery:report['checks'].append(check_service_recovery(folder))
    report['status_final']=status();save()


if __name__=='__main__':main()
