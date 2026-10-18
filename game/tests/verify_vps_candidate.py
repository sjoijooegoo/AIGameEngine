"""Run paired candidate release/UI checks with an SSH-independent lifetime."""
import argparse,base64,datetime,json,pathlib,shlex,subprocess,sys
from game.tests.benchmark_vps_coop import ssh
from game.tests.verify_coop import until
from game.tools.local_bank_server import query
from game.tools.coop import ROOT

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',required=True,choices=['bank'])
    p.add_argument('--binary',required=True);p.add_argument('--package',required=True,type=pathlib.Path)
    p.add_argument('--seconds',type=int,default=180);p.add_argument('--ui',action='store_true')
    p.add_argument('--players',type=int,nargs='+',choices=[2,4],default=[2,4]);args=p.parse_args()
    folder=ROOT/'logs/sessions'/('bank-vps-candidate-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    status=until(lambda:query('207.57.124.243',timeout=1),30);assert status['occupied']==0
    report={'checks':[],'failure':None};attempted=False
    source=base64.b64encode((ROOT/'game/tests/vps_release_bridge.py').read_bytes()).decode()
    install="import pathlib,base64;pathlib.Path('/home/dev/bank-coop-validation/drivers/vps_release_bridge.py').write_bytes(base64.b64decode("+repr(source)+"))"
    ssh('python3 -c '+shlex.quote(install))
    command=['python3','/home/dev/bank-coop-validation/drivers/vps_release_bridge.py']
    options=['--binary',args.binary,'--session','/home/dev/bank-coop-validation/sessions/'+folder.name]
    try:
        attempted=True;report['remote']=json.loads(ssh(shlex.join(command+['start']+options)))
        assert report['remote']['returncode']==0
        until(lambda:(s:=query('207.57.124.243',timeout=2)) and s.get('build')=='bank-combat-v6',120)
        for players in args.players:
            before=until(lambda:query('207.57.124.243',timeout=1),15)
            assert before['build']=='bank-combat-v6' and before['occupied']==0,'Candidate unexpectedly unavailable'
            result=subprocess.run([sys.executable,'-m','game.tests.verify_vps_release','--project','bank','--package',str(args.package),'--players',str(players),'--transport','tcp','--seconds',str(args.seconds),'--skip-service-recovery'])
            report['checks'].append({'players':players,'seconds':args.seconds,'packaged_soak':'pass' if result.returncode==0 else 'fail'})
        if args.ui:
            assert until(lambda:query('207.57.124.243',timeout=1),15)['build']=='bank-combat-v6'
            result=subprocess.run([sys.executable,'-m','game.tests.verify_vps','--project','bank','--transport','tcp'])
            report['checks'].append({'ui':'pass' if result.returncode==0 else 'fail'})
        assert not any('fail' in row.values() for row in report['checks']),'Candidate acceptance failed; all requested cases retained'
    except BaseException as exc:report['failure']=repr(exc);raise
    finally:
        try:
            if attempted:
                report['remote_end']=json.loads(ssh(shlex.join(command+['stop']+options)))
                report['service']=report['remote_end']['service']
        except Exception as exc:report['cleanup_failure']=repr(exc);raise
        finally:(folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':main()
