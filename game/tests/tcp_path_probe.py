"""Bounded authenticated TCP echo, independent of Godot; no system route changes."""
import argparse,concurrent.futures,datetime,json,secrets,shlex,socket,ssl,struct,subprocess,time
from game.tools.coop import ROOT,HIDDEN
from game.tools.local_bank_server import query
from game.tests.benchmark_vps_coop import SSH,ssh
from game.tests.benchmark_coop_combat import dist

SERVER=r'''import socket,threading,time,sys,json,ssl,subprocess,tempfile
token=bytes.fromhex(sys.argv[1]);stop=threading.Event();counts=[];threads=[]
tls=sys.argv[2]=='tls';directory=None;context=None
if tls:
 directory=tempfile.TemporaryDirectory(prefix='bank-tcp-echo-')
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',directory.name+'/key.pem','-out',directory.name+'/cert.pem','-days','1','-subj','/CN=bank-coop.test'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(directory.name+'/cert.pem',directory.name+'/key.pem')
def client(c,via_self):
 total=0
 try:
  c.settimeout(15)
  if tls:c=context.wrap_socket(c,server_side=True)
  prefix=b''
  while len(prefix)<20:
   part=c.recv(20-len(prefix))
   if not part:return
   prefix+=part
  if prefix==token+b'STOP':stop.set();return
  if not prefix.startswith(token):return
  c.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1);c.sendall(prefix);total=len(prefix)
  while not stop.is_set():
   data=c.recv(65536)
   if not data:break
   c.sendall(data);total+=len(data)
 except OSError:pass
 finally:c.close();counts.append({'bytes':total,'via_vps_proxy':via_self})
s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('0.0.0.0',24567));s.listen(12);s.settimeout(.2)
print('READY',flush=True);end=time.monotonic()+150
while time.monotonic()<end and not stop.is_set():
 try:c,a=s.accept()
 except socket.timeout:continue
 t=threading.Thread(target=client,args=(c,a[0]=='207.57.124.243'),daemon=True);threads.append(t);t.start()
s.close()
for t in threads:t.join(3)
print(json.dumps({'echoed_bytes_per_connection':counts}),flush=True)
if directory:directory.cleanup()
'''

def flow(native,rate,token,interface,address,tls=False,seconds=8):
    s=socket.socket();s.settimeout(5)
    if native:s.bind((address,0));s.setsockopt(socket.IPPROTO_IP,31,struct.pack('!I',interface))
    s.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
    started=time.monotonic();s.connect(('207.57.124.243',24567))
    # Diagnostic ephemeral certificate only; this is not the product's TLS policy.
    if tls:s=ssl._create_unverified_context().wrap_socket(s,server_hostname='bank-coop.test')
    connect_ms=(time.monotonic()-started)*1000
    s.setblocking(False);sent={};received=set();latencies=[];incoming=b'';outgoing=b'';serial=0
    start=time.monotonic();due=start
    try:
        while time.monotonic()<start+seconds+3:
            now=time.monotonic()
            if now>=due and now<start+seconds:
                serial+=1;outgoing+=token+struct.pack('!I',serial)+secrets.token_bytes(880);sent[serial]=now;due=now+1/rate
            if outgoing:
                try:outgoing=outgoing[s.send(outgoing):]
                except (BlockingIOError,ssl.SSLWantWriteError,ssl.SSLWantReadError):pass
            try:
                chunk=s.recv(65536)
                if not chunk:break
                incoming+=chunk
            except (BlockingIOError,ssl.SSLWantWriteError,ssl.SSLWantReadError):pass
            while len(incoming)>=900:
                data,incoming=incoming[:900],incoming[900:]
                assert data.startswith(token)
                number=struct.unpack('!I',data[16:20])[0];assert number in sent
                received.add(number);latencies.append((time.monotonic()-sent[number])*1000)
            time.sleep(.001)
        return {'connect_ms':connect_ms,'sent':len(sent),'echoed':len(received),'unsent_bytes':len(outgoing),'rtt_ms':dist(latencies)}
    finally:s.close()

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',choices=['bank'],required=True)
    p.add_argument('--interface',required=True,type=int);p.add_argument('--address',required=True)
    p.add_argument('--rates',nargs='+',type=int,default=[10,30,100]);p.add_argument('--tls',action='store_true');args=p.parse_args()
    status=query('207.57.124.243',timeout=3);assert status and status['occupied']==0,status
    folder=ROOT/'logs/network'/('bank-tcp-path-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True);print(folder,flush=True)
    token=secrets.token_bytes(16);process=None;report={'cases':[],'failure':None,'tls':args.tls}
    ssh('sudo -n systemctl stop bank-coop.service')
    try:
        process=subprocess.Popen(SSH+['python3 -u -c '+shlex.quote(SERVER)+' '+token.hex()+' '+('tls' if args.tls else 'plain')],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=HIDDEN)
        assert process.stdout.readline().strip()=='READY'
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            for native in [False,True]:
                for rate in args.rates:
                    futures=[pool.submit(flow,native,rate,token,args.interface,args.address,args.tls) for _ in range(4)]
                    row={'physical_interface':native,'rate_per_peer':rate,'bytes_per_message':900,'peers':[f.result() for f in futures]}
                    report['cases'].append(row);print(json.dumps(row),flush=True)
    except BaseException as exc:report['failure']=repr(exc);raise
    finally:
        if process:
            try:
                with socket.create_connection(('207.57.124.243',24567),timeout=5) as stop:
                    if args.tls:stop=ssl._create_unverified_context().wrap_socket(stop,server_hostname='bank-coop.test')
                    stop.sendall(token+b'STOP');stop.close()
            except OSError:pass
            try:
                output,error=process.communicate(timeout=55);report['server']=output;report['server_errors']=error
            except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
        report['service']=ssh('sudo -n systemctl start bank-coop.service; systemctl is-active bank-coop.service')
        (folder/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')

if __name__=='__main__':main()
