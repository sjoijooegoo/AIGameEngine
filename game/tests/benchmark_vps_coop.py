"""Current bank over real WAN: an SSH-controlled VPS server and Windows clients.

The public production service is restored in finally. The debug engine reads the
exact deployed release pack; its private file bridge is reachable only via SSH.
"""
import argparse
import base64
import gzip
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import os
from pathlib import Path
import queue
import shlex
import subprocess
import threading
import time
from game.tools.coop import ROOT,HIDDEN,godot
from game.tools.local_bank_server import query
from game.tests.benchmark_coop_combat import PerfPeer,Counters,summary,save,read,digest,dist
from game.tests.benchmark_wsl_coop import capacity_metrics,budget_result,read_result

SSH=['ssh','-T','-o','BatchMode=yes','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=3','-p','5579','dev@207.57.124.243']
if os.environ.get('BANK_VPS_SSH_DIRECT_ADDRESS'):
    interface=int(os.environ['BANK_VPS_SSH_DIRECT_INTERFACE'])
    import ipaddress
    address=str(ipaddress.IPv4Address(os.environ['BANK_VPS_SSH_DIRECT_ADDRESS']))
    proxy=f'{ROOT.as_posix()}/.venv/Scripts/python.exe {ROOT.as_posix()}/game/tests/ssh_direct_socket.py --interface {interface} --address {address} --host %h --port %p'
    SSH[1:1]=['-o','ProxyCommand='+proxy]

def ssh(command):
    return subprocess.run(SSH+[command],capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=HIDDEN,timeout=90,check=True).stdout


