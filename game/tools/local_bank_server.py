"""Manage the local WSL bank service and a loopback-only Windows UDP relay.

Only the named bank-coop-local systemd unit and this tool's startup shortcut are
managed. NAT WSL does not forward localhost UDP, so each client gets its own
upstream socket; ENet identities are never collapsed into one address.
"""
from __future__ import annotations
import argparse,datetime,hashlib,json,os,selectors,shlex,socket,subprocess,sys,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
STATE=ROOT/'logs/local-bank-server'
UNIT='bank-coop-local.service'
HIDDEN=0x08000000 if os.name=='nt' else 0
MAGIC='BANK_STATUS_1'

def write(path,value):
    temp=path.with_suffix('.tmp');temp.write_text(json.dumps(value,indent=2),encoding='utf8');temp.replace(path)

def wsl(distro,*args,root=False,check=True):
    command=['wsl','-d',distro]+(['-u','root'] if root else [])+['--',*args]
    return subprocess.run(command,capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=HIDDEN,timeout=30,check=check)

def mounted(path):
    path=Path(path).resolve();return '/mnt/'+path.drive[0].lower()+path.as_posix()[2:]

def query_port(port):return port+1 if port<65535 else 65534

def query(host='127.0.0.1',port=24567,timeout=.7):
    nonce=uuid.uuid4().hex
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(json.dumps({'magic':MAGIC,'query':True,'nonce':nonce,'padding':' '*192}).encode(),(host,query_port(port)))
        try:
            data,_=sock.recvfrom(512);value=json.loads(data)
            if value.get('magic')==MAGIC and value.get('nonce')==nonce:return value
        except (TimeoutError,OSError,ValueError):pass
    return None

def config():return json.loads((STATE/'config.json').read_text(encoding='utf8'))

def install(package,distro,autostart):
    binary=(package/'bank-coop-server.x86_64').resolve();assert binary.is_file(),binary
    digest=hashlib.sha256(binary.read_bytes()).hexdigest()
    user=wsl(distro,'whoami').stdout.strip();home=wsl(distro,'sh','-c','printf %s "$HOME"').stdout.strip()
    destination=f'{home}/.local/share/aigameengine-bank/{digest[:16]}'
    command=f'mkdir -p {shlex.quote(destination)} && cp {shlex.quote(mounted(binary))} {shlex.quote(destination+"/bank-server")} && chmod 755 {shlex.quote(destination+"/bank-server")}'
    wsl(distro,'sh','-c',command)
    unit=f'''# AIGameEngine managed local development service
[Unit]
Description=AIGameEngine local bank co-op server
After=network.target
[Service]
Type=simple
User={user}
WorkingDirectory={destination}
ExecStart={destination}/bank-server --headless --max-fps 60 -- --server --port=24567 --max-players=4 "--server-name=Local WSL Bank"
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
'''
    existing=wsl(distro,'cat','/etc/systemd/system/'+UNIT,root=True,check=False)
    if existing.returncode==0 and 'AIGameEngine managed' not in existing.stdout:raise RuntimeError('The service name belongs to another configuration')
    path=STATE/UNIT;path.write_text(unit,encoding='utf8',newline='\n')
    wsl(distro,'install','-m','644',mounted(path),'/etc/systemd/system/'+UNIT,root=True)
    wsl(distro,'systemctl','daemon-reload',root=True);wsl(distro,'systemctl','enable',UNIT,root=True)
    write(STATE/'config.json',{'distro':distro,'port':24567,'sha256':digest,'linux_executable':destination+'/bank-server','package':str(package.resolve())})
    if autostart:
        startup=Path(os.environ['APPDATA'])/'Microsoft/Windows/Start Menu/Programs/Startup/AIGameEngine Bank Local Server.lnk'
        pythonw=Path(sys.executable).with_name('pythonw.exe');assert pythonw.exists()
        # Literal paths are quoted as PowerShell strings, never interpolated as code.
        quote=lambda s:"'"+str(s).replace("'","''")+"'"
        script="$ws=New-Object -ComObject WScript.Shell\n$s=$ws.CreateShortcut("+quote(startup)+")\n$s.TargetPath="+quote(pythonw)+"\n$s.Arguments='-m game.tools.local_bank_server run'\n$s.WorkingDirectory="+quote(ROOT)+"\n$s.WindowStyle=7\n$s.Description='Local WSL bank server and localhost UDP relay'\n$s.Save()\n"
        ps=STATE/'install-startup.ps1';ps.write_text(script,encoding='utf-8-sig')
        subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ps)],check=True,creationflags=HIDDEN)
    wsl(distro,'systemctl','restart',UNIT,root=True)
    start()

def stop_relay():
    path=STATE/'relay.json'
    if not path.exists():return
    state=json.loads(path.read_text());write(STATE/'stop.json',{'token':state['token']})
    deadline=time.monotonic()+5
    while path.exists() and time.monotonic()<deadline:time.sleep(.1)

