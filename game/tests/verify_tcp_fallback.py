"""Normal join button falls back from an unavailable UDP endpoint to live TCP."""
import argparse,datetime,json,socket,time
from game.tests.verify_network_resilience import NetworkPeer
from game.tests.verify_coop import until
from game.tools.coop import ROOT

def port():
    with socket.socket() as tcp,socket.socket(type=socket.SOCK_DGRAM) as udp:
        tcp.bind(('127.0.0.2',0));value=tcp.getsockname()[1];udp.bind(('127.0.0.2',value));return value

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',required=True,choices=['bank']);p.parse_args()
    folder=ROOT/'logs/sessions'/('bank-tcp-fallback-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir();print(folder,flush=True)
    peers=[];report={'checks':[],'failure':None};native=port();fallback=port()
    try:
        server=NetworkPeer(folder/'server',['--server',f'--port={native}','--prefer-tcp']);peers.append(server)
        server.call('tcp_only_fixture',port=fallback)
        client=NetworkPeer(folder/'client',[]);peers.append(client)
        client.call('fields',address='127.0.0.2',port=fallback,nickname='Fallback')
        start=time.monotonic();client.call('click',control='join_button')
        until(lambda:client.net()['started'] and client.net()['input'] and client.net()['carrier']=='tcp',45)
        client.call('input',keys=['S']);time.sleep(.6);client.call('input')
        assert len(server.net()['players'])==1
        log=(client.folder/'engine.log').read_text(encoding='utf8')
        assert 'UDP 连接不稳定' in log and 'SCRIPT ERROR' not in log and '\nERROR:' not in log
        report['checks'].append({'name':'udp_unavailable_tcp_fallback_native_join','status':'pass','elapsed_ms':(time.monotonic()-start)*1000})
        client.call('menu');client.call('click',control='leave_button');until(lambda:server.net()['recovery']['occupied']==0)
    except BaseException as exc:report['failure']=repr(exc);raise
    finally:
        for peer in reversed(peers):peer.close()
        (folder/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')

if __name__=='__main__':main()
