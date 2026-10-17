"""Two real bank clients cooperate through 200 ms RTT and 5% datagram loss."""
import argparse,datetime,json,socket,time
from game.tests.verify_network_resilience import NetworkPeer
from game.tests.network_fault_proxy import FaultProxy,Profile
from game.tests.verify_coop import until
from game.tools.coop import ROOT

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',required=True,choices=['bank']);p.parse_args()
    folder=ROOT/'logs/sessions'/('bank-network-combat-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir();print(folder,flush=True)
    peers=[];proxies=[];checks=[]
    with socket.socket(type=socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    def fixture(name):
        serial=server.net()['fixture_barrier']+1;server.call('fixture',name=name)
        until(lambda:a.net()['fixture_barrier']==serial and b.net()['fixture_barrier']==serial,20)
    def mark(name,**data):checks.append({'name':name,'status':'pass',**data});print(name,flush=True)
    def enemy(peer):return next(x for x in peer.state()['enemies'] if x['active'])
    def fire(peer,ident):
        old=server.net()['weapons'][ident]['shots'];peer.call('input',buttons=['left']);time.sleep(.06);peer.call('input')
        until(lambda:server.net()['weapons'][ident]['shots']==old+1,8)
        time.sleep(.22)
        assert server.net()['weapons'][ident]['shots']==old+1,'duplicate operation fired twice'
    try:
        server=NetworkPeer(folder/'server',['--server',f'--port={port}']);peers.append(server)
        a=NetworkPeer(folder/'alpha',[]);peers.append(a);b=NetworkPeer(folder/'bravo',[]);peers.append(b)
        for i,client in enumerate([a,b]):
            proxy=FaultProxy(('127.0.0.1',port),Profile('combat_loss5',200,25,.05),18100+i);proxies.append(proxy)
            client.call('fields',nickname=['Alpha','Bravo'][i],port=proxy.port);client.call('click',control='join_button')
        until(lambda:a.net()['started'] and b.net()['started'] and len(server.net()['players'])==2,30)
        aid=str(a.net()['id']);bid=str(b.net()['id']);fixture('firearms_target')
        # Match the target's chest from each actual spawn slot.
        for client,ident in [(a,aid),(b,bid)]:
            x=server.net()['players'][ident]['position'][0]
            client.call('input',mouse=[0,75] if x<20.5 else [-164,69])
        hp=enemy(server)['hp'];fire(a,aid);after_a=enemy(server)['hp'];assert after_a<hp
        fire(b,bid);after_b=enemy(server)['hp'];assert after_b<after_a
        assert server.net()['weapons'][aid]['ammo']['pistol']['clip']==14 and server.net()['weapons'][bid]['ammo']['pistol']['clip']==14
        mark('bank_network_cooperative_damage',hp=[hp,after_a,after_b],ammo=[14,14])
        for _ in range(10):
            if enemy(server)['mode']=='dead':break
            fire(a,aid)
        until(lambda:enemy(a)['mode']==enemy(b)['mode']=='dead',8)
        mark('bank_network_shared_kill_without_duplicate_shots')
        a.call('input',keys=['R']);time.sleep(.06);a.call('input')
        until(lambda:server.net()['weapons'][aid]['ammo']['pistol']['clip']==15,8)
        assert server.net()['weapons'][bid]['ammo']['pistol']['clip']==14
        fixture('door_g_inner_a');a.call('input',keys=['E']);time.sleep(.06);a.call('input')
        until(lambda:a.net()['door']>.98 and b.net()['door']>.98,8)
        mark('bank_network_reload_and_shared_door')
        fixture('default');time.sleep(6)
        assert len(server.state()['enemies'])==84 and sum(x['active'] for x in server.state()['enemies'])==84
        assert a.net()['world_age_ms']<1000 and b.net()['world_age_ms']<1000
        mark('bank_network_live_84_actor_world',snapshot_bytes=server.net()['wire_bytes'])
        for peer in peers:
            log=(peer.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log,log[-2000:]
    finally:
        for peer in reversed(peers):peer.close()
        for proxy in proxies:proxy.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'proxies':[x.report() for x in proxies]},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
