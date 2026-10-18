"""Mixed UDP/TCP peers share one bank; TCP reset resumes the same character."""
import argparse,datetime,json,math,socket,time
from game.tests.verify_network_resilience import NetworkPeer
from game.tests.verify_coop import until
from game.tools.coop import ROOT

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',choices=['bank'],required=True);p.parse_args()
    folder=ROOT/'logs/sessions'/('bank-tcp-recovery-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir();print(folder,flush=True)
    while True:
        with socket.socket() as tcp,socket.socket(type=socket.SOCK_DGRAM) as udp:
            tcp.bind(('0.0.0.0',0));port=tcp.getsockname()[1]
            try:udp.bind(('0.0.0.0',port));break
            except OSError:continue
    peers=[];checks=[];failure=None
    def mark(name,**data):checks.append({'name':name,'status':'pass',**data});print(name,flush=True)
    try:
        server=NetworkPeer(folder/'server',['--server',f'--port={port}','--max-players=2','--prefer-tcp']);peers.append(server)
        a=NetworkPeer(folder/'alpha',['--transport=tcp']);peers.append(a)
        b=NetworkPeer(folder/'bravo',[]);peers.append(b)
        c=NetworkPeer(folder/'outsider',['--transport=tcp']);peers.append(c)
        for client,label in [(a,'TCP'),(b,'UDP')]:client.call('fields',nickname=label,port=port);client.call('click',control='join_button')
        until(lambda:a.net()['started'] and b.net()['started'] and len(server.net()['players'])==2,30)
        assert a.net()['carrier']=='tcp' and b.net()['carrier']=='udp'
        server.call('fixture',name='recovery_state');serial=server.net()['fixture_barrier']
        until(lambda:a.net()['fixture_barrier']==serial and b.net()['fixture_barrier']==serial,15)
        aid=str(a.net()['id']);bid=str(b.net()['id']);until(lambda:a.net()['weapons'][aid]['hp']==73)
        a.call('input',buttons=['left']);time.sleep(.06);a.call('input');until(lambda:server.net()['weapons'][aid]['shots']==1)
        before=server.net();assert before['weapons'][aid]['ammo']['pistol']['clip']==14
        c.call('fields',nickname='Full',port=port);c.call('click',control='join_button');until(lambda:'房间已满' in c.net()['status'],15)
        mark('tcp_udp_shared_capacity_and_damage',players=2)
        started=time.monotonic();a.call('cut_tcp')
        until(lambda:a.net()['recovery']['resumed']>=1 and a.net()['input'] and a.net()['world_age_ms']<500,20)
        after=server.net();new_id=str(a.net()['id'])
        assert new_id!=aid and after['weapons'][new_id]==before['weapons'][aid]
        assert math.dist(after['players'][new_id]['position'],before['players'][aid]['position'])<.2
        assert str(b.net()['id'])==bid and bid in after['players'] and not b.net()['recovery']['retrying']
        assert after['recovery']['reserved']==0 and after['recovery']['occupied']==2
        mark('tcp_socket_reset_recovery',recovery_ms=(time.monotonic()-started)*1000,hp=73,clip=14)
        a.call('menu');a.call('click',control='leave_button');until(lambda:server.net()['recovery']['occupied']==1)
        time.sleep(1.2);assert not a.net()['recovery']['retrying']
        c.call('click',control='join_button');until(lambda:c.net()['started'] and len(server.net()['players'])==2,20)
        mark('tcp_voluntary_leave_and_replacement')
        for peer in peers:
            log=(peer.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log,log[-2000:]
    except Exception as exc:failure=repr(exc);raise
    finally:
        for peer in reversed(peers):peer.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'failure':failure},indent=2),encoding='utf8')

if __name__=='__main__':main()
