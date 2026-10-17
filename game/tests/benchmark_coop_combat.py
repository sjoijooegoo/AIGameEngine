"""Current-bank multiplayer indoor combat benchmark. No legacy worlds.

One rendered player, remaining clients headless, separate authoritative server.
Sampling is scheduled in the processes; no request polling or capture in windows.
"""
from __future__ import annotations
import argparse,ctypes,datetime,hashlib,html,json,math,os,statistics,subprocess,time,socket
from ctypes import wintypes
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from game.tests.verify_coop import Peer
from game.tools.coop import ROOT,HIDDEN,godot

def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
def read(path):return json.loads(path.read_text(encoding='utf8'))
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def dist(values):
    xs=sorted(float(v) for v in values if v is not None and math.isfinite(float(v)))
    if not xs:return None
    return {'n':len(xs),'mean':statistics.mean(xs),**{f'p{q}':xs[max(0,math.ceil(len(xs)*q/100)-1)] for q in [50,95,99]},'max':xs[-1]}

class Counters:
    """Read-only Windows per-process CPU and memory; CPU 100% = one logical core."""
    class Memory(ctypes.Structure):
        _fields_=[('cb',wintypes.DWORD),('faults',wintypes.DWORD)]+[(n,ctypes.c_size_t) for n in ['peak_rss','rss','peak_pool','pool','peak_nonpaged','nonpaged','pagefile','peak_pagefile','private']]
    def __init__(self,pid):
        self.kernel=ctypes.WinDLL('kernel32',use_last_error=True);self.psapi=ctypes.WinDLL('psapi',use_last_error=True)
        self.kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];self.kernel.OpenProcess.restype=wintypes.HANDLE
        self.kernel.GetProcessTimes.argtypes=[wintypes.HANDLE,*([ctypes.POINTER(wintypes.FILETIME)]*4)]
        self.kernel.CloseHandle.argtypes=[wintypes.HANDLE]
        self.psapi.GetProcessMemoryInfo.argtypes=[wintypes.HANDLE,ctypes.POINTER(self.Memory),wintypes.DWORD]
        self.handle=self.kernel.OpenProcess(0x410,False,pid)
        if not self.handle:raise ctypes.WinError(ctypes.get_last_error())
    def sample(self):
        values=[wintypes.FILETIME() for _ in range(4)];memory=self.Memory();memory.cb=ctypes.sizeof(memory)
        if not self.kernel.GetProcessTimes(self.handle,*[ctypes.byref(v) for v in values]):raise ctypes.WinError()
        if not self.psapi.GetProcessMemoryInfo(self.handle,ctypes.byref(memory),memory.cb):raise ctypes.WinError()
        seconds=sum((v.dwHighDateTime<<32)+v.dwLowDateTime for v in values[2:])/1e7
        return {'time':time.time(),'cpu_seconds':seconds,'rss_mb':memory.rss/1048576,'private_mb':memory.private/1048576}
    def close(self):self.kernel.CloseHandle(self.handle)

class PerfPeer(Peer):
    def __init__(self,folder,args,rendered=False):
        folder.mkdir();self.folder=folder;self.serial=0;self.log=(folder/'engine.log').open('w',encoding='utf8')
        exe=godot();direct=exe.with_name(exe.name.replace('_console.exe','.exe'));exe=direct if direct.is_file() else exe
        command=[str(exe),'--path',str(ROOT/'game/runtime'),'--resolution','1920x1080','--position','10,10','--script',str(ROOT/'game/tests/coop_combat_performance.gd')]
        if not rendered:command+=['--headless']
        command+=['--',f'--test-session={folder.as_posix()}','--performance-benchmark','--coop',*args]
        self.process=subprocess.Popen(command,cwd=ROOT,stdout=self.log,stderr=subprocess.STDOUT,creationflags=HIDDEN)
        save(folder/'launch.json',{'command':command,'pid':self.process.pid});self.wait_file(folder/'ready.json',120)
        self.counters=Counters(self.process.pid)
    def close(self):
        super().close();self.counters.close()

