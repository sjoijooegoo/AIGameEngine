"""Bounded normal-input teammate walk, with an inspection camera in the real bank."""
import argparse
import datetime
import json
import socket
from concurrent.futures import ThreadPoolExecutor
from game.tests.verify_bank_coop import ROOT,BankPeer
from game.tests.verify_coop import until
from engine.tools.sequence import build


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-teammate-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    with socket.socket(type=socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    peers=[];frames=[]
    try:
        server=BankPeer(folder/'server',['--server',f'--port={port}']);peers.append(server)
        a=BankPeer(folder/'actor',[f'--connect=127.0.0.1',f'--port={port}','--name=Alpha']);peers.append(a)
        b=BankPeer(folder/'observer',[f'--connect=127.0.0.1',f'--port={port}','--name=Bravo'],True);peers.append(b)
        until(lambda:len(b.state()['players'])==2 and len(a.state()['players'])==2)
        def step(count):
            for _ in range(count//3):
                for c in [a,b]:c.call('step',frames=3)
                server.call('step',frames=3)
        step(12);a.call('click',control='start_button');step(12)
        server.call('fixture',name='firearms_range');step(12);a.call('input',keys=['W'])
        aid=a.state()['local_id']
        for _ in range(10):
            step(6);state=b.state();player=next(p for p in state['players'] if p['id']==aid);x,y,z=player['position']
            b.call('view',position=[x+.8,y+1.55,z-2.6],target=[x,y+.95,z])
            image=b.call('capture')['capture'];frames.append({'path':image,'simulation_time':state['bank_tick']/60,'state':player})
        a.call('input')
        path=folder/'observer/walk.sequence.json';path.write_text(json.dumps({'name':'walk','fps':10,'interval':6,'frames':frames},ensure_ascii=False,indent=2),encoding='utf8')
        result=build(path,.25);(folder/'report.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(result,flush=True)
    finally:
        for p in reversed(peers):p.close()


if __name__=='__main__':main()
