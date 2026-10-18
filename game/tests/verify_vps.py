"""Public production-server discovery, real UI entry, four slots and rejoin."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import math
from pathlib import Path
import time
from game.tests.verify_bank_coop import BankPeer
from game.tests.verify_frontend import FrontendPeer
from game.tests.verify_coop import until
from game.tools.coop import ROOT
from game.tools.local_bank_server import query


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--host',default='207.57.124.243');args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-vps-ui-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True)
    print(folder,flush=True);peers=[];checks=[];captures=[];failure=None
    def population(n):return until(lambda:(r:=query(args.host,timeout=2)) and r['players']==n,60)
    def mark(name,**values):checks.append({'name':name,'status':'pass',**values});print(name,flush=True)
    def state_ready(peer):return until(lambda:(s:=peer.state()) and s.get('started') and s.get('input_enabled') and s,90)
    try:
        population(0)
        browser=FrontendPeer(folder/'browser',True);peers.append(browser)
        browser.call('click',control='multiplayer');target=args.host+':24567'
        assert target in browser.state()['discovery'],'Public server must be present without typing an address'
        until(lambda:browser.state()['discovery'][target]['online'],30)
        control=next(k for k,v in browser.state()['controls'].items() if v.get('server_id')==target)
        browser.call('click',control=control)
        assert browser.state()['bank_nodes']==0 and not browser.state()['controls']['connect']['disabled']
        captures.append(browser.call('capture',name='vps-online-empty')['capture'])
        mark('vps_default_discovery_no_scene_load',row=browser.state()['discovery'][target])
        first=BankPeer(folder/'client-1',['--connect='+args.host,'--port=24567','--name=VPS1','--real-time']);peers.append(first)
        s=state_ready(first);population(1);aid=s['local_id']
        before=next(p for p in s['players'] if p['id']==aid)['position']
        first.call('input',keys=['S']);time.sleep(.65);first.call('input');time.sleep(1)
        s=first.state();after=next(p for p in s['players'] if p['id']==aid)['position']
        assert math.dist(before,after)>.7,(before,after)
        first.call('input',buttons=['left']);time.sleep(.1);first.call('input')
        until(lambda:first.state()['combat'][str(aid)]['shots']>=1,15)
        mark('vps_first_player_immediate_move_fire',metres=math.dist(before,after))
        clients=[first]
        with ThreadPoolExecutor(max_workers=3) as pool:
            futures=[pool.submit(BankPeer,folder/f'client-{i}', ['--connect='+args.host,'--port=24567',f'--name=VPS{i}','--real-time']) for i in [2,3,4]]
            for f in futures:client=f.result();clients.append(client);peers.append(client)
        for client in clients:state_ready(client)
        population(4)
        until(lambda:all(len(p.state()['players'])==4 for p in clients),30)
        until(lambda:browser.state()['discovery'][target]['players']==4,30)
        assert browser.state()['controls']['connect']['disabled']
        captures.append(browser.call('capture',name='vps-online-full')['capture'])
        assert all(c.state()['combat'][str(aid)]['shots']>=1 for c in clients)
        mark('vps_four_clients_authoritative_weapon_and_capacity')
        extra=BankPeer(folder/'fifth',['--connect='+args.host,'--port=24567','--name=Fifth']);peers.append(extra)
        until(lambda:'满' in extra.state()['status'],30);assert not extra.state()['players'];population(4)
        mark('vps_fifth_client_rejected')
        last=clients.pop();last.call('menu');last.call('click',control='leave_button');population(3)
        until(lambda:browser.state()['discovery'][target]['players']==3,30)
        assert not browser.state()['controls']['connect']['disabled']
        browser.call('click',control='connect')
        until(lambda:browser.state().get('scene')=='BankExploration' and browser.state().get('input_enabled'),120)
        population(4);browser.call('step',frames=12)
        captures.append(browser.call('capture',name='vps-browser-entered-bank')['capture'])
        assert browser.state()['lighting']['loaded'] and browser.state()['lighting']['meshes']==481
        browser.call('act',keys=['Escape']);browser.call('click',control='leave_button')
        until(lambda:browser.state().get('scene')=='MainMenu',60);population(3)
        mark('vps_native_browser_join_leave_and_current_bake')
        for client in clients:
            if client.state().get('input_enabled'):client.call('menu')
            client.call('click',control='leave_button')
        population(0)
        until(lambda:browser.state()['discovery'][target]['players']==0,30)
        captures.append(browser.call('capture',name='vps-still-online-after-leave')['capture'])
        mark('vps_service_persists_empty')
        for peer in peers:
            log=(peer.folder/'engine.log').read_text(encoding='utf8')
            assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log,log[-3000:]
    except Exception as exc:failure=repr(exc);raise
    finally:
        for peer in reversed(peers):peer.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures,'failure':failure,'host':args.host,
            'status_after':query(args.host,timeout=2)},ensure_ascii=False,indent=2),encoding='utf8')


if __name__=='__main__':main()
