"""Real main-menu join, interrupted connection HUD, and native cancel-reconnect UI."""
import argparse,datetime,json,socket,time
from game.tests.verify_bank_coop import BankPeer,ROOT
from game.tests.verify_frontend import FrontendPeer
from game.tests.verify_coop import until
from game.tests.network_fault_proxy import FaultProxy,Profile

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',required=True,choices=['bank']);p.parse_args()
    folder=ROOT/'logs/sessions'/('bank-network-ui-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir();print(folder,flush=True)
    peers=[];proxy=None;captures=[];checks=[]
    with socket.socket(type=socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    try:
        server=BankPeer(folder/'server',['--server',f'--port={port}','--real-time']);peers.append(server)
        proxy=FaultProxy(('127.0.0.1',port),Profile('ui',100,10),18003)
        client=FrontendPeer(folder/'client',True);peers.append(client)
        client.call('click',control='multiplayer');client.call('click',control='join_tab')
        client.call('fields',values={'nickname':'Network UI','address':'127.0.0.1','port':str(proxy.port)});client.call('click',control='connect')
        until(lambda:client.state().get('started'),90)
        server.call('fixture',name='door_g_inner_a');client.call('step',frames=18)
        captures.append(client.call('capture',name='connected-hud')['capture'])
        proxy.blackout(25)
        def state():return client.call('step',frames=3)['state']
        until(lambda:state().get('coop',{}).get('network_stalled'),8)
        captures.append(client.call('capture',name='network-interrupted')['capture'])
        until(lambda:state().get('coop',{}).get('recovery',{}).get('retrying'),18)
        status=client.state();button=status['controls']['leave_button'];assert button['visible'] and button['text']=='取消重连'
        x,y,w,h=button['rect'];assert x>=0 and y>=0 and x+w<=1280 and y+h<=720,button
        captures.append(client.call('capture',name='cancel-reconnect')['capture'])
        client.call('click',control='leave_button')
        until(lambda:client.state().get('scene')=='MainMenu',10)
        time.sleep(1.2);assert client.state()['scene']=='MainMenu' and client.state()['bank_nodes']==0
        captures.append(client.call('capture',name='canceled-back-to-browser')['capture'])
        checks.append({'name':'bank_network_native_ui_cancel','status':'pass','normal_input':True})
        for peer in peers:
            text=(peer.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-1600:]
    finally:
        for peer in reversed(peers):peer.close()
        if proxy:proxy.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures,'proxy':proxy.report() if proxy else None},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
