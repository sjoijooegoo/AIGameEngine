"""Bounded loopback UDP fault injector. Does not change OS networking or game data."""
from dataclasses import dataclass,asdict
import heapq,random,select,socket,threading,time

@dataclass(frozen=True)
class Profile:
    name: str
    rtt_ms: float=0
    jitter_ms: float=0 # independent uniform +/- jitter on EACH direction
    loss: float=0 # independent datagram loss on EACH direction
    duplicate: float=0

class FaultProxy:
    def __init__(self,target,profile,seed):
        self.target=target;self.profile=profile;self.seed=seed;self.rng=random.Random(seed)
        self.local=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);self.local.bind(('127.0.0.1',0));self.local.setblocking(False)
        self.port=self.local.getsockname()[1];self.channels={};self.queue=[];self.queued_bytes=0;self.serial=0
        self.stop=threading.Event();self.block_until=0.0;self.started=time.monotonic();self.error=None;self.socket_events=[]
        self.stats={d:{'received':0,'bytes':0,'random_dropped':0,'blackout_dropped':0,'overflow_dropped':0,'sent':0,'duplicates':0,'actual_delay_ms':[]} for d in ['up','down']}
        self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()

    def blackout(self,seconds):self.block_until=time.monotonic()+seconds

    def socket_event(self,operation,exc):
        # On Windows an ICMP Port Unreachable for a client that has closed its
        # socket can surface on the shared UDP listener's next recvfrom call.
        # It concerns that endpoint; it must not stop forwarding other clients.
        if len(self.socket_events)<64:self.socket_events.append({'elapsed_s':time.monotonic()-self.started,'operation':operation,'error':repr(exc)})

    def schedule(self,direction,data,sock,address=None):
        now=time.monotonic();stats=self.stats[direction];stats['received']+=1;stats['bytes']+=len(data)
        if now<self.block_until:stats['blackout_dropped']+=1;return
        if self.rng.random()<self.profile.loss:stats['random_dropped']+=1;return
        copies=2 if self.rng.random()<self.profile.duplicate else 1
        stats['duplicates']+=copies-1
        for _ in range(copies):
            if len(self.queue)>=4096 or self.queued_bytes+len(data)>8*1024*1024:stats['overflow_dropped']+=1;continue
            delay=max(0,self.profile.rtt_ms/2+self.rng.uniform(-self.profile.jitter_ms,self.profile.jitter_ms))/1000
            self.serial+=1;heapq.heappush(self.queue,(now+delay,self.serial,now,direction,data,sock,address));self.queued_bytes+=len(data)

    def run(self):
        try:
            while not self.stop.is_set():
                now=time.monotonic()
                while self.queue and self.queue[0][0]<=now:
                    _,_,received,direction,data,sock,address=heapq.heappop(self.queue);self.queued_bytes-=len(data)
                    if now<self.block_until:self.stats[direction]['blackout_dropped']+=1;continue
                    try:
                        sock.sendto(data,address) if address else sock.send(data)
                        stats=self.stats[direction];stats['sent']+=1
                        if len(stats['actual_delay_ms'])<20000:stats['actual_delay_ms'].append((time.monotonic()-received)*1000)
                    except (ConnectionResetError,ConnectionRefusedError) as exc:self.socket_event('send',exc)
                readers=[self.local,*[x['socket'] for x in self.channels.values()]]
                timeout=min(.005,max(0,self.queue[0][0]-time.monotonic())) if self.queue else .005
                ready,_,_=select.select(readers,[],[],timeout)
                for sock in ready:
                    if sock is self.local:
                        try:data,address=sock.recvfrom(65535)
                        except (ConnectionResetError,ConnectionRefusedError) as exc:self.socket_event('client_receive',exc);continue
                        if address not in self.channels:
                            if len(self.channels)>=8:continue
                            upstream=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);upstream.connect(self.target);upstream.setblocking(False)
                            self.channels[address]={'socket':upstream}
                        self.schedule('up',data,self.channels[address]['socket'])
                    else:
                        try:data=sock.recv(65535)
                        except (ConnectionResetError,ConnectionRefusedError) as exc:self.socket_event('server_receive',exc);continue
                        address=next(a for a,x in self.channels.items() if x['socket'] is sock)
                        self.schedule('down',data,self.local,address)
        except Exception as exc:self.error=repr(exc)

    def report(self):
        result={'profile':asdict(self.profile),'seed':self.seed,'duration_s':time.monotonic()-self.started,'error':self.error,'socket_events':list(self.socket_events),'directions':{}}
        for direction,stats in self.stats.items():
            values=sorted(stats['actual_delay_ms']);summary={k:v for k,v in stats.items() if k!='actual_delay_ms'}
            summary['delay_mean_ms']=sum(values)/len(values) if values else None
            summary['delay_p95_ms']=values[int((len(values)-1)*.95)] if values else None
            result['directions'][direction]=summary
        return result

    def close(self):
        self.stop.set();self.thread.join(2)
        self.local.close()
        for channel in self.channels.values():channel['socket'].close()
