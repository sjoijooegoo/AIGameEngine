"""Standalone startup, single-player entry and two-client UI connection flow."""
from __future__ import annotations
import argparse
import datetime
import json
import math
import socket
import subprocess
import time
from game.tests.verify_coop import Peer, until
from game.tools.coop import ROOT, HIDDEN, godot


class FrontendPeer(Peer):
    def __init__(self, folder, rendered=False):
        folder.mkdir(); self.folder=folder; self.serial=0
        self.log=(folder/'engine.log').open('w',encoding='utf8')
        executable=godot(); direct=executable.with_name(executable.name.replace('_console.exe','.exe'))
        if direct.is_file(): executable=direct
        cmd=[str(executable),'--path',str(ROOT/'game/runtime'),'--max-fps','120','--resolution','1280x720',
             '--script',str(ROOT/'game/tests/frontend_driver.gd')]
        if not rendered:cmd+=['--headless']
        cmd+=['--',f'--test-session={folder.as_posix()}','--performance-benchmark']
        self.process=subprocess.Popen(cmd,stdout=self.log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=HIDDEN)
        (folder/'launch.json').write_text(json.dumps({'command':cmd,'pid':self.process.pid},indent=2))
        self.wait_file(folder/'ready.json',90)

    def call(self,command,**args):
        # Scene construction is synchronous after background resource loading.
        return super().call(command,**args)

    def wait_file(self,path,timeout=90):
        return super().wait_file(path,timeout)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--rendered',action='store_true');args=parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-frontend-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    folder.mkdir(parents=True);peers=[];checks=[];captures=[]
    print(folder,flush=True)
    def mark(name,**details):checks.append(dict(name=name,status='pass',**details));print(name,flush=True)
    def capture(peer,name):
        if args.rendered:captures.append(peer.call('capture',name=name)['capture'])
    def page(peer,name):return until(lambda:(lambda s:s if s.get('scene')=='MainMenu' and s['page']==name else False)(peer.state()),90)
    def bank(peer):return until(lambda:(lambda s:s if s.get('scene')=='BankExploration' and not s['loading'] else False)(peer.state()),90)
    def spin(peer):return peer.call('step',frames=3)['state']
    def connected(peer,count):return until(lambda:(lambda s:s if len(s.get('coop',{}).get('players',[]))==count else False)(spin(peer)),90)
    def port():
        with socket.socket(type=socket.SOCK_DGRAM) as sock:sock.bind(('127.0.0.1',0));return sock.getsockname()[1]
    try:
        a=FrontendPeer(folder/'alpha',args.rendered);peers.append(a)
        s=a.state();assert s['scene']=='MainMenu' and s['bank_nodes']==0 and not s['bank_cached'],s
        capture(a,'01-main-menu');a.call('click',control='multiplayer');s=page(a,'multiplayer')
        assert s['bank_nodes']==0 and not s['bank_cached'];capture(a,'02-server-join')
        a.call('fields',values={'nickname':'Alpha','address':'','port':'24567'});a.call('click',control='connect')
        s=a.state();assert s['message'] and s['bank_nodes']==0
        a.call('fields',values={'address':'127.0.0.1','port':'0'});a.call('click',control='connect');assert a.state()['message']
        mark('frontend_lightweight_and_validation',bank_nodes=0,bank_resource_cached=False)
        a.call('click',control='back');a.call('click',control='single');s=bank(a);a.call('step',frames=1);s=a.state()
        assert s['lighting']['loaded'] and s['lighting']['meshes']==481,s['lighting']
        active=[e for e in s['enemies'] if e['active']]
        near=[e for e in active if abs(e['position'][1]-.04)<1.5 and math.dist((e['position'][0],e['position'][2]),(23,8.2))<8]
        assert not near and len(active)==77,(near,len(active))
        capture(a,'03-single-spawn');before=s['position'];a.call('act',keys=['W'],frames=30);s=a.state();assert math.dist(before,s['position'])>.6
        a.call('step',frames=300);assert a.state()['hp']==100
        a.call('act',keys=['Escape']);a.call('click',control='to_title');s=page(a,'home');assert s['bank_nodes']==0
        mark('frontend_solo_spawn_bake_and_return',active_enemies=77,baked_meshes=481,real_movement=True)
        a.call('click',control='multiplayer');a.call('fields',values={'nickname':'Alpha','address':'127.0.0.1','port':str(port())})
        a.call('click',control='connect');bank(a)
        until(lambda:a.call('step',frames=60)['state']['scene']=='MainMenu',40)
        s=page(a,'multiplayer');assert s['message'] and s['controls']['nickname']['text']=='Alpha' and s['bank_nodes']==0
        capture(a,'04-connection-failed');mark('frontend_failure_returns_with_fields',message=s['message'])
        p=port();a.call('click',control='create_tab');a.call('fields',values={'port':str(p)})
        capture(a,'05-create-session');a.call('click',control='connect');bank(a);s=connected(a,1)
        assert not s['started'] and s['controls']['start_button']['disabled'];server_pid=s['server_pid']
        b=FrontendPeer(folder/'bravo',args.rendered);peers.append(b)
        b.call('click',control='multiplayer');b.call('fields',values={'nickname':'Bravo','address':'127.0.0.1','port':str(p)})
        b.call('click',control='connect');bank(b);connected(b,2);s=connected(a,2);capture(a,'06-two-player-lobby')
        assert not s['controls']['start_button']['disabled'] and b.state()['controls']['start_button']['disabled']
        for value in s['controls'].values():
            if value['visible']:
                x,y,w,h=value['rect'];assert min(x,y)>=0 and x+w<=1281 and y+h<=721,value
        a.call('act',keys=['Escape']);assert not a.state()['input_enabled'],'Escape must not bypass the lobby'
        a.call('click',control='start_button');until(lambda:spin(a)['started'] and spin(b)['started'],15)
        before=a.state()['position'];a.call('act',keys=['W'],frames=45);spin(b);s=a.state();assert math.dist(before,s['position'])>.6
        assert b.state()['input_enabled'];capture(b,'07-coop-entered')
        mark('frontend_two_clients_create_join_and_start',server_pid=server_pid,players=2,real_movement=True)
        a.call('act',keys=['Escape']);a.call('click',control='leave_button');page(a,'multiplayer')
        until(lambda:spin(b)['scene']=='MainMenu',20);s=page(b,'multiplayer');assert s['message'] and s['bank_nodes']==0
        processes=subprocess.run(['powershell','-NoProfile','-Command',f'Get-Process -Id {server_pid} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id'],capture_output=True,text=True).stdout.strip()
        assert not processes,processes
        mark('frontend_leave_cleans_owned_server',remote_return=True)
        # Cancellation during connection is a native UI action, then another join
        # confirms scene lifetime and MultiplayerAPI subscriptions are reusable.
        b.call('fields',values={'port':str(port())});b.call('click',control='connect');bank(b)
        b.call('click',control='back_button');s=page(b,'multiplayer');assert s['bank_nodes']==0
        mark('frontend_cancel_connection')
        for peer in peers:
            log=(peer.folder/'engine.log').read_text(encoding='utf8')
            assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log,log[-3000:]
    finally:
        for peer in reversed(peers):peer.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)


if __name__=='__main__':main()
