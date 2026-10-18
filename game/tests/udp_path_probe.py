"""Bounded 1:1 UDP echo audit to separate the WAN from Godot/ENet.

Only the empty bank port is temporarily used; production is restored in finally.
No proxy settings or routes change. Raw payloads and the transient token are not
included in the public report.
"""
import argparse,collections,datetime,json,secrets,select,shlex,socket,struct,subprocess,time
from pathlib import Path
from game.tools.coop import ROOT,HIDDEN
from game.tools.local_bank_server import query
from game.tests.benchmark_vps_coop import SSH,ssh
from game.tests.benchmark_coop_combat import dist

SERVER='''import socket,time,sys,collections,json
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1048576)
s.bind(('0.0.0.0',24567));s.settimeout(.2)
token=bytes.fromhex(sys.argv[1]);end=time.monotonic()+90;counts=collections.Counter()
print('READY',flush=True)
while time.monotonic()<end:
 try:d,a=s.recvfrom(2048)
 except socket.timeout:continue
 if d==token+b'STOP':break
 if not 24<=len(d)<=1400 or not d.startswith(token):continue
 counts[str(a)]+=1;s.sendto(d,a)
print(json.dumps([{'received':n,'via_vps_proxy':a.startswith("('207.57.124.243',")} for a,n in counts.items()]),flush=True)
'''

def sample(native,burst,token,interface,address,seconds=8):
    peers=[];sent={};seen={};latencies=[];duplicates=0
    for index in range(4):
        s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1048576)
        if native:s.bind((address,0));s.setsockopt(socket.IPPROTO_IP,31,struct.pack('!I',interface))
        s.connect(('207.57.124.243',24567));s.setblocking(False);peers.append(s);sent[s]={};seen[s]=set()
    start=time.monotonic();next_send=start;serial=0
    try:
        while time.monotonic()<start+seconds+1:
            now=time.monotonic()
            if now>=next_send and now<start+seconds:
                for _ in range(10 if burst else 1):
                    serial+=1;data=token+struct.pack('!I',serial)+secrets.token_bytes(900-len(token)-4)
                    for s in peers:s.send(data);sent[s][serial]=time.monotonic()
                next_send=now+(.1 if burst else .01)
            ready,_,_=select.select(peers,[],[],.001)
            for s in ready:
                while True:
                    try:data=s.recv(2048)
                    except BlockingIOError:break
                    if len(data)!=900 or not data.startswith(token):continue
                    number=struct.unpack('!I',data[len(token):len(token)+4])[0]
                    if number not in sent[s]:continue
                    if number in seen[s]:duplicates+=1;continue
                    seen[s].add(number);latencies.append((time.monotonic()-sent[s][number])*1000)
        return {'physical_interface':native,'burst':burst,'seconds':seconds,'bytes_per_datagram':900,
                'peers':[{'sent':len(sent[s]),'received':len(seen[s]),'loss':1-len(seen[s])/len(sent[s])} for s in peers],
                'rtt_ms':dist(latencies),'duplicates':duplicates}
    finally:
        for s in peers:s.close()

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',choices=['bank'],required=True)
    p.add_argument('--interface',type=int,required=True);p.add_argument('--address',required=True);args=p.parse_args()
    status=query('207.57.124.243',timeout=3);assert status and status['occupied']==0,status
    folder=ROOT/'logs/network'/('bank-udp-path-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    token=secrets.token_bytes(16);process=None;report={'cases':[],'failure':None}
    ssh('sudo -n systemctl stop bank-coop.service')
    try:
        command='python3 -u -c '+shlex.quote(SERVER)+' '+shlex.quote(token.hex())
        process=subprocess.Popen(SSH+[command],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=HIDDEN)
        assert process.stdout.readline().strip()=='READY'
        for native in [False,True]:
            for burst in [False,True]:
                row=sample(native,burst,token,args.interface,args.address);report['cases'].append(row);print(json.dumps(row),flush=True)
    except BaseException as exc:report['failure']=repr(exc);raise
    finally:
        if process:
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as stop:
                for _ in range(5):stop.sendto(token+b'STOP',('207.57.124.243',24567))
            # Closing SSH does not promise to kill the remote Python process;
            # its 90s bound does. Wait before restoring the same UDP listener.
            try:
                output,error=process.communicate(timeout=55);report['server']=output;report['server_errors']=error
            except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
        report['service']=ssh('sudo -n systemctl start bank-coop.service; systemctl is-active bank-coop.service')
        (folder/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')

if __name__=='__main__':main()