class RemotePeer:
    def __init__(self,folder,count,port=24567,pack='/opt/bank-coop/current/bank-coop-server.x86_64',candidate=None):
        folder.mkdir();self.folder=folder;self.inbox=queue.Queue();self.closed=False
        self.log=(folder/'ssh.log').open('w',encoding='utf8')
        session='/home/dev/bank-coop-validation/sessions/'+folder.parent.parent.name+f'-{count}p'
        command=['python3','/home/dev/bank-coop-validation/drivers/vps_ssh_bridge.py',
                 '--engine','/home/dev/.local/share/bank-coop-tools/Godot_v4.7.2-stable_linux.x86_64',
                 '--pack',pack,
                 '--overlay','/home/dev/bank-coop-validation/validation-overlay.pck',
                 '--drivers','/home/dev/bank-coop-validation/drivers','--session',session,'--players',str(count),'--port',str(port)]
        if candidate:command+=['--candidate-overlay',candidate]
        self.process=subprocess.Popen(SSH+[shlex.join(command)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.log,
                                      text=True,encoding='utf8',bufsize=1,creationflags=HIDDEN)
        def reader():
            for line in self.process.stdout:self.inbox.put(line)
            self.inbox.put(None)
        threading.Thread(target=reader,daemon=True).start()
        self.environment=self.receive(200);assert self.environment['ready'];save(folder/'environment.json',self.environment)
        save(folder/'launch.json',{'ssh':SSH,'remote_command':command,'remote_session':session})
    def receive(self,timeout=90):
        line=self.inbox.get(timeout=timeout)
        if line is None:raise RuntimeError('SSH bridge closed; inspect '+str(self.folder/'ssh.log'))
        value=json.loads(line)
        if 'error' in value:raise RuntimeError(value['error'])
        return value
    def request(self,op,**values):
        self.process.stdin.write(json.dumps({'op':op,**values})+'\n');self.process.stdin.flush()
        return self.receive()['result']
    def call(self,command,**values):
        result=self.request('call',command=command,**values)
        with (self.folder/'trace.jsonl').open('a',encoding='utf8') as out:out.write(json.dumps({'command':command,'arguments':values,'result':result},ensure_ascii=False)+'\n')
        return result
    def close(self):
        if self.closed:return
        self.closed=True
        try:
            if self.process.poll() is None:
                result=self.request('quit');(self.folder/'engine.log').write_text(result['log'],encoding='utf8')
                self.process.wait(timeout=20)
        finally:
            if self.process.poll() is None:self.process.terminate();self.process.wait(timeout=10)
            self.log.close()


class VpsClient(PerfPeer):
    def __init__(self,folder,args,rendered,lean,project=None):
        folder.mkdir();self.folder=folder;self.serial=0;self.log=(folder/'engine.log').open('w',encoding='utf8')
        exe=godot();direct=exe.with_name(exe.name.replace('_console.exe','.exe'));exe=direct if direct.is_file() else exe
        command=[str(exe),'--path',str(project or ROOT/'game/runtime'),'--resolution','1920x1080','--position','10,10',
                 '--script',str(ROOT/'game/tests/vps_client_performance.gd')]
        if not rendered:command.append('--headless')
        command+=['--','--test-session='+folder.as_posix(),'--performance-benchmark','--coop',*args]
        if lean:command.append('--lean-load-client')
        self.process=subprocess.Popen(command,cwd=ROOT,stdout=self.log,stderr=subprocess.STDOUT,creationflags=HIDDEN)
        save(folder/'launch.json',{'command':command,'pid':self.process.pid});self.wait_file(folder/'ready.json',150)
        self.counters=Counters(self.process.pid)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--players',type=int,nargs='+',choices=[2,4],default=[2,4])
    parser.add_argument('--populations',type=int,nargs='+',default=[24,32,48,84])
    parser.add_argument('--repeat',type=int,default=2);parser.add_argument('--seconds',type=float,default=30)
    parser.add_argument('--port',type=int,default=24567);parser.add_argument('--server-pack',default='/opt/bank-coop/current/bank-coop-server.x86_64');parser.add_argument('--candidate-overlay')
    parser.add_argument('--client-project',type=Path)
    parser.add_argument('--transport',choices=['udp','tcp'],default='udp')
    parser.add_argument('--tcp-interface',type=int,help='Diagnostic per-socket TCP interface, no routing/config changes')
    parser.add_argument('--tcp-address')
    parser.add_argument('--audit-proxy',action='store_true',help='Transparent local IPv4 UDP relay; capture only hashes and ENet headers')
    parser.add_argument('--audit-interface',type=int,help='Windows IP_UNICAST_IF for this diagnostic relay only')
    parser.add_argument('--audit-address',help='Physical IPv4 address for this diagnostic relay only')
    parser.add_argument('--headless',action='store_true');args=parser.parse_args()
    if args.client_project:args.client_project=args.client_project.resolve()
    assert args.tcp_interface is None or (args.transport=='tcp' and args.tcp_address and not args.audit_proxy)
    assert 1<=args.repeat<=3 and 5<=args.seconds<=60 and all(1<=n<=84 for n in args.populations)
    folder=ROOT/'logs/performance'/('bank-vps-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    status=query('207.57.124.243',timeout=3);assert status and status['occupied']==0,status
    (folder/'host-before.txt').write_text(ssh('uname -a; lscpu; free -m; uptime; ps -eo pid,comm,pcpu,rss --sort=-pcpu | head -15; systemctl show bank-coop.service -p MainPID -p MemoryCurrent -p NRestarts'),encoding='utf8')
    paths=[p for base in ['game/runtime/coop','game/runtime/scripts','game/runtime/frontend','game/runtime/data','engine/godot/performance'] for p in (ROOT/base).rglob('*') if p.suffix in ['.gd','.json']]
    paths += [ROOT/'game/tests'/name for name in ['vps_performance.gd','vps_client_performance.gd','vps_ssh_bridge.py','wsl_coop_performance.gd','coop_combat_performance.gd','bank_coop_driver.gd']]
    if args.client_project:paths += list((args.client_project/'coop').glob('*.gd'))
    sources={p.relative_to(ROOT).as_posix():digest(p) for p in paths};save(folder/'sources.json',sources)
    save(folder/'plan.json',{'players':args.players,'populations':args.populations,'repeat':args.repeat,'seconds':args.seconds,'warmup':5,'transport':args.transport,'tcp_interface':args.tcp_interface,
        'topology':'One dedicated Linux VPS server using deployed release assets + debug engine. One full rendered Windows client (unless --headless), remaining lean-presentation Windows load generators. Real WAN, no injected impairment.',
        'limits':'5s warmup, bounded real inputs and setup-only diagnostic HP. Initial live population becomes corpses. Full rendered client is distinguished from lean load generators. Profiler scopes inclusive; physics monitor is a held once-per-second maximum.'})
    peers=[];proxies=[];tcp_relays=[];pool=ThreadPoolExecutor(max_workers=5);report={'cases':[],'failures':[]}
    def steps():
        # VPS drivers run continuously: stepping here would double-advance.
        time.sleep(.1)
    base=read(ROOT/'game/tests/coop_combat_performance_suite.json')['cases'][0]
    ssh('sudo -n systemctl stop bank-coop.service')
    try:
        for count in args.players:
            group=folder/f'{count}p';group.mkdir();server=RemotePeer(group/'server',count,args.port,args.server_pack,args.candidate_overlay);peers.append(server)
            for slot in range(count):
                flags=['--connect=207.57.124.243',f'--port={args.port}',f'--name=VPSPerf{slot+1}','--transport='+args.transport]
                if args.tcp_interface is not None:
                    from game.tests.tcp_direct_relay import DirectTcpRelay
                    relay=DirectTcpRelay(('207.57.124.243',args.port),args.tcp_interface,args.tcp_address)
                    tcp_relays.append((group/f'client-{slot+1}',relay))
                    flags=['--connect=127.0.0.1',f'--port={relay.port}',f'--name=VPSPerf{slot+1}','--transport=tcp']
                if args.audit_proxy:
                    from game.tests.network_fault_proxy import FaultProxy,Profile
                    import hashlib
                    class AuditProxy(FaultProxy):
                        def __init__(self):
                            self.packets=[]
                            super().__init__(('207.57.124.243',args.port),Profile('transparent'),1)
                        def schedule(self,direction,data,sock,address=None):
                            self.packets.append({'time':time.time(),'direction':direction,'size':len(data),'hash':hashlib.sha256(data).hexdigest(),'header':data[:12].hex()})
                            super().schedule(direction,data,sock,address)
                        def create_upstream(self):
                            if args.audit_interface is None:return super().create_upstream()
                            import socket,struct
                            upstream=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
                            upstream.bind((args.audit_address,0));upstream.setsockopt(socket.IPPROTO_IP,31,struct.pack('!I',args.audit_interface))
                            upstream.connect(self.target);upstream.setblocking(False);return upstream
                    proxy=AuditProxy();proxies.append((group/f'client-{slot+1}',proxy))
                    flags=['--connect=127.0.0.1',f'--port={proxy.port}',f'--name=VPSPerf{slot+1}']
                peer=VpsClient(group/f'client-{slot+1}',flags,rendered=slot==0 and not args.headless,lean=slot!=0,project=args.client_project)
                peers.append(peer)
            for _ in range(90):
                steps();states=[p.call('perf_status') for p in peers]
                if all(s['players']==count and s['started'] for s in states):break
            else:raise RuntimeError('Players did not synchronize over WAN')
            clocks=[]
            for _ in range(5):
                before=time.time();remote=server.request('clock')['time'];after=time.time()
                clocks.append({'rtt':after-before,'offset':remote-(before+after)/2})
            offset=min(clocks,key=lambda x:x['rtt'])['offset'];save(group/'clock-offset.json',clocks)
            for repeat in range(1,args.repeat+1):
                populations=args.populations if repeat%2 else list(reversed(args.populations))
                for population in populations:
                    case={**base,'id':f'hall_{count}p_{population}','label':f'一楼大厅 · {count}人{population}敌','players':count,'population':population,'repeat':repeat,'resolution':[1920,1080]}
                    directory=folder/(case['id']+f'-r{repeat}');directory.mkdir()
                    for p in peers:p.call('perf_config',config=case)
                    placement=server.call('perf_fixture',config=case);save(directory/'placement.json',placement)
                    for _ in range(40):
                        steps();states=[p.call('perf_status') for p in peers]
                        if all(s['active']==population and s['players']==count and s['round']==states[0]['round'] for s in states):break
                    else:raise RuntimeError('WAN fixture not synchronized')
                    start=time.time()+5;warmup=5
                    server.request('sample',start=start+offset+warmup,seconds=args.seconds)
                    server.call('perf_run',start=start+offset,warmup=warmup,seconds=args.seconds)
                    for p in peers[1:]:
                        (p.folder/'result.json').unlink(missing_ok=True);p.call('perf_run',start=start,warmup=warmup,seconds=args.seconds)
                    os_rows={p.folder.name:[] for p in peers[1:]};finish=start+warmup+args.seconds
                    while time.time()<finish:
                        if time.time()>=start+warmup:
                            for p in peers[1:]:os_rows[p.folder.name].append(p.counters.sample())
                        time.sleep(min(.5,max(.01,finish-time.time())))
                    collected=json.loads(gzip.decompress(base64.b64decode(server.request('collect')['gzip'])));raws={'server':collected['raw']};os_rows['server']=collected['os']
                    for p in peers[1:]:p.wait_file(p.folder/'result.json',40);raws[p.folder.name]=read_result(p.folder/'result.json')
                    results={}
                    for name,raw in raws.items():
                        save(directory/(name+'-raw.json'),raw);results[name]=summary(raw,os_rows[name])
                        for field in ['rtt_ms','rtt_variance_ms','throttle']:results[name][field]=dist(t.get(field) for t in raw['telemetry'])
                    save(directory/'os-samples.json',os_rows);save(directory/'linux-os-samples.json',collected['os'])
                    authority=results['server'];issues=[]
                    if placement.get('world_overlaps',-1)!=0:issues.append('Invalid placement')
                    for name,r in results.items():
                        if r['dropped_samples'] or not r['script_tick_ms']:issues.append(name+': missing samples')
                        if r['finish']['players']!=count or r['finish']['active']!=population:issues.append(name+': lost connection/population')
                        if name!='server':
                            telemetry=raws[name]['telemetry']
                            if max((t.get('world_age_ms',0) for t in telemetry),default=0)>1500:issues.append(name+': world stall over 1500ms')
                            if any(t.get('retrying') for t in telemetry) or len({t['peer_id'] for t in telemetry if 'peer_id' in t})>1:issues.append(name+': automatic reconnection')
                    if any(c['shots']<3 for c in authority['finish']['combat'].values()):issues.append('Not enough real shots per player')
                    if authority['finish']['kills']<2:issues.append('No meaningful kills')
                    if args.seconds>=16 and not sum(authority['finish'].get('loaded_rounds',{}).values()):issues.append('No completed reload')
                    if not any(c['hp']<10000 for c in authority['finish']['combat'].values()):issues.append('No enemy contact')
                    cap=capacity_metrics(raws['server'],collected['os']);budget=budget_result(authority,cap)
                    row={'config':case,'results':results,'issues':issues,'capacity':cap,'budget':budget,'within_budget':not issues and all(budget.values()),'evidence':directory.name}
                    report['cases'].append(row);save(folder/'report.json',report)
                    if not args.headless:
                        capture=peers[1].call('capture')['capture'];(directory/'combat.png').write_bytes(Path(capture).read_bytes())
                    print(case['id'],repeat,'serverHz',round(authority['tick_hz'],2),'P95',round(authority['script_tick_ms']['p95'],2),'CPU',round(authority['os_cpu_one_core_pct']['mean'],1),
                        'clientFPS',round(results['client-1']['fps_average'] or 0,1),'worldHz',round(results['client-1']['world_delivery_hz'] or 0,1),'issues',issues,flush=True)
            for p in reversed(peers):p.close()
            peers.clear()
    except Exception as exc:report['failures'].append(repr(exc));raise
    finally:
        for p in reversed(peers):
            try:p.close()
            except Exception as exc:report['failures'].append('cleanup: '+repr(exc))
        for directory,proxy in proxies:
            proxy.close();save(directory/'proxy.json',proxy.report())
            (directory/'datagrams.json.gz').write_bytes(gzip.compress(json.dumps(proxy.packets).encode()))
        for directory,relay in tcp_relays:
            relay.close();save(directory/'tcp-direct.json',relay.report())
            if relay.errors:report['failures'].append('TCP relay error: '+str(relay.errors))
        pool.shutdown()
        report['source_changes']={k:digest(ROOT/k) for k,v in sources.items() if digest(ROOT/k)!=v}
        report['engine_errors']={str(p.relative_to(folder)):[l for l in p.read_text(encoding='utf8',errors='replace').splitlines() if 'SCRIPT ERROR' in l or l.startswith('ERROR:')] for p in folder.rglob('engine.log')}
        report['measurement_complete']=len(report['cases'])==len(args.players)*len(args.populations)*args.repeat and not report['failures'] and not report['source_changes'] and not any(report['engine_errors'].values())
        report['all_cases_within_budget']=report['measurement_complete'] and all(c['within_budget'] for c in report['cases'])
        try:report['restored_service']=ssh('sudo -n systemctl start bank-coop.service; systemctl is-active bank-coop.service')
        finally:save(folder/'report.json',report)
    print(folder,flush=True)
    if not report['all_cases_within_budget']:raise SystemExit(1)


if __name__=='__main__':main()
