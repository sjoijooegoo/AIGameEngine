"""Bank: real blackout, native fire/leave/join, reserved capacity and state recovery."""
import argparse,datetime,json,math,socket,time
from game.tests.verify_network_resilience import NetworkPeer
from game.tests.network_fault_proxy import FaultProxy,Profile
from game.tests.verify_coop import until
from game.tools.coop import ROOT

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',required=True,choices=['bank']);args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-network-recovery-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir();print(folder,flush=True)
    peers=[];proxies=[];checks=[];observations=[]
    def mark(name,**values):checks.append({'name':name,'status':'pass',**values});print(name,values,flush=True)
    with socket.socket(type=socket.SOCK_DGRAM) as reserve:reserve.bind(('127.0.0.1',0));port=reserve.getsockname()[1]
    try:
        server=NetworkPeer(folder/'server',['--server',f'--port={port}','--max-players=2']);peers.append(server)
        a=NetworkPeer(folder/'alpha',[]);peers.append(a)
        b=NetworkPeer(folder/'bravo',[]);peers.append(b)
        c=NetworkPeer(folder/'outsider',[]);peers.append(c)
        proxy=FaultProxy(('127.0.0.1',port),Profile('recovery',100,10),18001);proxies.append(proxy)
        for peer,name,target in [(a,'Alpha',proxy.port),(b,'Bravo',port)]:
            peer.call('fields',nickname=name,port=target);peer.call('click',control='join_button')
        until(lambda:len(a.net()['players'])==2 and a.net()['started'] and b.net()['started'],25)
        server.call('fixture',name='recovery_state')
        until(lambda:a.net()['fixture_barrier']==server.net()['fixture_barrier'] and len(a.net()['weapons'])==2,20)
        aid=str(a.net()['id']);until(lambda:a.net()['weapons'][aid]['hp']==73)
        a.call('input',buttons=['left']);time.sleep(.06);a.call('input')
        until(lambda:server.net()['weapons'][aid]['shots']==1)
        before=server.net();assert before['weapons'][aid]['ammo']['pistol']['clip']==14
        started=time.monotonic();proxy.blackout(25)
        # A click made during the outage must never execute after recovery.
        a.call('input',buttons=['left']);time.sleep(.06);a.call('input')
        end=time.monotonic()+22
        while time.monotonic()<end:
            ss,aa=server.net(),a.net();observations.append({'elapsed':time.monotonic()-started,'server':ss,'client':aa})
            assert str(b.net()['id']) in ss['players'],'unaffected teammate disconnected'
            if ss['recovery']['reserved']==1:break
            time.sleep(.15)
        assert server.net()['recovery']['reserved']==1,'server never retained the disconnected character'
        assert server.net()['recovery']['occupied']==2
        c.call('fields',nickname='Outsider',port=port);c.call('click',control='join_button')
        until(lambda:'房间已满' in c.net()['status'],12)
        assert not c.net()['players']
        mark('bank_network_capacity_reservation',occupied=2,connected=1)
        until(lambda:a.net()['recovery']['resumed']>=1 and a.net()['input'] and a.net()['world_age_ms']<500,45)
        after=server.net();new_id=str(a.net()['id']);after_weapon=after['weapons'][new_id]
        assert after_weapon==before['weapons'][aid],(before['weapons'][aid],after_weapon)
        assert math.dist(after['players'][new_id]['position'],before['players'][aid]['position'])<.2
        assert after['recovery']['reserved']==0 and after['recovery']['occupied']==2
        mark('bank_network_recovery',blackout_seconds=25,recovery_after_link_ms=max(0,(time.monotonic()-started-25)*1000),hp=after_weapon['hp'],ammo=after_weapon['ammo']['pistol']['clip'],stale_click_did_not_fire=True)
        a.call('menu');a.call('click',control='leave_button')
        until(lambda:server.net()['recovery']['occupied']==1 and not a.net()['players'])
        time.sleep(1.1);assert not a.net()['recovery']['retrying']
        c.call('click',control='join_button');until(lambda:c.net()['started'] and len(server.net()['players'])==2,20)
        mark('bank_network_voluntary_leave_releases_slot')
        c.call('menu');c.call('click',control='leave_button');until(lambda:len(server.net()['players'])==1)
        delayed=FaultProxy(('127.0.0.1',port),Profile('join_reset_race',500),18002);proxies.append(delayed)
        c.call('fields',port=delayed.port);c.call('click',control='join_button')
        until(lambda:len(server.net()['players'])==2,20)
        server.call('fixture',name='firearms_range')
        until(lambda:c.net()['started'] and c.net()['round']==server.net()['round'],20)
        mark('bank_network_join_during_round_reset')
        for peer in peers:
            log=(peer.folder/'engine.log').read_text(encoding='utf8');assert '\nERROR:' not in log and 'SCRIPT ERROR' not in log,log[-2500:]
        assert not proxy.report()['error']
    finally:
        for peer in reversed(peers):peer.close()
        for proxy in proxies:proxy.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'observations':observations,'proxies':[x.report() for x in proxies]},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
