"""Create the local dedicated server through the actual bank UI, then join it."""
import argparse
import datetime
import json
import time
import socket
from concurrent.futures import ThreadPoolExecutor
from game.tests.verify_bank_coop import BankPeer, ROOT
from game.tests.verify_coop import until


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.add_argument('--rendered',action='store_true');args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-session-ui-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True)
    print(folder,flush=True);peers=[];checks=[];captures=[]
    with socket.socket(type=socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1',0));port=reservation.getsockname()[1]
    try:
        a=BankPeer(folder/'host',[],args.rendered);peers.append(a)
        a.call('fields',nickname='Host',port=port)
        if args.rendered:captures.append(a.call('capture')['capture'])
        a.call('click',control='create_button')
        for _ in range(90):
            a.call('step',frames=30)
            if len(a.state()['players'])==1:break
        assert len(a.state()['players'])==1,a.state()['status']
        assert a.state()['local_server_pid']>0 and not a.state()['server']
        checks.append({'name':'bank_ui_create_dedicated_process','status':'pass','pid':a.state()['local_server_pid']});print(checks[-1]['name'],flush=True)
        b=BankPeer(folder/'guest',[],args.rendered);peers.append(b)
        b.call('fields',nickname='Guest',port=port);b.call('click',control='join_button')
        until(lambda:len(a.state()['players'])==2 and len(b.state()['players'])==2,30)
        for p in peers:p.call('step',frames=3)
        if args.rendered:captures.append(a.call('capture')['capture'])
        a.call('click',control='start_button');until(lambda:a.state()['started'] and b.state()['started'])
        b.call('input',keys=['S']);before=b.state()['players']
        with ThreadPoolExecutor(max_workers=2) as pool:
            for _ in range(12):
                futures=[pool.submit(p.call,'step',frames=3) for p in peers]
                for future in futures:future.result()
                if args.rendered and _ in [0,3,6,9,11]:
                    guest=next(row for row in a.state()['players'] if row['id']!=a.state()['local_id']);x,y,z=guest['position']
                    a.call('view',position=[x+1.5,y+1.5,z+2.2],target=[x,y+1,z])
                    captures.append(a.call('capture')['capture'])
        b.call('input');a.call('step',frames=3);b.call('step',frames=3)
        assert b.state()['players']!=before
        checks.append({'name':'bank_ui_start_real_time_two_clients','status':'pass'});print(checks[-1]['name'],flush=True)
        a.call('menu');a.call('click',control='leave_button')
        until(lambda:'断开' in b.state()['status'],20)
        assert a.state()['local_server_pid']==-1 and not b.state()['players']
        checks.append({'name':'bank_ui_host_closes_owned_server','status':'pass'});print(checks[-1]['name'],flush=True)
    finally:
        for p in peers:p.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures},indent=2),encoding='utf8')


if __name__=='__main__':main()
