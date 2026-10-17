"""Real bank native-input weapon switching, aiming, fire/reload and captured animation."""
import argparse,datetime,json,socket
from game.tests.verify_bank_coop import ROOT,BankPeer
from game.tests.verify_coop import until
from engine.tools.sequence import build

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-armed-teammate-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    with socket.socket(type=socket.SOCK_DGRAM) as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    peers=[];checks=[];sequences=[];captures=[]
    try:
        server=BankPeer(folder/'server',['--server',f'--port={port}']);peers.append(server)
        a=BankPeer(folder/'actor',['--connect=127.0.0.1',f'--port={port}','--name=Alpha']);peers.append(a)
        b=BankPeer(folder/'observer',['--connect=127.0.0.1',f'--port={port}','--name=Bravo'],True);peers.append(b)
        until(lambda:len(a.state()['players'])==2 and len(b.state()['players'])==2)
        def step(n):
            for _ in range(n//3):
                for p in [a,b]:p.call('step',frames=3)
                server.call('step',frames=3)
        step(24);server.call('fixture',name='firearms_range');step(18);aid=a.state()['local_id']
        def state():return b.state()
        def equip():return state()['equipment'][str(aid)]
        def view():
            row=next(p for p in state()['players'] if p['id']==aid);x,y,z=row['position']
            b.call('view',position=[x+1.25,y+1.65,z-1.6],target=[x,y+1.30,z-.15])
            return row
        def shot():a.call('input',buttons=['left']);step(3);a.call('input');step(3)
        def sequence(name,keys=None,n=10,interval=6):
            frames=[]
            if keys:a.call('input',keys=keys)
            for _ in range(n):
                step(interval);row=view();s=state();equipment=s['equipment'][str(aid)]
                assert equipment['source']=='local_l4d2_world_models' and equipment['bone_error']<.0001,equipment
                capture=b.call('capture')['capture'];frames.append({'path':capture,'simulation_time':s['bank_tick']/60,'state':{'player':row,'equipment':equipment}})
            if keys:a.call('input')
            path=folder/'observer'/f'{name}.sequence.json';path.write_text(json.dumps({'name':name,'fps':60/interval,'interval':interval,'frames':frames},indent=2),encoding='utf8')
            sequences.append(build(path,.25));return frames
        view();captures.append(b.call('capture')['capture']);assert equip()['merged_bones']==4
        sequence('pistol_walk',['W'])
        server.call('fixture',name='firearms_range');step(18)
        sequence('pistol_run',['W','Shift'],n=6)
        server.call('fixture',name='firearms_range');step(18)
        base=equip()['muzzle'][1];a.call('input',mouse=[0,-200]);step(18);up=equip()['muzzle'][1]
        view();captures.append(b.call('capture')['capture']);assert up>base+.15,(base,up)
        a.call('input',mouse=[0,400]);step(18);down=equip()['muzzle'][1];assert down<base-.15,(base,down)
        view();captures.append(b.call('capture')['capture']);a.call('input',mouse=[0,-200]);step(18)
        checks.append({'name':'teammate_native_pistol_grip_aim_walk_run','status':'pass','muzzle_height':[base,up,down]})
        shot();f=sequence('pistol_fire',n=6,interval=3)
        a.call('input',keys=['R']);step(3);a.call('input');f=sequence('pistol_reload',n=16,interval=6)
        assert any(x['state']['player']['avatar']['upper_action']=='reload_pistol' for x in f)
        checks.append({'name':'teammate_pistol_reload_and_fire','status':'pass'})
        a.call('input',keys=['2']);step(3);a.call('input');step(60)
        assert equip()['weapon']=='shotgun' and equip()['merged_bones']==2
        view();captures.append(b.call('capture')['capture']);sequence('shotgun_walk',['W'],n=8)
        shot();sequence('shotgun_fire',n=8,interval=3);step(60)
        a.call('input',keys=['R']);step(3);a.call('input');f=sequence('shotgun_reload',n=24,interval=6)
        assert any(x['state']['player']['avatar']['upper_action']=='reload_shotgun_loop' for x in f)
        checks.append({'name':'teammate_native_shotgun_grip_walk_fire_reload','status':'pass'})
        a.call('input',keys=['3']);step(3);a.call('input');step(18);assert not equip()['visible']
        checks.append({'name':'teammate_weapon_switch_hides_stowed_gun','status':'pass'})
        for p in peers:
            text=(p.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-2000:]
    finally:
        for p in reversed(peers):p.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'sequences':sequences,'captures':captures},indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
