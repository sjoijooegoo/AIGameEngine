"""Own one bounded transient candidate unit independently of SSH lifetime."""
import argparse,json,pathlib,socket,subprocess,time,uuid

def query():
    nonce=uuid.uuid4().hex
    with socket.socket(type=socket.SOCK_DGRAM) as sock:
        sock.settimeout(2)
        sock.sendto(json.dumps({'magic':'BANK_STATUS_1','query':True,'nonce':nonce,'padding':' '*192}).encode(),('127.0.0.1',24568))
        try:
            row=json.loads(sock.recv(512))
            return row if row.get('nonce')==nonce else None
        except (OSError,ValueError):return None

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['start','stop'])
    p.add_argument('--binary',required=True,type=pathlib.Path);p.add_argument('--session',required=True,type=pathlib.Path);args=p.parse_args()
    assert args.binary.is_file() and args.session.parent==pathlib.Path('/home/dev/bank-coop-validation/sessions')
    assert args.session.name.startswith('bank-vps-candidate-')
    unit=args.session.name+'.service'
    if args.action=='start':
        assert not args.session.exists();row=query();assert row and row['occupied']==0
        args.session.mkdir()
        # systemd owns lifetime independently of SSH. Conflicts+After stop the
        # original before binding. Nonblocking restore avoids a stop-job deadlock.
        command=['sudo','-n','systemd-run','--quiet','--collect','--unit='+unit,
            '--property=Type=exec','--property=User=dev','--property=Group=dev',
            '--property=RuntimeMaxSec=1200','--property=TimeoutStopSec=20',
            '--property=Conflicts=bank-coop.service','--property=After=bank-coop.service',
            '--property=ExecStopPost=+/usr/bin/systemctl --no-block start bank-coop.service',
            '--property=StandardOutput=append:'+str(args.session/'engine.log'),
            '--property=StandardError=inherit',str(args.binary),'--headless','--max-fps','60',
            '--','--server','--port=24567','--max-players=4','--prefer-tcp']
        result=subprocess.run(command,capture_output=True,text=True)
        record={'unit':unit,'command':command,'returncode':result.returncode,'stderr':result.stderr}
        (args.session/'launch.json').write_text(json.dumps(record,indent=2))
        print(json.dumps(record),flush=True)
        if result.returncode:raise SystemExit(result.returncode)
    else:
        result=subprocess.run(['sudo','-n','systemctl','stop',unit],capture_output=True,text=True)
        subprocess.run(['sudo','-n','systemctl','start','bank-coop.service'],check=True)
        row=None
        for _ in range(30):
            row=query()
            if row and row['occupied']==0:break
            time.sleep(1)
        active=subprocess.run(['systemctl','is-active','bank-coop.service'],capture_output=True,text=True)
        print(json.dumps({'unit':unit,'stop_returncode':result.returncode,'service':active.stdout.strip(),
            'discovery':row,'log':(args.session/'engine.log').read_text(errors='replace') if (args.session/'engine.log').exists() else ''}),flush=True)

if __name__=='__main__':main()