def summary(raw,os_samples):
    frames=raw['frames'];ticks=raw['ticks'];wall=raw['wall_seconds'];rendered=not raw['environment']['headless']
    ms=[f['frame_ms'] for f in frames];slow=sorted(ms,reverse=True)[:max(1,math.ceil(len(ms)*.01))]
    scopes=sorted({k for t in ticks for k in t['scopes_ms']})
    counts=sorted({k for t in ticks for k in t['counts']})
    cpu=[]
    for a,b in zip(os_samples,os_samples[1:]):
        if b['time']>a['time']:cpu.append((b['cpu_seconds']-a['cpu_seconds'])/(b['time']-a['time'])*100)
    changes=[];last=-1
    for row in raw['telemetry']:
        if row['world_tick']!=last and row['world_tick']>=0:changes.append(row['time']);last=row['world_tick']
    return {'environment':raw['environment'],'wall_seconds':wall,'tick_hz':len(ticks)/wall,'script_tick_ms':dist(t['elapsed_ms'] for t in ticks),
      'scopes_ms':{k:dist(t['scopes_ms'].get(k,0) for t in ticks) for k in scopes},'counts':{k:dist(t['counts'].get(k,0) for t in ticks) for k in counts},
      'frame_ms':dist(ms) if rendered else None,'fps_average':1000/statistics.mean(ms) if rendered else None,
      'fps_1pct_low':1000/statistics.mean(slow) if rendered else None,'hitches_over_50ms':sum(m>50 for m in ms) if rendered else None,
      'over_16_67ms_pct':100*sum(m>1000/60 for m in ms)/len(ms) if rendered else None,
      'monitors':{k:dist(f[k] for f in frames) for k in ['physics_ms','process_ms','draw_calls','primitives','video_memory_mb','static_memory_mb']},
      'gpu_ms':{k:dist(f['viewport_gpu_ms'].get(k) for f in frames if f['viewport_gpu_ms'].get(k,0)>0) for k in sorted({k for f in frames for k in f['viewport_gpu_ms']})} if rendered else {},
      'render_cpu_ms':{k:dist(f['viewport_render_cpu_ms'].get(k) for f in frames if f['viewport_render_cpu_ms'].get(k,0)>0) for k in sorted({k for f in frames for k in f['viewport_render_cpu_ms']})} if rendered else {},
      'os_cpu_one_core_pct':dist(cpu),'rss_mb':dist(s['rss_mb'] for s in os_samples),'private_mb':dist(s['private_mb'] for s in os_samples),
      'network_kib_s':{k:v/wall/1024 for k,v in raw['network'].items() if k.endswith('bytes')},'network':raw['network'],
      'world_delivery_hz':(len(changes)-1)/(changes[-1]-changes[0]) if len(changes)>1 else None,
      'world_gap_ms':dist((b-a)*1000 for a,b in zip(changes,changes[1:])),
      'world_age_ms':dist(r['world_age_ms'] for r in raw['telemetry'] if r['world_age_ms']>=0),
      'prediction_error_m':dist(r['prediction_error'] for r in raw['telemetry']),
      'route_input_ms':dist(t.get('route_input_ms',0) for t in ticks),'dropped_samples':raw['dropped_samples'],
      'start':raw['start'],'finish':raw['finish'],'phase_states':raw['phase_states']}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--suite',type=Path,default=ROOT/'game/tests/coop_combat_performance_suite.json')
    parser.add_argument('--cases',nargs='+');parser.add_argument('--repeat',type=int,default=2);parser.add_argument('--diagnostics',action='store_true')
    parser.add_argument('--seconds',type=float);args=parser.parse_args();assert 1<=args.repeat<=3
    suite=read(args.suite);assert suite['project']=='bank'
    cases=[{**c,'resolution':suite['resolution']} for c in suite['cases']]
    if args.diagnostics:
        for diagnostic in suite['diagnostics']:
            base=next(c for c in cases if c['id']==diagnostic['base']);cases.append({**base,**diagnostic,'diagnostic_only':True})
    if args.cases:
        assert set(args.cases)<=set(c['id'] for c in cases)
        cases=[c for c in cases if c['id'] in args.cases]
    seconds=args.seconds or suite['measure_seconds'];assert 5<=seconds<=60
    folder=ROOT/'logs/performance'/('bank-coop-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True)
    print(folder,flush=True)
    paths=[p for base in ['game/runtime/coop','game/runtime/scripts','game/runtime/frontend','game/runtime/data','engine/godot/performance'] for p in (ROOT/base).rglob('*') if p.suffix in ['.gd','.json']]
    paths += [ROOT/'game/runtime/project.godot',Path(__file__),ROOT/'game/tests/coop_combat_performance.gd',args.suite]
    sources={p.relative_to(ROOT).as_posix():digest(p) for p in paths};save(folder/'sources.json',sources)
    save(folder/'plan.json',{'suite':suite,'selected':cases,'repeat':args.repeat,'warmup_seconds':suite['warmup_seconds'],'measure_seconds':seconds,
      'topology':'Dedicated headless server + one rendered client + remaining headless clients on one Windows host. No injected network impairment.',
      'semantics':'Wall-time samples, no controller commands/capture/disk writes during measured interval. CPU scopes inclusive. Headless frame rate is not rendered FPS.'})
    report={'cases':[],'failures':[],'source_changes':{},'sources':'sources.json'}
    peers=[];pool=ThreadPoolExecutor(max_workers=5)
    def steps(n=6):
        for f in [pool.submit(p.call,'step',frames=n) for p in peers]:f.result()
    try:
      for count in sorted({c['players'] for c in cases}):
        group=folder/f'{count}p';group.mkdir()
        with socket.socket(type=socket.SOCK_DGRAM) as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        server=PerfPeer(group/'server',['--server',f'--port={port}',f'--max-players={count}']);peers.append(server)
        for slot in range(count):
            peer=PerfPeer(group/f'client-{slot+1}',['--connect=127.0.0.1',f'--port={port}',f'--name=Perf{slot+1}'],slot==0);peers.append(peer)
        for attempt in range(100):
            steps(6);states=[p.call('perf_status') for p in peers]
            if all(s['players']==count and s['started'] for s in states):break
        else:raise RuntimeError('Players did not synchronize')
        preflight={}
        for base in [c for c in cases if c['players']==count and not c.get('diagnostic_only')]:
            preflight[base['id']]=server.call('perf_fixture',config=base)
        save(group/'placement-preflight.json',preflight)
        for repeat in range(1,args.repeat+1):
          for base in [c for c in cases if c['players']==count]:
            case={**base,'repeat':repeat};case_dir=folder/(case['id']+f'-r{repeat}');case_dir.mkdir()
            for p in peers:p.call('perf_config',config=case)
            placement=server.call('perf_fixture',config=case);save(case_dir/'placement.json',placement)
            for attempt in range(30):
                steps(6);states=[p.call('perf_status') for p in peers]
                if all(s['active']==case['population'] and s['round']==states[0]['round'] for s in states):break
            else:raise RuntimeError('Fixture epoch/population not synchronized')
            start=time.time()+2
            for p in peers:
                path=p.folder/'result.json'
                if path.exists():path.unlink()
                p.call('perf_run',start=start,warmup=suite['warmup_seconds'],seconds=seconds)
            os_rows={p.folder.name:[] for p in peers}
            sample_at=start+suite['warmup_seconds'];finish=sample_at+seconds
            while time.time()<finish:
                now=time.time()
                if now>=sample_at:
                    for p in peers:os_rows[p.folder.name].append(p.counters.sample())
                time.sleep(min(.5,max(.01,finish-time.time())))
            results={}
            for p in peers:
                p.wait_file(p.folder/'result.json',20);raw=read(p.folder/'result.json')
                save(case_dir/(p.folder.name+'-raw.json'),raw);results[p.folder.name]=summary(raw,os_rows[p.folder.name])
            save(case_dir/'os-samples.json',os_rows)
            capture=peers[1].call('capture')['capture'];target=case_dir/'combat.png';target.write_bytes(Path(capture).read_bytes())
            issues=[];authority=results['server']
            if placement['world_overlaps']!=0:issues.append('Initial world overlap')
            for name,r in results.items():
                if not r['script_tick_ms'] or r['dropped_samples']:issues.append(name+': missing/truncated samples')
                if r['finish']['players']!=count or r['finish']['active']!=case['population']:issues.append(name+': population/connection changed')
                if any(s['dead'] for s in r['finish']['combat'].values()):issues.append(name+': diagnostic player died')
            if any(s['shots']<3 for s in authority['finish']['combat'].values()):issues.append('A peer did not fire enough normal shots')
            if authority['finish']['kills']<2:issues.append('No meaningful shared kills')
            if seconds>=16 and not sum(authority['finish'].get('loaded_rounds',{}).values()):issues.append('No actual reload completion')
            if not any(s['hp']<10000 for s in authority['finish']['combat'].values()):issues.append('No enemy combat contact')
            row={'config':case,'results':results,'issues':issues,'evidence':case_dir.name};report['cases'].append(row)
            save(folder/'report.json',report)
            measured=results['client-1'];print(case['id'],repeat,'FPS',round(measured['fps_average'],1),'p95',round(measured['frame_ms']['p95'],2),'server p95',round(authority['script_tick_ms']['p95'],2),'kills',authority['finish']['kills'],'issues',issues,flush=True)
        for p in reversed(peers):p.close()
        peers.clear()
    except Exception as exc:
        report['failures'].append(repr(exc));raise
    finally:
        for p in reversed(peers):p.close()
        pool.shutdown()
        report['source_changes']={k:digest(ROOT/k) for k,v in sources.items() if digest(ROOT/k)!=v}
        report['engine_errors']={str(p.relative_to(folder)):[line for line in p.read_text(encoding='utf8').splitlines() if 'SCRIPT ERROR' in line or line.startswith('ERROR:')] for p in folder.rglob('engine.log')}
        report['passed']=not report['failures'] and not report['source_changes'] and all(not c['issues'] for c in report['cases']) and not any(report['engine_errors'].values())
        save(folder/'report.json',report)
    if not report['passed']:raise SystemExit(1)

if __name__=='__main__':main()
