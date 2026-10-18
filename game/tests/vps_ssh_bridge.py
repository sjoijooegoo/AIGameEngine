"""Private stdin/stdout bridge launched through authenticated SSH, never a socket.

Only a bounded local Godot test session is controlled. Sampling writes after its
window. Production exports do not contain this file or its GDScript drivers.
"""
import argparse
import base64
import gzip
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--engine',required=True);p.add_argument('--pack',required=True)
    p.add_argument('--overlay',required=True);p.add_argument('--drivers',type=Path,required=True)
    p.add_argument('--session',type=Path,required=True);p.add_argument('--players',type=int,choices=[2,4],required=True)
    p.add_argument('--port',type=int,default=24567);p.add_argument('--candidate-overlay')
    args=p.parse_args();args.session.mkdir(parents=True,exist_ok=False)
    log=(args.session/'engine.log').open('w')
    command=[args.engine,'--headless','--main-pack',args.pack,'--script',str(args.drivers/'vps_performance.gd'),
             '--','--test-session='+str(args.session),'--validation-overlay='+args.overlay,
             '--performance-benchmark','--coop','--server','--prefer-tcp',f'--port={args.port}',f'--max-players={args.players}']
    if args.candidate_overlay:command.append('--candidate-overlay='+args.candidate_overlay)
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    serial=0;sampler=None
    def wait_file(path,timeout=30):
        deadline=time.monotonic()+timeout
        while not path.exists():
            if process.poll() is not None:raise RuntimeError('Godot exited: '+(args.session/'engine.log').read_text()[-5000:])
            if time.monotonic()>deadline:raise TimeoutError(str(path))
            time.sleep(.005)
    def call(command,**values):
        nonlocal serial
        serial+=1;response=args.session/'response.json';response.unlink(missing_ok=True)
        request={'id':serial,'command':command,**values};temp=args.session/'request.tmp'
        temp.write_text(json.dumps(request));temp.replace(args.session/'request.json')
        wait_file(response);result=json.loads(response.read_text());assert result['id']==serial
        with (args.session/'trace.jsonl').open('a') as f:f.write(json.dumps({'request':request,'response':result})+'\n')
        if 'error' in result['result']:raise RuntimeError(result)
        return result['result']
    def emit(value):print(json.dumps(value,separators=(',',':')),flush=True)
    try:
        wait_file(args.session/'validation.json',180)
        emit({'ready':True,'pid':process.pid,'time':time.time(),'validation':json.loads((args.session/'validation.json').read_text()),
              'cpus':os.cpu_count(),'meminfo':Path('/proc/meminfo').read_text(),'cpuinfo':Path('/proc/cpuinfo').read_text()})
        for line in sys.stdin:
            req=json.loads(line);op=req.pop('op')
            try:
                if op=='call':result=call(**req)
                elif op=='clock':result={'time':time.time()}
                elif op=='sample':
                    assert sampler is None or sampler.poll() is not None
                    (args.session/'os.json').unlink(missing_ok=True);(args.session/'result.json').unlink(missing_ok=True)
                    sampler=subprocess.Popen([sys.executable,str(args.drivers/'wsl_proc_sampler.py'),'--pid',str(process.pid),
                        '--start',str(req['start']),'--seconds',str(req['seconds']),'--output',str(args.session/'os.json')],stdout=log,stderr=subprocess.STDOUT)
                    result={}
                elif op=='collect':
                    wait_file(args.session/'result.json',45);sampler.wait(timeout=20);assert sampler.returncode==0
                    payload={'raw':json.loads((args.session/'result.json').read_text()),'os':json.loads((args.session/'os.json').read_text())}
                    result={'gzip':base64.b64encode(gzip.compress(json.dumps(payload,separators=(',',':')).encode())).decode()}
                elif op=='quit':
                    call('quit');process.wait(timeout=15);emit({'result':{'log':(args.session/'engine.log').read_text()}});break
                else:raise ValueError('Unsupported SSH bridge operation')
                emit({'result':result})
            except Exception as exc:emit({'error':repr(exc)})
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=15)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        if sampler and sampler.poll() is None:sampler.terminate();sampler.wait(timeout=5)
        log.close()


if __name__=='__main__':main()
