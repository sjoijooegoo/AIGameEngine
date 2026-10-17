"""Compare reference preview with real solo and localhost multiplayer menu entry."""
import argparse,datetime,json,math,subprocess
from pathlib import Path
from PIL import Image,ImageChops,ImageStat
from game.tests.verify_frontend import FrontendPeer,ROOT,HIDDEN,godot
from game.tests.verify_coop import until
from engine.tools.sequence import build

class LightingPeer(FrontendPeer):
    def __init__(self,folder,reference=''):
        folder.mkdir();self.folder=folder;self.serial=0
        self.log=(folder/'engine.log').open('w',encoding='utf8')
        executable=godot();direct=executable.with_name(executable.name.replace('_console.exe','.exe'))
        if direct.is_file():executable=direct
        cmd=[str(executable),'--path',str(ROOT/'game/runtime'),'--max-fps','60','--resolution','1280x720',
             '--script',str(ROOT/'game/tests/lighting_entry_driver.gd'),'--',f'--test-session={folder.as_posix()}','--performance-benchmark']
        if reference:cmd.append('--lighting-reference='+reference)
        self.process=subprocess.Popen(cmd,stdout=self.log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=HIDDEN)
        (folder/'launch.json').write_text(json.dumps({'command':cmd,'pid':self.process.pid},indent=2),encoding='utf8')
        self.wait_file(folder/'ready.json',90)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-lighting-entry-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    checks=[];captures={};states={};peers=[];sequences=[]
    def mark(name,**values):checks.append(dict(name=name,status='pass',**values));print(name,flush=True)
    def bank(peer):return until(lambda:(lambda s:s if s.get('scene')=='BankExploration' and not s['loading'] else False)(peer.state()),90)
    def step(peer):return peer.call('step',frames=3)['state']
    def capture(peer,name):return peer.call('capture',name=name)['capture']
    try:
        for mode in ['base','preview','solo','multiplayer']:
            peer=LightingPeer(folder/mode,mode if mode in ['base','preview'] else '');peers.append(peer)
            if mode in ['solo','multiplayer']:
                assert peer.state()['bank_nodes']==0
                if mode=='solo':peer.call('click',control='single');bank(peer)
                else:
                    peer.call('click',control='multiplayer')
                    until(lambda:peer.state()['discovery']['localhost:24567']['online'])
                    peer.call('click',control='connect');bank(peer)
                    until(lambda:step(peer).get('input_enabled'),90)
                before=step(peer)['position'];peer.call('act',keys=['W'],frames=30)
                after=step(peer);assert math.dist(before,after['position'])>.5,(before,after['position'])
                mark('lighting_'+mode+'_normal_entry_and_movement')
            state=peer.state();states[mode]=state
            assert state['lighting']['loaded'] and state['lighting']['meshes']==481
            if mode=='base':assert state['diffuse_nodes']==0
            else:
                assert state['room_lighting']['emitters']==54 and state['diffuse_nodes']==54,state['room_lighting']
                assert state['room_lighting']['lobby']['source']=='G_source_10'
                assert all(state['profile_copies'])
                mark('lighting_'+mode+'_54_emitters_and_bake')
            captures[mode]={}
            for name in ['cash','lobby','meeting','floor3','floor4']:
                peer.call('lighting_view',name=name);captures[mode][name]=capture(peer,name)
            if mode=='solo':
                peer.call('lighting_play_fixture');peer.call('step',frames=18)
                frames=[]
                for i in range(8):
                    state=peer.call('act',keys=['D' if i<4 else 'A'],frames=6)['state']
                    assert state['profile_copies'] and all(state['profile_copies']),state['profile_copies']
                    frames.append({'path':capture(peer,f'walk-{i}'),'simulation_time':i*.1,'state':{'projector_copies':state['profile_copies'],'position':state['position']}})
                path=peer.folder/'light_walk.sequence.json';path.write_text(json.dumps({'name':'light_walk','fps':10,'interval':6,'frames':frames},indent=2),encoding='utf8')
                sequences.append(build(path,.25));mark('lighting_normal_walk_preserves_weapon_projector')
            text=(peer.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-2000:]
            peer.close();peers.remove(peer)
        # Inspect the same world region, excluding mode-specific HUD and hands.
        metrics={}
        for name in captures['preview']:
            images={mode:Image.open(paths[name]).convert('RGB').crop((220,160,1150,560)) for mode,paths in captures.items()}
            delta=lambda mode:sum(ImageStat.Stat(ImageChops.difference(images['preview'],images[mode])).mean)/3
            metrics[name]={mode:delta(mode) for mode in ['base','solo','multiplayer']}
        assert metrics['cash']['base']>2 and metrics['lobby']['base']>2,metrics
        for name,values in metrics.items():
            assert values['solo']<1.5 and values['multiplayer']<1.5,(name,values)
        mark('lighting_five_views_match_selected_preview',metrics=metrics)
    finally:
        for peer in reversed(peers):peer.close()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures,'states':states,'sequences':sequences,'scope':'Fixed inspection cameras for world lighting; actual entry/movement via native inputs. Existing v46 indirect bake retained.'},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
