"""Real-time bank ENet over seeded loopback UDP delay/loss/duplication proxies.

Unlike fixed-step gameplay tests, this deliberately uses wall time: retransmit,
RTT, jitter and outages must be measured against the production 60 Hz scheduler.
"""
import argparse,datetime,hashlib,json,math,socket,subprocess,time
from dataclasses import asdict
from game.tests.network_fault_proxy import Profile,FaultProxy
from game.tests.verify_coop import Peer
from game.tools.coop import ROOT,HIDDEN,godot

PROFILES=[Profile('local'),Profile('rtt100',100,10),Profile('rtt200',200,25),Profile('rtt300_loss5',300,40,.05),
          Profile('rtt500_loss5',500,75,.05),Profile('rtt800_loss10',800,100,.10),
          Profile('rtt200_loss20',200,40,.20),Profile('rtt300_loss30',300,80,.30),Profile('reorder_duplicate',200,140,.02,.03),
          Profile('rtt300',300),Profile('rtt500',500),Profile('rtt800',800)]

class NetworkPeer(Peer):
    def __init__(self,folder,args):
        folder.mkdir();self.folder=folder;self.serial=0;self.log=(folder/'engine.log').open('w',encoding='utf8')
        executable=godot();direct=executable.with_name(executable.name.replace('_console.exe','.exe'))
        if direct.is_file():executable=direct
        cmd=[str(executable),'--headless','--path',str(ROOT/'game/runtime'),'--max-fps','60','--script',str(ROOT/'game/tests/network_peer_driver.gd'),
             '--',f'--test-session={folder.as_posix()}','--performance-benchmark','--coop','--real-time',*args]
        self.process=subprocess.Popen(cmd,stdout=self.log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=HIDDEN)
        (folder/'launch.json').write_text(json.dumps({'command':cmd,'pid':self.process.pid},indent=2),encoding='utf8')
        self.wait_file(folder/'ready.json',90)
    def net(self):return self.call('net_state')

