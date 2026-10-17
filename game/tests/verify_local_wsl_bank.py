"""Installed WSL release server through the real localhost UDP relay and UI browser."""
import argparse,datetime,json,math,time
from game.tests.verify_bank_coop import ROOT,BankPeer
from game.tests.verify_frontend import FrontendPeer
from game.tests.verify_coop import until
from game.tools.local_bank_server import query,wsl,config

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-local-wsl-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    cfg=config();peers=[];checks=[];captures=[]
    before=wsl(cfg['distro'],'systemctl','show','bank-coop-local.service','-p','MainPID','-p','ActiveEnterTimestamp','-p','NRestarts').stdout
    def population(count):return until(lambda:(r:=query()) and r['players']==count,30)
    def mark(name,**data):checks.append({'name':name,'status':'pass',**data});print(name,flush=True)
    try:
        population(0)
        browser=FrontendPeer(folder/'browser',True);peers.append(browser);browser.call('click',control='multiplayer')
        until(lambda:browser.state()['discovery']['localhost:24567']['online'],15)
        assert browser.state()['bank_nodes']==0;captures.append(browser.call('capture',name='wsl-localhost-0-of-4')['capture'])
        mark('wsl_localhost_discovery_empty')
        clients=[]
        for i in range(4):
            client=BankPeer(folder/f'client-{i+1}',['--connect=localhost','--port=24567',f'--name=WSL{i+1}','--real-time']);clients.append(client);peers.append(client)
            until(lambda:client.state()['started'] and client.state()['input_enabled'],30);population(i+1)
            if i==0:
                aid=client.state()['local_id'];row=lambda:next(p for p in client.state()['players'] if p['id']==aid)
                start=row()['position'];client.call('input',keys=['S']);time.sleep(.5);client.call('input');time.sleep(.4)
                assert math.dist(start,row()['position'])>.7
                mark('wsl_first_player_enters_and_moves')
        until(lambda:browser.state()['discovery']['localhost:24567']['players']==4,15)
        assert browser.state()['controls']['connect']['disabled'];captures.append(browser.call('capture',name='wsl-localhost-4-of-4')['capture'])
        mark('wsl_localhost_four_independent_peers')
        extra=BankPeer(folder/'fifth',['--connect=localhost','--port=24567','--name=Fifth']);peers.append(extra)
        until(lambda:'满' in extra.state()['status']);assert not extra.state()['players'];population(4)
        mark('wsl_rejects_fifth_peer')
        client=clients.pop();client.call('menu');client.call('click',control='leave_button');population(3)
        until(lambda:browser.state()['discovery']['localhost:24567']['players']==3,15)
        assert not browser.state()['controls']['connect']['disabled'];browser.call('click',control='connect')
        until(lambda:browser.state().get('scene')=='BankExploration' and browser.state().get('input_enabled'),90)
        population(4);browser.call('step',frames=6);captures.append(browser.call('capture',name='wsl-browse-join')['capture'])
        browser.call('act',keys=['Escape']);browser.call('click',control='leave_button')
        until(lambda:browser.state().get('scene')=='MainMenu');population(3)
        mark('wsl_native_browse_join_and_leave')
        for p in clients:p.close();peers.remove(p)
        population(0);until(lambda:browser.state()['discovery']['localhost:24567']['players']==0,15)
        after=wsl(cfg['distro'],'systemctl','show','bank-coop-local.service','-p','MainPID','-p','ActiveEnterTimestamp','-p','NRestarts').stdout
        assert before==after,(before,after)
        (folder/'service-status.txt').write_text(after,encoding='utf8')
        captures.append(browser.call('capture',name='wsl-stays-online-after-leave')['capture'])
        mark('wsl_persistent_service_survives_all_clients_leaving')
        for p in peers:
            text=(p.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-2500:]
    finally:
        for p in reversed(peers):p.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures,'installed_server':cfg,'local_status_after':query()},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
