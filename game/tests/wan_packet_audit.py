"""Bounded two-ended packet audit for this bank VPS; payloads stay in local logs.

The public report contains hashes/lengths only, never ENet authentication data.
A transparent loopback proxy records the client-side datagrams without loss or
latency injection. tcpdump is restricted to the bank game port on the VPS.
"""
import argparse,collections,datetime,gzip,hashlib,json,shlex,struct,subprocess,time
from pathlib import Path
from game.tests.network_fault_proxy import FaultProxy,Profile
from game.tests.benchmark_vps_coop import SSH,ssh
from game.tools.coop import ROOT,HIDDEN
from game.tools.local_bank_server import query

class AuditProxy(FaultProxy):
    def __init__(self,target):
        self.packets=[]
        super().__init__(target,Profile('transparent'),1)
    def schedule(self,direction,data,sock,address=None):
        self.packets.append({'time':time.time(),'direction':direction,'size':len(data),'hash':hashlib.sha256(data).hexdigest()})
        super().schedule(direction,data,sock,address)

def packets(path,port):
    rows=[]
    with path.open('rb') as f:
        header=f.read(24);endian='<' if header[:4]==b'\xd4\xc3\xb2\xa1' else '>'
        link=struct.unpack(endian+'I',header[20:24])[0]
        assert link in [1,113,276],link
        while h:=f.read(16):
            sec,usec,length,_=struct.unpack(endian+'IIII',h);frame=f.read(length)
            offset=14 if link==1 else 16 if link==113 else 20
            proto=frame[12:14] if link==1 else frame[14:16] if link==113 else frame[:2]
            if proto!=b'\x08\x00':continue
            ip=frame[offset:];ihl=(ip[0]&15)*4
            if ip[9]!=17 or struct.unpack('!H',ip[6:8])[0]&0x3fff:continue
            udp=ip[ihl:];src,dst,length,_=struct.unpack('!HHHH',udp[:8]);data=udp[8:length]
            if src!=port and dst!=port:continue
            rows.append({'time':sec+usec/1e6,'direction':'down' if src==port else 'up','size':len(data),'hash':hashlib.sha256(data).hexdigest(),'client_port':dst if src==port else src,
                         'source_ip':'.'.join(map(str,ip[12:16])),'destination_ip':'.'.join(map(str,ip[16:20])),'enet_header':data[:20].hex()})
    return rows

def compare(server,client):
    out={}
    for direction in ['up','down']:
        sent=[p for p in (server if direction=='down' else client) if p['direction']==direction]
        received=[p for p in (client if direction=='down' else server) if p['direction']==direction]
        budget=collections.Counter(p['hash'] for p in received);lost=[]
        for p in sent:
            if budget[p['hash']]:budget[p['hash']]-=1
            else:lost.append(p)
        out[direction]={'sent':len(sent),'received':len(received),'unmatched':len(lost),'unmatched_sizes':dict(collections.Counter(p['size'] for p in lost)),
                        'unmatched_by_second':dict(collections.Counter(int(p['time']-sent[0]['time']) for p in lost)) if sent else {}}
    return out

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True)
    parser.add_argument('--package',type=Path,required=True);parser.add_argument('--port',type=int,default=24567)
    parser.add_argument('--direct',action='store_true');parser.add_argument('--seconds',type=int,default=60);args=parser.parse_args();assert 20<=args.seconds<=180
    status=query('207.57.124.243',port=args.port,timeout=3);assert status and status['occupied']==0,status
    folder=ROOT/'logs/network'/('bank-wan-audit-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    remote='/home/dev/bank-coop-validation/'+folder.name;ssh('mkdir -p '+shlex.quote(remote))
    caplog=(folder/'capture.log').open('w',encoding='utf8')
    command=f'sudo -n timeout --signal=INT {args.seconds+45} tcpdump -U -n -i any -s 0 -w {shlex.quote(remote+"/network.pcap")} '+shlex.quote('udp port '+str(args.port))
    capture=subprocess.Popen(SSH+[command],stdout=caplog,stderr=subprocess.STDOUT,creationflags=HIDDEN)
    proxies=[];peers=[];logs=[];samples=[];failure=None
    try:
        time.sleep(2)
        for i in range(2):
            proxy=None if args.direct else AuditProxy(('207.57.124.243',args.port))
            if proxy:proxies.append(proxy)
            log=(folder/f'client-{i+1}.log').open('w',encoding='utf8');logs.append(log)
            command=[str((args.package/'BankCoop.exe').resolve()),'--headless','--max-fps','60','--','--connect='+('207.57.124.243' if args.direct else '127.0.0.1'),f'--port={args.port if args.direct else proxy.port}',f'--name=Audit{i+1}']
            peers.append(subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,creationflags=HIDDEN))
        start=time.monotonic()
        while time.monotonic()-start<args.seconds:
            samples.append({'time':time.time(),'status':query('207.57.124.243',port=args.port,timeout=2)})
            assert all(p.poll() is None for p in peers)
            time.sleep(2)
    except Exception as exc:failure=repr(exc);raise
    finally:
        for p in peers:
            if p.poll() is None:p.terminate();p.wait(timeout=10)
        time.sleep(2)
        for p in proxies:p.close()
        for f in logs:f.close()
        capture.wait(timeout=60);caplog.close()
        subprocess.run(['scp','-P','5579','dev@207.57.124.243:'+remote+'/network.pcap',str(folder/'network.pcap')],check=True,creationflags=HIDDEN,timeout=90)
        server=packets(folder/'network.pcap',args.port);client=[p for proxy in proxies for p in proxy.packets]
        report={'direct':args.direct,'comparison':compare(server,client) if not args.direct else {'server_packets':len(server),'client_ports':dict(collections.Counter(p['client_port'] for p in server))},'samples':samples,'proxy':[p.report() for p in proxies],'failure':failure}
        (folder/'packet-hashes.json.gz').write_bytes(gzip.compress(json.dumps({'server':server,'client':client}).encode()))
        (folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
        print(json.dumps(report['comparison']),flush=True)

if __name__=='__main__':main()
