"""Real multi-process ENet checks in the current bank co-op scene, never sandbox."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import math
from pathlib import Path
import shutil
import subprocess
import time
import uuid
from game.tools.coop import ROOT, HIDDEN, godot, stage, import_project


class Peer:
    def __init__(self, project: Path, folder: Path, args: list[str], rendered=False):
        folder.mkdir(); self.folder=folder; self.serial=0
        self.log=(folder/'engine.log').open('w',encoding='utf8')
        cmd=[str(godot()),'--path',str(project),'--max-fps','120','--resolution','960x540',
             '--script','res://tests/coop_peer_driver.gd']
        if not rendered: cmd+=['--headless']
        cmd+=['--',f'--test-session={folder.as_posix()}',*args]
        self.process=subprocess.Popen(cmd,stdout=self.log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=HIDDEN)
        (folder/'launch.json').write_text(json.dumps({'command':cmd,'pid':self.process.pid},indent=2),encoding='utf8')
        self.wait_file(folder/'ready.json',30)

    def wait_file(self,path,timeout=15):
        end=time.monotonic()+timeout
        while not path.exists():
            if self.process.poll() is not None: raise RuntimeError(f'Peer exited: {self.folder}\n{(self.folder/"engine.log").read_text(encoding="utf8")[-3000:]}')
            if time.monotonic()>end: raise TimeoutError(str(path))
            time.sleep(.004)

    def call(self,command,*,_timeout=15,**args):
        self.serial+=1
        response=self.folder/'response.json'
        if response.exists():response.unlink()
        request={'id':self.serial,'command':command,**args}
        path=self.folder/'request.tmp';path.write_text(json.dumps(request),encoding='utf8');path.replace(self.folder/'request.json')
        self.wait_file(response,_timeout)
        result=None
        for _ in range(100):
            try:result=json.loads(response.read_text(encoding='utf8'));break
            except (PermissionError,json.JSONDecodeError):time.sleep(.005)
        assert result is not None,'Response stayed unreadable'
        assert result['id']==self.serial
        with (self.folder/'trace.jsonl').open('a',encoding='utf8') as out:out.write(json.dumps({'request':request,'response':result},ensure_ascii=False)+'\n')
        assert 'error' not in result['result'],result
        return result['result']

    def state(self):return self.call('state')['state']

    def close(self):
        if self.process.poll() is None:
            try:self.call('quit');self.process.wait(timeout=5)
            except Exception:self.process.terminate();self.process.wait(timeout=5)
        self.log.close()


def until(predicate,timeout=12):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        value=predicate()
        if value:return value
        time.sleep(.02)
    raise AssertionError('Timed out waiting for network state')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--rendered',action='store_true')
    parser.add_argument('--reference',action='store_true')
    args=parser.parse_args()
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
    evidence=ROOT/'logs/sessions'/('bank-coop-'+stamp);evidence.mkdir(parents=True)
    project=stage(reference=args.reference);(project/'tests').mkdir()
    shutil.copy2(ROOT/'game/tests/coop_peer_driver.gd',project/'tests')
    import_project(project)
    peers=[];checks=[];captures=[];port=24671
    pool=ThreadPoolExecutor(max_workers=5)
    def create(label,extra=None,server=False):
        flags=['--server',f'--port={port}'] if server else [f'--connect=127.0.0.1',f'--port={port}',f'--name={label}']
        p=Peer(project,evidence/label,flags+(extra or []),args.rendered and not server)
        peers.append(p);return p
    def mark(name,**details):
        checks.append({'name':name,'status':'pass',**details});print(name,flush=True)
    def frames(server,clients,count):
        assert count%3==0
        for _ in range(count//3):
            futures=[pool.submit(c.call,'step',frames=3) for c in clients]
            for future in futures:future.result()
            server.call('step',frames=3)
    def player(state,id):return next(row for row in state['players'] if row['id']==id)
    try:
        server=create('server',server=True)
        a=create('alpha');b=create('bravo')
        until(lambda:len(server.state()['players'])==2 and len(a.state()['players'])==2 and len(b.state()['players'])==2)
        frames(server,[a,b],30)
        aid=a.state()['local_id'];bid=b.state()['local_id']
        assert 1 not in [p['id'] for p in server.state()['players']]
        mark('coop_two_clients',dedicated_server_is_not_player=True)
        before=player(server.state(),aid)['position']
        a.call('input',keys=['W']);frames(server,[a,b],60);a.call('input',keys=[]);frames(server,[a,b],12)
        after=player(server.state(),aid)['position'];distance=math.dist(before,after)
        if args.rendered:captures.append(b.call('capture')['capture'])
        assert 2.5<distance<3.3,(before,after,distance)
        assert player(server.state(),aid)['motion']=='idle'
        assert math.dist(player(a.state(),aid)['target'],after)<.02
        assert math.dist(player(b.state(),aid)['target'],after)<.02
        mark('coop_authoritative_walk_and_stop',distance=distance,input='Input.parse_input_event -> normal _input -> UDP RPC')
        if args.rendered:captures.append(b.call('capture')['capture'])
        # Walk/run sideways in the hall, then approach the outer wall.
        a.call('input',keys=['D','Shift']);frames(server,[a,b],24)
        moving=player(server.state(),aid);assert moving['motion']=='run',moving
        if args.rendered:
            for _ in range(6):
                frames(server,[a,b],3);captures.append(b.call('capture')['capture'])
        a.call('input',keys=[]);frames(server,[a,b],12)
        mark('coop_run_animation',remote_avatar=player(b.state(),aid)['avatar'])
        avatar=player(b.state(),aid)['avatar']
        assert avatar['bones']>=17 and all(clip in avatar['clips'] for clip in ['idle','walk','run'])
        if args.reference:assert avatar['source']=='local_l4d2_reference' and avatar['bones']>=50
        a.call('input',keys=['W','Shift']);frames(server,[a,b],180)
        wall=player(server.state(),aid)['position'];assert wall[2]<24.1 and wall[1]>-.05,wall
        frames(server,[a,b],30)
        assert math.dist(player(server.state(),aid)['position'],wall)<.02,'Walking into a wall must remain blocked'
        a.call('input',keys=[]);frames(server,[a,b],12)
        mark('coop_wall_collision',position=wall)
        rejected_before=server.state()['rejected_inputs']
        a.call('invalid_input');frames(server,[a,b],6)
        assert server.state()['rejected_inputs']>rejected_before
        mark('coop_invalid_input_rejected')
        a.call('input',keys=['S']);frames(server,[a,b],6)
        # Stop sending this client's input, while server ticks continue.
        frames(server,[b],45)
        stopped=player(server.state(),aid)
        assert stopped['motion']=='idle'
        a.call('input',keys=[]);frames(server,[a,b],6)
        mark('coop_stale_input_stops')
        c=create('charlie');d=create('delta')
        until(lambda:len(server.state()['players'])==4 and all(len(p.state()['players'])==4 for p in [a,b,c,d]))
        frames(server,[a,b,c,d],30)
        assert math.dist(player(c.state(),aid)['target'],player(server.state(),aid)['position'])<.02
        slots=[p['slot'] for p in server.state()['players']];assert sorted(slots)==[0,1,2,3]
        mark('coop_four_clients_and_late_join',slots=slots)
        if args.rendered:captures.append(d.call('capture')['capture'])
        full=create('echo')
        until(lambda:'满' in full.state()['status']);assert len(server.state()['players'])==4
        mark('coop_capacity_rejected');full.close()
        # Leave through the actual menu and button, not a gameplay callback.
        old_id=c.state()['local_id']
        c.call('menu');c.call('click',control='leave_button')
        until(lambda:len(server.state()['players'])==3 and len(b.state()['players'])==3)
        assert not c.state()['players']
        mark('coop_leave_button_and_cleanup')
        c.call('click',control='join_button')
        until(lambda:len(server.state()['players'])==4 and len(c.state()['players'])==4)
        assert c.state()['local_id']!=old_id
        mark('coop_rejoin')
        d.process.kill();d.process.wait()
        until(lambda:len(server.state()['players'])==3,timeout=45)
        mark('coop_abrupt_disconnect')
        mismatch=create('mismatch',['--bad-map'])
        until(lambda:'一致' in mismatch.state()['status']);assert not mismatch.state()['players']
        mark('coop_map_version_rejected');mismatch.close()
        server.close()
        until(lambda:not a.state()['players'] and not b.state()['players'],timeout=20)
        mark('coop_server_disconnect_cleanup')
        for p in peers:
            log=(p.folder/'engine.log').read_text(encoding='utf8',errors='replace')
            assert 'SCRIPT ERROR:' not in log and '\nERROR:' not in log, str(p.folder/'engine.log')
        report={'passed':True,'project':'bank','checks':checks,'captures':captures,'rendered':args.rendered,'reference':args.reference,'project_path':str(project),
                'scope':'real ENet on separate local Godot processes; frozen between bounded 60 Hz steps; no legacy worlds; no WAN latency or Ubuntu execution claim'}
    except BaseException as error:
        report={'passed':False,'error':repr(error),'checks':checks,'captures':captures,'project_path':str(project)}
        raise
    finally:
        for peer in peers:peer.close()
        pool.shutdown()
        (evidence/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
        (ROOT/'logs/coop-test-latest.json').write_text(json.dumps({'report':str(evidence/'report.json')}),encoding='utf8')
        print(evidence/'report.json',flush=True)


if __name__=='__main__':main()
