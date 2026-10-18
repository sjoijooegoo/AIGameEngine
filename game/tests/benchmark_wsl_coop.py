"""Bank only: 2-vCPU / 4-GiB WSL server and real Windows ENet input clients.

Requires the WSL VM to have already been explicitly limited. Never silently
changes global WSL configuration. All gameplay comes from the existing bounded
combat route, with diagnostic HP only at fixture setup.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
from pathlib import Path
import shlex
import subprocess
import time

from game.tests.benchmark_coop_combat import PerfPeer, Counters, summary, save, read, digest, dist
from game.tests.verify_coop import Peer
from game.tools.coop import ROOT, HIDDEN, godot
from game.tools.local_bank_server import wsl, mounted


def read_result(path):
    deadline=time.monotonic()+3
    while True:
        try:return read(path)
        except (PermissionError,json.JSONDecodeError):
            if time.monotonic()>=deadline:raise
            time.sleep(.02)


class DiagnosticPeer(PerfPeer):
    def __init__(self,folder,args,route,lean):
        folder.mkdir();self.folder=folder;self.serial=0
        self.log=(folder/'engine.log').open('w',encoding='utf8')
        exe=godot();direct=exe.with_name(exe.name.replace('_console.exe','.exe'));exe=direct if direct.is_file() else exe
        driver='wsl_coop_hold.gd' if route=='hold' else 'wsl_coop_performance.gd'
        command=[str(exe),'--headless','--path',str(ROOT/'game/runtime'),'--script',str(ROOT/'game/tests'/driver),
                 '--','--test-session='+folder.as_posix(),'--performance-benchmark','--coop',*args]
        if lean:command.append('--lean-load-client')
        self.process=subprocess.Popen(command,cwd=ROOT,stdout=self.log,stderr=subprocess.STDOUT,creationflags=HIDDEN)
        save(folder/'launch.json',{'command':command,'pid':self.process.pid});self.wait_file(folder/'ready.json',120)
        self.counters=Counters(self.process.pid)


class LinuxPeer(Peer):
    def __init__(self, folder, executable, port, count, route='combat'):
        folder.mkdir(); self.folder=folder; self.serial=0
        self.log=(folder/'engine.log').open('w', encoding='utf8')
        args=[executable, '--headless', '--path', mounted(ROOT/'game/runtime'),
              '--script', mounted(ROOT/'game/tests'/('wsl_coop_hold.gd' if route=='hold' else 'wsl_coop_performance.gd')), '--',
              '--test-session='+mounted(folder), '--performance-benchmark', '--coop',
              '--server', f'--port={port}', f'--max-players={count}']
        script=folder/'launch.sh'
        script.write_text('#!/bin/sh\necho $$ > '+shlex.quote(mounted(folder/'pid'))+'\nexec '+shlex.join(args)+'\n', encoding='utf8', newline='\n')
        self.process=subprocess.Popen(['wsl','-d','Ubuntu','--','sh',mounted(script)],
                                      stdout=self.log, stderr=subprocess.STDOUT, creationflags=HIDDEN)
        try:
            self.wait_file(folder/'ready.json',180)
        except Exception:
            self.close(); raise
        self.pid=int((folder/'pid').read_text())
        save(folder/'launch.json', {'command':args, 'linux_pid':self.pid})

    def close(self):
        if self.process.poll() is None:
            try:
                self.call('quit'); self.process.wait(timeout=8)
            except Exception:
                if (self.folder/'pid').exists():
                    wsl('Ubuntu','kill','-TERM',(self.folder/'pid').read_text().strip(),check=False)
                try:self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:self.process.terminate()
        self.log.close()


def capacity_metrics(raw, rows):
    timestamps=[t['started_usec']/1000 for t in raw['ticks']]
    seconds={}
    if timestamps:
        for t in timestamps:seconds[int((t-timestamps[0])/1000)]=seconds.get(int((t-timestamps[0])/1000),0)+1
    # Exclude the final partial second; wall-clock spacing retains stalls.
    full=[seconds.get(k,0) for k in range(int((timestamps[-1]-timestamps[0])/1000))] if timestamps else []
    thread_cpu={}; system_busy=[]; steal=[]
    for a,b in zip(rows,rows[1:]):
        dt=b['monotonic']-a['monotonic']
        for tid, info in b['threads'].items():
            if tid in a['threads']:
                thread_cpu.setdefault(tid,{'name':info['name'],'samples':[]})['samples'].append(100*(info['cpu_seconds']-a['threads'][tid]['cpu_seconds'])/dt)
        values=[y-x for x,y in zip(a['system_cpu'],b['system_cpu'])]
        total=sum(values[:8])
        if total:
            system_busy.append(100*(total-values[3]-values[4])/total);steal.append(100*values[7]/total)
    return {'tick_interval_ms':dist(b-a for a,b in zip(timestamps,timestamps[1:])),
            'full_second_tick_counts':full,'min_full_second_ticks':min(full) if full else None,
            'threads':{k:{'name':v['name'],'cpu_one_core_pct':dist(v['samples'])} for k,v in thread_cpu.items()},
            'system_busy_pct':dist(system_busy),'steal_pct':dist(steal),
            'mem_available_mb':dist(r['mem_available_mb'] for r in rows),
            'swap_mb':dist(r['swap_mb'] for r in rows),
            'alive':dist(r['alive'] for r in raw['phase_states']),
            'awake_corpses':dist(r['awake_corpses'] for r in raw['phase_states'])}


def budget_result(result, capacity):
    return {'average_tick_59_5hz':result['tick_hz']>=59.5,
            'script_p95_16_67ms':result['script_tick_ms']['p95']<=1000/60,
            # Godot main.cpp publishes a maximum once per second. Keep this
            # conservative headroom criterion, but never call it per-tick P95.
            'physics_monitor_peak_p95_16_67ms':result['monitors']['physics_ms']['p95']<=1000/60,
            'no_second_below_57ticks':capacity['min_full_second_ticks'] is not None and capacity['min_full_second_ticks']>=57}


def main():
    # A foreground pipe keeps WSL alive; systemd services alone do not.
    keeper=subprocess.Popen(['wsl','-d','Ubuntu','--','sh','-c','cat >/dev/null'],stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=HIDDEN)
    import atexit
    def close_keeper():
        keeper.stdin.close()
        try:keeper.wait(timeout=5)
        except subprocess.TimeoutExpired:keeper.terminate()
    atexit.register(close_keeper)
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--linux-executable',default='/home/song/.local/share/aigameengine-bank/benchmark/godot-debug')
    parser.add_argument('--players',type=int,nargs='+',default=[2,4],choices=[2,4])
    parser.add_argument('--populations',type=int,nargs='+',default=[16,24,32,48,64,84])
    parser.add_argument('--repeat',type=int,default=2)
    parser.add_argument('--repeat-start',type=int,default=1)
    parser.add_argument('--route',choices=['combat','hold'],default='combat')
    parser.add_argument('--lean-clients',action='store_true',help='Diagnostic load generators skip invisible replica bone presentation; server remains unchanged')
    parser.add_argument('--seconds',type=float,default=30)
    parser.add_argument('--areas',nargs='+',default=['hall'],choices=['hall','cash','activity','conference','corridor'])
    args=parser.parse_args(); assert 1<=args.repeat<=3 and 5<=args.seconds<=60
    assert all(1<=n<=84 for n in args.populations)
    folder=ROOT/'logs/performance'/('bank-wsl-2c4g-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True)
    print(folder,flush=True)
    limits=json.loads(wsl('Ubuntu','python3','-c',"import json,os;from pathlib import Path;m=dict(l.split(':',1) for l in Path('/proc/meminfo').read_text().splitlines());print(json.dumps({'cpus':os.cpu_count(),'mem_kib':int(m['MemTotal'].split()[0]),'swap_kib':int(m['SwapTotal'].split()[0])}))").stdout)
    assert limits['cpus']==2 and 3.5*1024**2<limits['mem_kib']<=4*1024**2 and limits['swap_kib']==0,limits
    assert wsl('Ubuntu','systemctl','is-active','bank-coop-local.service',check=False).stdout.strip()!='active','Stop the normal server to avoid a second instance sharing the VM'
    environment=wsl('Ubuntu','sh','-c','uname -a; lscpu; free -m; ps -eo pid,comm,%cpu,%mem --sort=-%cpu; cat /proc/pressure/cpu; cat /proc/pressure/memory').stdout
    (folder/'environment.txt').write_text(environment,encoding='utf8');save(folder/'limits.json',limits)
    host=wsl('Ubuntu','hostname','-I').stdout.split()[0]
    suite=read(ROOT/'game/tests/coop_combat_performance_suite.json')
    bases={c['id'].split('_')[0]:c for c in suite['cases']}
    cases=[{**bases[area],'id':f'{area}_{count}p_{pop}','label':f'{area} {count}p {pop} infected','route':args.route,'lean_clients':args.lean_clients,'players':count,'population':pop,'resolution':[1920,1080]}
           for count in args.players for area in args.areas for pop in args.populations]
    paths=[p for base in ['game/runtime/coop','game/runtime/scripts','game/runtime/frontend','game/runtime/data','engine/godot/performance'] for p in (ROOT/base).rglob('*') if p.suffix in ['.gd','.json']]
    paths += [ROOT/'game/runtime/project.godot',Path(__file__),ROOT/'game/tests/wsl_coop_performance.gd',ROOT/'game/tests/wsl_proc_sampler.py',ROOT/'game/tests/coop_combat_performance.gd',ROOT/'game/tests/bank_coop_driver.gd']
    if args.route=='hold':paths.append(ROOT/'game/tests/wsl_coop_hold.gd')
    if args.lean_clients:paths.append(ROOT/'game/tests/wsl_load_presentation.gd')
    sources={p.relative_to(ROOT).as_posix():digest(p) for p in paths};save(folder/'sources.json',sources)
    snapshot=folder/'harness-source';snapshot.mkdir()
    for p in paths:
        if 'game/tests/' in p.as_posix(): (snapshot/p.name).write_bytes(p.read_bytes())
    save(folder/'plan.json',{'cases':cases,'repeat':args.repeat,'seconds':args.seconds,'warmup':5,'limits':limits,
         'topology':'WSL Ubuntu VM limited to 2 logical CPUs, 4 GiB, swap 0; one Linux debug headless server. Windows headless clients outside VM. Real UDP; no network impairment.',
         'semantics':'Initial population becomes live enemies plus corpses. No respawn/HP refill during measurement. Diagnostic player HP 10000. Server frame rate is not client rendered FPS. CPU scopes inclusive. Source project on /mnt/d; sampling buffered in RAM.',
         'budget':'Per run: >=59.5 average Hz, script P95 and the repeated once-per-second physics maximum monitor P95 <=16.667ms, no complete one-second bucket below 57 ticks. A workload passes only if every repeat passes and route evidence is valid. Physics monitor is conservative peak headroom, NOT a per-tick P95.'})
    report={'cases':[],'failures':[],'limits':limits,'sources':'sources.json'}
    peers=[]; pool=ThreadPoolExecutor(max_workers=5)
    def steps(n=6):
        futures=[pool.submit(p.call,'step',frames=n) for p in peers]
        for f in futures:f.result()
    try:
        for count in args.players:
            group=folder/f'{count}p';group.mkdir();port=24880+count
            server=LinuxPeer(group/'server',args.linux_executable,port,count,args.route);peers.append(server)
            for slot in range(count):
                client_args=['--connect='+host,f'--port={port}',f'--name=WSLPerf{slot+1}']
                peers.append(DiagnosticPeer(group/f'client-{slot+1}',client_args,args.route,args.lean_clients) if args.route=='hold' or args.lean_clients else PerfPeer(group/f'client-{slot+1}',client_args))
            for attempt in range(100):
                steps();states=[p.call('perf_status') for p in peers]
                if all(s['players']==count and s['started'] for s in states):break
            else:raise RuntimeError('Players did not synchronize')
            for repeat in range(args.repeat_start,args.repeat_start+args.repeat):
                selected=[c for c in cases if c['players']==count]
                if repeat%2==0:selected.reverse()
                for base in selected:
                    case={**base,'repeat':repeat};case_dir=folder/(case['id']+f'-r{repeat}');case_dir.mkdir()
                    for p in peers:p.call('perf_config',config=case)
                    placement=server.call('perf_fixture',config=case);save(case_dir/'placement.json',placement)
                    for attempt in range(40):
                        steps();states=[p.call('perf_status') for p in peers]
                        if all(s['active']==case['population'] and s['round']==states[0]['round'] for s in states):break
                    else:raise RuntimeError('Fixture not synchronized')
                    start=time.time()+3;warmup=5
                    for p in peers:
                        (p.folder/'result.json').unlink(missing_ok=True)
                        p.call('perf_run',start=start,warmup=warmup,seconds=args.seconds)
                    sampler_log=(case_dir/'sampler.log').open('w',encoding='utf8')
                    sampler=subprocess.Popen(['wsl','-d','Ubuntu','--','python3',mounted(ROOT/'game/tests/wsl_proc_sampler.py'),
                             '--pid',str(server.pid),'--start',str(start+warmup),'--seconds',str(args.seconds),
                             '--output',mounted(case_dir/'linux-os-samples.json')],stdout=sampler_log,stderr=subprocess.STDOUT,creationflags=HIDDEN)
                    os_rows={p.folder.name:[] for p in peers[1:]}
                    finish=start+warmup+args.seconds
                    while time.time()<finish:
                        if time.time()>=start+warmup:
                            for p in peers[1:]:os_rows[p.folder.name].append(p.counters.sample())
                        time.sleep(min(.5,max(.01,finish-time.time())))
                    sampler.wait(timeout=20);sampler_log.close();assert sampler.returncode==0
                    os_rows['server']=read_result(case_dir/'linux-os-samples.json');results={};raws={}
                    for p in peers:
                        p.wait_file(p.folder/'result.json',30);raw=read_result(p.folder/'result.json');raws[p.folder.name]=raw
                        save(case_dir/(p.folder.name+'-raw.json'),raw);results[p.folder.name]=summary(raw,os_rows[p.folder.name])
                    save(case_dir/'os-samples.json',os_rows)
                    authority=results['server'];issues=[]
                    if placement['world_overlaps']!=0:issues.append('Initial world overlap')
                    for name,r in results.items():
                        if not r['script_tick_ms'] or r['dropped_samples']:issues.append(name+': missing/truncated samples')
                        if r['finish']['players']!=count or r['finish']['active']!=case['population']:issues.append(name+': population/connection changed')
                        if any(s['dead'] for s in r['finish']['combat'].values()):issues.append(name+': diagnostic player died')
                    if args.route=='combat':
                        if any(s['shots']<3 for s in authority['finish']['combat'].values()):issues.append('A peer did not fire enough normal shots')
                        if authority['finish']['kills']<2:issues.append('No meaningful shared kills')
                        if args.seconds>=16 and not sum(authority['finish'].get('loaded_rounds',{}).values()):issues.append('No actual reload completion')
                    else:
                        if any(s['shots']!=0 for s in authority['finish']['combat'].values()):issues.append('Hold route fired a gun')
                        if any(s['alive']!=case['population'] for s in [authority['start'],*authority['phase_states'],authority['finish']]):issues.append('Full living population not sustained')
                    if not any(s['hp']<10000 for s in authority['finish']['combat'].values()):issues.append('No enemy combat contact')
                    capacity=capacity_metrics(raws['server'],os_rows['server']);budget=budget_result(authority,capacity)
                    row={'config':case,'results':results,'issues':issues,'capacity':capacity,'budget':budget,
                         'within_budget':not issues and all(budget.values()),'evidence':case_dir.name};report['cases'].append(row)
                    row['clients_keep_up']=all(r['tick_hz']>=59.5 and r['world_delivery_hz'] is not None and r['world_delivery_hz']>=9 for name,r in results.items() if name!='server')
                    save(folder/'report.json',report)
                    print(case['id'],repeat,'Hz',round(authority['tick_hz'],2),'p95',round(authority['script_tick_ms']['p95'],2),
                          'physicsP95',round(authority['monitors']['physics_ms']['p95'],2),'minHz',capacity['min_full_second_ticks'],
                          'CPU',round(authority['os_cpu_one_core_pct']['mean'],1),'RSS',round(authority['rss_mb']['max']),
                          'alive',authority['start']['alive'],authority['finish']['alive'],'budget',row['within_budget'],'issues',issues,flush=True)
            for p in reversed(peers):p.close()
            peers.clear()
    except Exception as exc:
        report['failures'].append(repr(exc));raise
    finally:
        for p in reversed(peers):p.close()
        pool.shutdown()
        report['source_changes']={k:digest(ROOT/k) for k,v in sources.items() if digest(ROOT/k)!=v}
        report['engine_errors']={str(p.relative_to(folder)):[line for line in p.read_text(encoding='utf8',errors='replace').splitlines() if 'SCRIPT ERROR' in line or line.startswith('ERROR:')] for p in folder.rglob('engine.log')}
        report['measurement_valid']=len(report['cases'])==len(cases)*args.repeat and not report['failures'] and not report['source_changes'] and all(not c['issues'] for c in report['cases']) and not any(report['engine_errors'].values())
        save(folder/'report.json',report)
    if not report['measurement_valid']:raise SystemExit(1)


if __name__=='__main__':main()