def start():
    cfg=config();wsl(cfg['distro'],'systemctl','start',UNIT,root=True)
    if query(port=cfg['port']):return
    stop_relay()
    log=(STATE/'relay.log').open('a',encoding='utf8')
    subprocess.Popen([str(Path(sys.executable).with_name('pythonw.exe')),'-m','game.tools.local_bank_server','run'],cwd=ROOT,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,creationflags=HIDDEN|0x00000200)
    log.close()
    for _ in range(120):
        result=query(port=cfg['port'])
        if result:print(json.dumps(result));return
        time.sleep(.3)
    raise RuntimeError('Local relay did not receive a WSL server response; inspect logs/local-bank-server')

def run():
    cfg=config();distro=cfg['distro'];port=cfg['port'];token=uuid.uuid4().hex
    selector=selectors.DefaultSelector();listeners={};channels={};host='';next_host=0;keeper=None
    try:
        # Binding first makes repeated startup shortcuts harmless.
        for value in [port,query_port(port)]:
            sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);sock.bind(('127.0.0.1',value));sock.setblocking(False)
            listeners[value]=sock;selector.register(sock,selectors.EVENT_READ,('local',value))
    except OSError:
        for sock in listeners.values():sock.close()
        selector.close();return
    wsl(distro,'systemctl','start',UNIT,root=True)
    # systemd services alone do not keep a WSL VM alive. An open, pipe-owned
    # foreground process prevents idle VM shutdown; EOF on relay exit ends it.
    keeper=subprocess.Popen(['wsl','-d',distro,'--','sh','-c','cat >/dev/null'],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=HIDDEN)
    write(STATE/'relay.json',{'pid':os.getpid(),'token':token,'ports':list(listeners),'started':datetime.datetime.now().isoformat()})
    try:
        while True:
            stop=STATE/'stop.json'
            if stop.exists() and json.loads(stop.read_text()).get('token')==token:break
            now=time.monotonic()
            if now>=next_host:
                if keeper.poll() is not None:
                    keeper=subprocess.Popen(['wsl','-d',distro,'--','sh','-c','cat >/dev/null'],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=HIDDEN)
                    wsl(distro,'systemctl','start',UNIT,root=True)
                result=wsl(distro,'hostname','-I',check=False)
                addresses=result.stdout.split();address=next((a for a in addresses if ':' not in a),'')
                if address and address!=host:
                    for item in channels.values():selector.unregister(item['socket']);item['socket'].close()
                    channels.clear();host=address
                next_host=now+30
            for key,_ in selector.select(.2):
                kind,value=key.data
                if kind=='local':
                    try:data,client=key.fileobj.recvfrom(65535)
                    except OSError:continue
                    if not host:continue
                    channel_id=(value,client)
                    if channel_id not in channels:
                        if len(channels)>=64:continue
                        upstream=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);upstream.connect((host,value));upstream.setblocking(False)
                        channels[channel_id]={'socket':upstream,'last':now};selector.register(upstream,selectors.EVENT_READ,('remote',channel_id))
                    item=channels[channel_id];item['last']=now
                    try:item['socket'].send(data)
                    except OSError:pass
                else:
                    try:data=key.fileobj.recv(65535);listeners[value[0]].sendto(data,value[1])
                    except OSError:pass
            for channel_id,item in list(channels.items()):
                if now-item['last']>(12 if channel_id[0]==query_port(port) else 120):
                    selector.unregister(item['socket']);item['socket'].close();del channels[channel_id]
    finally:
        if keeper:
            keeper.stdin.close()
            try:keeper.wait(timeout=5)
            except subprocess.TimeoutExpired:keeper.terminate()
        for item in channels.values():item['socket'].close()
        for sock in listeners.values():sock.close()
        selector.close()
        path=STATE/'relay.json'
        if path.exists() and json.loads(path.read_text()).get('token')==token:path.unlink()

def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    setup=sub.add_parser('install');setup.add_argument('--package',type=Path,required=True);setup.add_argument('--distro',default='Ubuntu');setup.add_argument('--autostart',action='store_true')
    for name in ['start','stop','status','run']:sub.add_parser(name)
    args=parser.parse_args();STATE.mkdir(parents=True,exist_ok=True)
    if sys.stdout is None:
        sys.stdout=(STATE/'relay.log').open('a',encoding='utf8');sys.stderr=sys.stdout
    if args.command=='install':install(args.package,args.distro,args.autostart)
    elif args.command=='start':start()
    elif args.command=='run':run()
    elif args.command=='stop':stop_relay();wsl(config()['distro'],'systemctl','stop',UNIT,root=True)
    else:
        cfg=config();print(json.dumps({'service':wsl(cfg['distro'],'systemctl','is-active',UNIT,check=False).stdout.strip(),'localhost':query(port=cfg['port']),'config':cfg},indent=2))

if __name__=='__main__':main()