def percentile(values,p):
    values=sorted(values);return values[min(len(values)-1,int((len(values)-1)*p))] if values else None

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--repeat',type=int,default=2,choices=[1,2,3]);parser.add_argument('--profiles',nargs='*');parser.add_argument('--sample-seconds',type=float,default=8)
    parser.add_argument('--skip-outages',action='store_true');args=parser.parse_args();assert 3<=args.sample_seconds<=60
    profiles=[p for p in PROFILES if not args.profiles or p.name in args.profiles];assert profiles
    folder=ROOT/'logs/sessions'/('bank-network-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    while True:
        with socket.socket(type=socket.SOCK_DGRAM) as sock:
            port=22000+int(time.time_ns()%1800)
            try:sock.bind(('127.0.0.1',port))
            except OSError:continue
            with socket.socket(type=socket.SOCK_DGRAM) as status:
                try:status.bind(('127.0.0.1',port+1));break
                except OSError:continue
        break
    peers=[];cases=[];outages=[];proxy_pairs=[];engine_errors={};fatal_error=None
    sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'game/runtime/coop').glob('*.gd')}
    def save():
        report={'scope':'Current bank, two actual headless clients and one real-time dedicated process; seeded UDP impairment in both directions. Not real VPS/GPU/FPS/long-soak validation.',
                'delay_definition':'Configured rtt_ms is added RTT; each direction gets half, with independent uniform +/- jitter_ms. Loss is per UDP datagram per direction; retransmissions also traverse proxy.',
                'harness_revision':'ordered-fixture-barrier-v3-port-unreachable-aware','cases':cases,'outages':outages,'engine_errors':engine_errors,
                'fatal_error':fatal_error,'functional_passed':not fatal_error and not engine_errors and bool(cases) and all(c['outcome']=='completed' for c in cases),
                'weak_network_quality':'not certified; completed cases may still have severe input latency or snapshot gaps',
                'sources':sources}
        path=folder/'report.json';temp=path.with_suffix('.tmp');temp.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');temp.replace(path)
    def state_triplet():return server.net(),a.net(),b.net()
    def wait_for(predicate,timeout=10):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            result=predicate()
            if result:return result
            time.sleep(.025)
        raise TimeoutError('condition did not converge')
    def leave():
        for client in [a,b]:
            state=client.net()
            if state['players'] or state['transport'] or state['recovery']['retrying']:
                if client.net()['input']:client.call('menu')
                client.call('click',control='leave_button')
        # A canceled offline client cannot notify the server. Its bounded
        # reservation must expire before the next independent profile starts.
        wait_for(lambda:not server.net()['players'] and server.net()['recovery']['occupied']==0,65)
    def join(proxies):
        start=time.monotonic()
        for index,client in enumerate([a,b]):
            client.call('fields',nickname=['Alpha','Bravo'][index],address='127.0.0.1',port=proxies[index].port)
            client.call('click',control='join_button')
        wait_for(lambda:all(len(s['players'])==2 and s['started'] for s in state_triplet()),16)
        return (time.monotonic()-start)*1000
    def fixture(name):
        serial=server.net()['fixture_barrier']+1
        server.call('fixture',name=name)
        # The marker shares reset's reliable channel. World round equality alone
        # races late resets that clear held input or restore an old player pose.
        wait_for(lambda:all(s['fixture_barrier']==serial for s in state_triplet()),16)
        wait_for(lambda:(lambda s:s[0]['round']==s[1]['round']==s[2]['round'])(state_triplet()),10)
    try:
        server=NetworkPeer(folder/'server',['--server',f'--port={port}']);peers.append(server)
        a=NetworkPeer(folder/'alpha',[]);peers.append(a)
        b=NetworkPeer(folder/'bravo',[]);peers.append(b)
        # Warm imported avatar resources through a normal clean connection first.
        warm=[FaultProxy(('127.0.0.1',port),Profile('warm'),1+i) for i in range(2)];proxy_pairs.extend(warm)
        join(warm);leave()
        for p in warm:p.close();proxy_pairs.remove(p)
        for repeat in range(args.repeat):
            for index,profile in enumerate(profiles):
                case={'profile':asdict(profile),'repeat':repeat+1,'outcome':'running','metrics':{},'issues':[],'stage':'join','measurement':'controller upper bounds until completed'};cases.append(case)
                proxies=[FaultProxy(('127.0.0.1',port),profile,20261017+repeat*1000+PROFILES.index(profile)*10+i) for i in range(2)];proxy_pairs.extend(proxies)
                start=time.monotonic()
                recording=False
                log_offsets={peer.folder.name:len((peer.folder/'engine.log').read_text(encoding='utf8').splitlines()) for peer in peers}
                try:
                    case['metrics']['join_ms']=join(proxies)
                    case['stage']='movement_fixture';fixture('firearms_range')
                    time.sleep(.5)
                    for peer in [server,a,b]:peer.call('record_start')
                    recording=True;case['stage']='movement'
                    initial=state_triplet();aid=str(initial[1]['id']);origin=initial[0]['players'][aid]['position'];visible_origin=initial[1]['players'][aid]['position']
                    movement=time.monotonic();move_epoch=a.call('input',keys=['S'])['received_at_ms'];server_seen=None;client_seen=None;released=False;stop_sent=None;stop_seen=None;stop_epoch=None
                    while time.monotonic()-movement<max(3.0,profile.rtt_ms/1000+2):
                        elapsed=time.monotonic()-movement
                        if elapsed>=.8 and not released:stop_epoch=a.call('input')['received_at_ms'];released=True;stop_sent=time.monotonic()
                        ss,aa,_=state_triplet()
                        if aid not in ss['players'] or aid not in aa['players']:raise ConnectionError('disconnected during movement')
                        if server_seen is None and math.dist(origin,ss['players'][aid]['position'])>.08:server_seen=(time.monotonic()-movement)*1000
                        if client_seen is None and math.dist(visible_origin,aa['players'][aid]['position'])>.08:client_seen=(time.monotonic()-movement)*1000
                        if released and stop_seen is None and server_seen is not None and ss['players'][aid]['motion']=='idle':stop_seen=(time.monotonic()-stop_sent)*1000
                        time.sleep(.025)
                    case['metrics'].update(move_server_ms=server_seen,move_visible_ms=client_seen,stop_server_ms=stop_seen)
                    if server_seen is None or client_seen is None:case['issues'].append('movement did not visibly respond within observation window')
                    if stop_seen is None:case['issues'].append('stop not observed within bounded window')
                    case['stage']='shot_server'
                    ss,aa,_=state_triplet();case['metrics']['position_error_after_stop']=math.dist(ss['players'][aid]['position'],aa['players'][aid]['position'])
                    before=ss['weapons'][aid]['shots'];preview_before=aa['preview_shots'];fired=time.monotonic();shot_epoch=a.call('input',buttons=['left'])['received_at_ms'];time.sleep(.06);a.call('input')
                    wait_for(lambda:server.net()['weapons'].get(aid,{}).get('shots',before)>before,8)
                    case['metrics']['shot_server_ms']=(time.monotonic()-fired)*1000
                    case['stage']='shot_clients'
                    wait_for(lambda:all(s['weapons'].get(aid,{}).get('shots',-1)==before+1 for s in [a.net(),b.net()]),8)
                    case['metrics']['shot_all_clients_ms']=(time.monotonic()-fired)*1000
                    if server.net()['weapons'][aid]['shots']!=before+1:case['issues'].append('shot executed more than once')
                    case['stage']='door_fixture';fixture('door_g_inner_a')
                    case['stage']='door_server'
                    opened=time.monotonic();a.call('input',keys=['E']);time.sleep(.06);a.call('input')
                    wait_for(lambda:server.net()['door']>.98,8);case['metrics']['door_server_complete_ms']=(time.monotonic()-opened)*1000
                    case['stage']='door_clients'
                    wait_for(lambda:a.net()['door']>.98 and b.net()['door']>.98,8);case['metrics']['door_all_clients_complete_ms']=(time.monotonic()-opened)*1000
                    # Full-world, no test population reduction: 84 actors remain in packets.
                    case['stage']='steady'
                    samples=[];t0=time.monotonic();steady_epoch=time.time()*1000;s0=server.net()['tick'];last=[-1,-1];last_changed=[t0,t0];gaps=[[],[]]
                    while time.monotonic()-t0<args.sample_seconds:
                        ss,aa,bb=state_triplet();now=time.monotonic()
                        for i,s in enumerate([aa,bb]):
                            if len(s['players'])!=2:raise ConnectionError('disconnected during steady observation')
                            if s['bank_tick']!=last[i]:
                                if last[i]>=0:gaps[i].append((now-last_changed[i])*1000)
                                last[i]=s['bank_tick'];last_changed[i]=now
                        samples.append({'elapsed':now-t0,'server':ss,'clients':[aa,bb]});time.sleep(.075)
                    telemetry=[peer.call('record_stop')['samples'] for peer in [server,a,b]]
                    recording=False
                    def first_time(rows,epoch,predicate):return next((x['time_ms']-epoch for x in rows if x['time_ms']>=epoch and predicate(x)),None)
                    case['metrics']['move_server_ms']=first_time(telemetry[0],move_epoch,lambda x:aid in x['players'] and math.dist(origin,x['players'][aid]['position'])>.08)
                    case['metrics']['move_visible_ms']=first_time(telemetry[1],move_epoch,lambda x:aid in x['players'] and math.dist(visible_origin,x['players'][aid]['position'])>.08)
                    case['metrics']['stop_server_ms']=first_time(telemetry[0],stop_epoch,lambda x:aid in x['players'] and x['players'][aid]['motion']=='idle')
                    case['metrics']['shot_server_ms']=first_time(telemetry[0],shot_epoch,lambda x:x['shots'].get(aid,0)>before)
                    case['metrics']['fire_feedback_ms']=first_time(telemetry[1],shot_epoch,lambda x:x['preview_shots']>preview_before)
                    shot_times=[first_time(rows,shot_epoch,lambda x:x['shots'].get(aid,-1)==before+1) for rows in telemetry[1:]]
                    case['metrics']['shot_all_clients_ms']=max(shot_times) if all(x is not None for x in shot_times) else None
                    steady=[[x for x in rows if x['time_ms']>=steady_epoch] for rows in telemetry]
                    duration=(steady[0][-1]['time_ms']-steady[0][0]['time_ms'])/1000
                    case['metrics']['server_hz']=(steady[0][-1]['tick']-steady[0][0]['tick'])/duration
                    gaps=[[],[]]
                    for i,rows in enumerate(steady[1:]):
                        tick=-1;last_time=None
                        for sample in rows:
                            if sample['bank_tick']!=tick:
                                if last_time is not None:gaps[i].append(sample['time_ms']-last_time)
                                tick=sample['bank_tick'];last_time=sample['time_ms']
                    case['metrics']['client_rtt_median_ms']=[percentile([x['rtt_ms'] for x in rows],.5) for rows in steady[1:]]
                    case['metrics']['world_gap_p95_ms']=[percentile(g,.95) for g in gaps]
                    case['metrics']['world_gap_max_ms']=[max(g,default=0) for g in gaps]
                    case['metrics']['world_delivery_hz']=[len(g)/duration for g in gaps]
                    case['metrics']['world_age_p95_ms']=[percentile([x['world_age_ms'] for x in rows],.95) for rows in steady[1:]]
                    case['metrics']['throttle_min']=[min(x['throttle'] for x in rows) for rows in steady[1:]]
                    case['metrics']['snapshot_bytes_mean']=sum(x['wire_bytes'] for x in steady[0])/len(steady[0])
                    case['metrics']['snapshot_assembly']=[a.net()['assembly'],b.net()['assembly']]
                    sample_path=folder/f'{profile.name}-r{repeat+1}.json';sample_path.write_text(json.dumps({'controller_samples':samples,'process_frame_telemetry':telemetry,'input_epochs_ms':{'move':move_epoch,'stop':stop_epoch,'shot':shot_epoch}},indent=2),encoding='utf8');case['samples']=sample_path.name
                    case['outcome']='completed' if not case['issues'] else 'degraded'
                    case['stage']='complete';case['measurement']='process-frame telemetry; join and door are controller upper bounds'
                except Exception as exc:
                    case['outcome']='failed';case['issues'].append(str(exc));case['end_states']=state_triplet()
                finally:
                    case['proxies_before_cleanup']=[p.report() for p in proxies]
                    if any(p['error'] for p in case['proxies_before_cleanup']):
                        case['outcome']='failed';case['issues'].append('proxy failed before cleanup; game conclusions need isolation')
                    if recording:
                        telemetry=[peer.call('record_stop')['samples'] for peer in [server,a,b]]
                        sample_path=folder/f'{profile.name}-r{repeat+1}-failed.json'
                        sample_path.write_text(json.dumps({'process_frame_telemetry':telemetry,'stage':case['stage']},indent=2),encoding='utf8');case['samples']=sample_path.name
                    a.call('input');b.call('input')
                    try:leave()
                    except Exception as exc:case['issues'].append('cleanup: '+str(exc))
                    for p in proxies:p.close();proxy_pairs.remove(p)
                    case['engine_errors']={}
                    for peer in peers:
                        lines=(peer.folder/'engine.log').read_text(encoding='utf8').splitlines()[log_offsets[peer.folder.name]:]
                        errors=[line for line in lines if line.startswith(('ERROR:','SCRIPT ERROR:'))]
                        if errors:case['engine_errors'][peer.folder.name]=errors
                    case['proxies']=[p.report() for p in proxies];case['duration_s']=time.monotonic()-start;save()
                print(json.dumps({'profile':profile.name,'repeat':repeat+1,'outcome':case['outcome'],'metrics':case['metrics'],'issues':case['issues']}),flush=True)
        if not args.skip_outages:
            proxies=[FaultProxy(('127.0.0.1',port),Profile('outage_control',100,10),880+i) for i in range(2)];proxy_pairs.extend(proxies);join(proxies)
            for seconds in [3,12]:
                fixture('firearms_range');time.sleep(.5);aid=str(a.net()['id'])
                a.call('input',keys=['S']);wait_for(lambda:server.net()['players'][aid]['motion']!='idle')
                started=time.monotonic();proxies[0].blackout(seconds);a.call('input');rows=[];stopped=None;client_disconnect=None
                while time.monotonic()-started<seconds+2:
                    ss,aa,bb=state_triplet();elapsed=time.monotonic()-started;rows.append({'elapsed':elapsed,'server':ss,'client':aa})
                    if stopped is None and (aid not in ss['players'] or ss['players'][aid]['motion']=='idle'):stopped=elapsed
                    if client_disconnect is None and not aa['players']:client_disconnect=elapsed
                    if len(bb['players'])<1:raise AssertionError('unaffected teammate lost connection')
                    time.sleep(.05)
                recovered=a.net();item={'blackout_seconds':seconds,'server_stopped_s':stopped,'client_disconnected_s':client_disconnect,'session_survived':bool(recovered['players']),'samples':rows}
                assert stopped is not None and stopped<.6,item
                wait_for(lambda:len(a.net()['players'])==2 and a.net()['input'] and a.net()['world_age_ms']<500,30)
                item['automatic_recovery_after_link_ms']=max(0,(time.monotonic()-started-seconds)*1000)
                item['recovery']=a.net()['recovery']
                outages.append(item);save();print(json.dumps({k:v for k,v in item.items() if k!='samples'}),flush=True)
            leave()
    except Exception as exc:
        fatal_error=repr(exc)
        raise
    finally:
        for proxy in proxy_pairs:proxy.close()
        for peer in reversed(peers):peer.close()
        for peer in peers:
            errors=[line for line in (peer.folder/'engine.log').read_text(encoding='utf8').splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))]
            if errors:engine_errors[peer.folder.name]=errors
        if any(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h for p,h in sources.items()):fatal_error='Runtime changed during measurement'
        save()
    print(folder/'report.json',flush=True)
    assert not engine_errors,engine_errors
    assert all(c['outcome']=='completed' for c in cases),'Network cases failed; inspect report and preserved logs'

if __name__=='__main__':main()
