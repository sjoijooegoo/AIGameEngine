"""Real UDP discovery, immediate entry, hard capacity, release/rejoin and native browse UI."""
import argparse,datetime,json,socket,time,secrets
from game.tests.verify_bank_coop import ROOT,BankPeer
from game.tests.verify_frontend import FrontendPeer
from game.tests.verify_coop import until
from game.tools.local_bank_server import query

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.add_argument('--rendered',action='store_true');args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-open-server-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    peers=[];checks=[];captures=[]
    while True:
        with socket.socket(type=socket.SOCK_DGRAM) as sock:
            port=20000+secrets.randbelow(4000)
            try:sock.bind(('0.0.0.0',port))
            except OSError:continue
            with socket.socket(type=socket.SOCK_DGRAM) as status:
                try:status.bind(('0.0.0.0',port+1));break
                except OSError:continue
    def mark(name,**data):checks.append({'name':name,'status':'pass',**data});print(name,flush=True)
    try:
        server=BankPeer(folder/'server',['--server',f'--port={port}','--max-players=4','--real-time']);peers.append(server)
        info=query(port=port);assert info and info['players']==0 and info['capacity']==4,info
        mark('discovery_empty_server_without_player_slot',info=info)
        browser=FrontendPeer(folder/'browser',args.rendered);peers.append(browser)
        browser.call('click',control='multiplayer');browser.call('click',control='join_tab')
        browser.call('fields',values={'address':'127.0.0.1','port':str(port),'nickname':'BrowserPlayer'});browser.call('click',control='find_tab')
        target=f'localhost:{port}'
        until(lambda:browser.state()['discovery'].get(target,{}).get('online'),15)
        control=next(k for k,v in browser.state()['controls'].items() if v.get('server_id')==target)
        browser.call('click',control=control)
        assert not browser.state()['controls']['connect']['disabled'] and browser.state()['bank_nodes']==0
        if args.rendered:captures.append(browser.call('capture',name='empty-0-of-4')['capture'])
        mark('discovery_native_find_ui_no_scene_load')
        clients=[]
        def step(n=12):
            for _ in range(n//3):
                for c in clients:c.call('step',frames=3)
        for i in range(4):
            c=BankPeer(folder/f'client-{i+1}',['--connect=127.0.0.1',f'--port={port}',f'--name=Player{i+1}']);clients.append(c);peers.append(c)
            until(lambda:len(server.state()['players'])==i+1);step(18)
            assert c.state()['started'] and c.state()['input_enabled']
            assert query(port=port)['players']==i+1
            if i==0:
                before=c.state()['players'][0]['position'];c.call('input',keys=['S']);step(30);c.call('input');step(12)
                after=c.state()['players'][0]['position'];assert abs(after[0]-before[0])+abs(after[2]-before[2])>.5
                mark('open_server_first_player_moves_immediately')
        until(lambda:browser.state()['discovery'][target]['players']==4,15)
        assert browser.state()['controls']['connect']['disabled']
        browser.call('click',control='connect');assert browser.state()['bank_nodes']==0
        if args.rendered:captures.append(browser.call('capture',name='full-4-of-4')['capture'])
        fifth=BankPeer(folder/'rejected',['--connect=127.0.0.1',f'--port={port}','--name=Fifth']);peers.append(fifth)
        until(lambda:'满' in fifth.state()['status'],15)
        assert not fifth.state()['players'] and len(server.state()['players'])==4
        mark('open_server_hard_four_player_limit',server_message=fifth.state()['status'],ui_disabled=True)
        leaving=clients.pop();leaving.call('menu');leaving.call('click',control='leave_button')
        until(lambda:len(server.state()['players'])==3)
        until(lambda:browser.state()['discovery'][target]['players']==3,15)
        assert not browser.state()['controls']['connect']['disabled']
        browser.call('click',control='connect')
        until(lambda:browser.state().get('scene')=='BankExploration' and not browser.state()['loading'],90)
        for _ in range(30):
            step(3);s=browser.call('step',frames=3)['state']
            if s.get('started') and s.get('input_enabled'):break
        assert s['started'] and s['input_enabled'] and len(server.state()['players'])==4,s.get('message')
        mark('open_server_browse_join_freed_slot')
        server.close();peers.remove(server)
        until(lambda:'断开' in clients[0].state()['status'],20)
        mark('open_server_disconnect_cleanup')
        for p in peers:
            text=(p.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-2500:]
    finally:
        for p in reversed(peers):p.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
