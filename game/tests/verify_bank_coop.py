"""Real bank + dedicated ENet + two clients; normal input, no legacy worlds."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import math
from pathlib import Path
import subprocess
import socket
import time
from game.tests.verify_coop import Peer, until
from game.tools.coop import ROOT, HIDDEN, godot


class BankPeer(Peer):
    def __init__(self, folder, args, rendered=False):
        folder.mkdir(); self.folder=folder; self.serial=0
        self.log=(folder/'engine.log').open('w',encoding='utf8')
        executable=godot();direct=executable.with_name(executable.name.replace('_console.exe','.exe'))
        if direct.is_file():executable=direct
        cmd=[str(executable),'--path',str(ROOT/'game/runtime'),'--max-fps','120',
             '--resolution','1280x720','--script',str(ROOT/'game/tests/bank_coop_driver.gd')]
        if not rendered:cmd+=['--headless']
        cmd+=['--',f'--test-session={folder.as_posix()}','--performance-benchmark','--coop',*args]
        self.process=subprocess.Popen(cmd,stdout=self.log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=HIDDEN)
        (folder/'launch.json').write_text(json.dumps({'command':cmd,'pid':self.process.pid},indent=2),encoding='utf8')
        self.wait_file(folder/'ready.json',90)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--rendered',action='store_true')
    args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-combat-coop-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    folder.mkdir(parents=True);peers=[];checks=[];captures=[];pool=ThreadPoolExecutor(max_workers=4)
    print(folder,flush=True)
    with socket.socket(type=socket.SOCK_DGRAM) as reservation:
        reservation.bind(('127.0.0.1',0));port=reservation.getsockname()[1]
    def create(label,flags):
        p=BankPeer(folder/label,flags,args.rendered and label!='server');peers.append(p);return p
    def mark(name,**detail):checks.append({'name':name,'status':'pass',**detail});print(name,flush=True)
    def frames(count,clients=None):
        for _ in range(count//3):
            futures=[pool.submit(c.call,'step',frames=3) for c in (clients or [a,b])]
            for f in futures:f.result()
            server.call('step',frames=3)
    def combat(p,id):return p.state()['combat'][str(id)]
    def enemy(p):return next(e for e in p.state()['enemies'] if e['active'])
    def player(p,id):return next(e for e in p.state()['players'] if e['id']==id)
    def fixture(name):
        server.call('fixture',name=name);frames(12)
    shot_index=0
    def fire(p):
        nonlocal shot_index
        shot_index+=1
        p.call('input',buttons=['left']);frames(3);p.call('input')
        for i in range(7):
            frames(3)
            if args.rendered and shot_index<=6 and i in [0,2,4,6]:captures.append(b.call('capture')['capture'])
    def capture(p):
        if args.rendered:captures.append(p.call('capture')['capture'])
    try:
        server=create('server',['--server',f'--port={port}'])
        a=create('alpha',[]);b=create('bravo',[])
        capture(a)
        for p,name in [(a,'Alpha'),(b,'Bravo')]:
            p.call('fields',nickname=name,port=port);p.call('click',control='join_button')
        until(lambda:len(server.state()['players'])==2 and len(a.state()['players'])==2 and len(b.state()['players'])==2,30);frames(30)
        aid=a.state()['local_id'];bid=b.state()['local_id']
        assert a.state()['bank_scene'] and len(server.state()['enemies'])==84
        assert len(a.state()['combat'])==2 and len(b.state()['combat'])==2
        mark('bank_session_ui_join_two',population=84);capture(a)
        lobby_enemies=server.state()['enemies'];frames(120)
        assert server.state()['enemies']==lobby_enemies and all(c['hp']==100 for c in server.state()['combat'].values())
        mark('bank_lobby_world_waits')
        (a if a.state()['leader']==aid else b).call('click',control='start_button');frames(18)
        assert server.state()['started'] and a.state()['started'] and b.state()['started']
        mark('bank_lobby_start_ui')
        before=player(server,aid)['position'];a.call('input',keys=['S']);frames(30);a.call('input');frames(12)
        distance=math.dist(before,player(server,aid)['position']);assert distance>.5,distance
        assert math.dist(player(b,aid)['target'],player(server,aid)['position'])<.1
        mark('bank_team_movement',distance=distance)
        fixture('firearms_target')
        # Aim at chest height. Bravo aims diagonally at the same target.
        a.call('input',mouse=[0,75]);b.call('input',mouse=[-164,69]);frames(6)
        initial=enemy(server)['hp'];fire(a);after_a=enemy(server)['hp']
        assert after_a<initial,(initial,after_a,combat(server,aid)['last_shot'])
        fire(b);after_b=enemy(server)['hp'];assert after_b<after_a,(after_a,after_b,combat(server,bid)['last_shot'])
        assert combat(server,aid)['ammo']['pistol']['clip']==14 and combat(server,bid)['ammo']['pistol']['clip']==14
        mark('bank_shared_damage_and_separate_ammo',hp=[initial,after_a,after_b]);capture(b)
        for _ in range(12):
            if enemy(server)['mode']=='dead':break
            fire(a)
        frames(12);assert enemy(server)['mode']=='dead'
        assert enemy(a)['mode']==enemy(b)['mode']=='dead'
        assert a.state()['kills']==b.state()['kills']==1
        mark('bank_shared_kill_and_corpse');capture(b)
        a.call('input',keys=['R']);frames(3);a.call('input');frames(135)
        assert combat(server,aid)['ammo']['pistol']['clip']==15
        assert combat(server,bid)['ammo']['pistol']['clip']==14
        mark('bank_server_reload')
        # Opening the local menu must neither pause the server nor auto-fire.
        a.call('menu');t=server.state()['tick'];frames(30)
        assert server.state()['tick']==t+30 and player(server,aid)['motion']=='idle'
        a.call('click',control='resume_button');mark('bank_local_menu_does_not_pause')
        fixture('firearms_wall');a.call('input',mouse=[0,0]);b.call('input',mouse=[0,0]);frames(6)
        hp=enemy(server)['hp'];fire(a);assert enemy(server)['hp']==hp
        mark('bank_wall_blocks_shot')
        fixture('door_g_inner_a')
        before=player(server,aid)['position'];a.call('input',keys=['E']);frames(3);a.call('input');frames(96)
        door=server.state()['doors']['g_inner'];assert door['progress']>.98,door
        assert abs(b.state()['doors']['g_inner']['progress']-door['progress'])<.1
        capture(b)
        a.call('input',keys=['W']);frames(51);a.call('input');frames(9)
        after=player(server,aid)['position']
        assert (before[0]-26)*(after[0]-26)<0,(before,after)
        mark('bank_shared_door_and_crossing',before=before,after=after)
        fixture('combat_grab')
        b.call('input',mouse=[-356,112]);frames(3);b.call('input')
        for _ in range(40):
            if combat(server,aid)['grabbed']:break
            frames(3)
        assert combat(server,aid)['grabbed'],combat(server,aid)
        hp=enemy(server)['hp'];fire(b)
        assert enemy(server)['hp']<hp,combat(server,bid)['last_shot']
        assert not combat(server,aid)['grabbed']
        mark('bank_teammate_rescues_grab');capture(b)
        fixture('combat_grab');frames(150)
        assert combat(server,aid)['hp']<100 or combat(server,bid)['hp']<100
        assert combat(a,aid)['hp']==combat(server,aid)['hp']
        mark('bank_server_infected_damage');capture(a)
        fixture('coop_wipe')
        for _ in range(90):
            if server.state()['team_wiped']:break
            frames(12)
        assert server.state()['team_wiped'],server.state()['combat']
        frames(12);a.call('menu');capture(a);a.call('click',control='restart_button');frames(24)
        assert not server.state()['team_wiped'] and all(c['hp']==100 for c in server.state()['combat'].values())
        assert sum(e['active'] and e['mode']!='dead' for e in server.state()['enemies'])==84
        mark('bank_team_wipe_restart',fixture='both players start with 5 HP; normal enemy attacks')
        fixture('firearms_target')
        # Actual leave + reconnect; late peer receives the existing fight.
        hp=enemy(server)['hp'];b.call('menu');b.call('click',control='leave_button')
        until(lambda:len(server.state()['players'])==1)
        b.call('click',control='join_button');until(lambda:len(server.state()['players'])==2);frames(18)
        assert enemy(b)['hp']==enemy(server)['hp'] and len(b.state()['combat'])==2
        mark('bank_late_join_existing_world',enemy_hp=hp)
        for p in [a,b]:
            if p.state().get('input_enabled',True):p.call('menu')
            p.call('click',control='leave_button')
        until(lambda:not server.state()['players'])
        for p in [a,b]:p.call('click',control='join_button')
        until(lambda:len(a.state()['players'])==2 and len(b.state()['players'])==2);frames(18)
        assert not server.state()['started'] and sum(e['active'] for e in server.state()['enemies'])==84
        mark('bank_empty_room_starts_fresh')
        server.close();until(lambda:'断开' in a.state()['status'],15)
        assert not a.state()['players'];mark('bank_server_loss_cleanup')
        for p in peers:
            log=(p.folder/'engine.log').read_text(encoding='utf8')
            assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log,log[-2500:]
    finally:
        for p in peers:p.close()
        pool.shutdown()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures},ensure_ascii=False,indent=2),encoding='utf8')


if __name__=='__main__':main()
