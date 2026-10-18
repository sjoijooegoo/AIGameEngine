"""Delta-copy a verified Linux package to an isolated VPS candidate directory.

Uses WSL rsync + Windows OpenSSH (existing keys/host checks). Never changes the
production service or current link. Verify the complete remote binary hash.
"""
import argparse,hashlib,json,re,shlex,subprocess
from pathlib import Path
from game.tools.coop import ROOT,HIDDEN
from game.tests.benchmark_vps_coop import SSH,ssh

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',required=True,choices=['bank']);p.add_argument('--package',type=Path,required=True);p.add_argument('--name',required=True);args=p.parse_args()
    assert re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}',args.name)
    package=args.package.resolve();build=json.loads((package/'build.json').read_text(encoding='utf8'))
    assert build['platform']=='linux' and build['wire_protocol']==4
    binary=package/build['executable'];assert binary.parent==package and hashlib.sha256(binary.read_bytes()).hexdigest()==build['sha256']
    remote='/home/dev/bank-coop-validation/candidates/'+args.name
    setup="import pathlib,shutil;dest=pathlib.Path("+repr(remote)+");dest.mkdir(parents=True,exist_ok=False);shutil.copyfile('/opt/bank-coop/current/bank-coop-server.x86_64',dest/'bank-coop-server.x86_64')"
    ssh('python3 -c '+shlex.quote(setup))
    options=[]
    for index,argument in enumerate(SSH[:-1]):
        if argument=='-o':options+=['-o',SSH[index+1]]
    shell=shlex.join(['/mnt/c/Windows/System32/OpenSSH/ssh.exe',*options,'-p','5579'])
    mounted='/mnt/'+binary.drive[0].lower()+binary.as_posix()[2:]
    command=['wsl','-d','Ubuntu','--','rsync','-rt','--inplace','--no-whole-file','--stats','-e',shell,mounted,'dev@207.57.124.243:'+remote+'/bank-coop-server.x86_64']
    result=subprocess.run(command,capture_output=True,text=True,timeout=1200,creationflags=HIDDEN)
    (package/'candidate-transfer.log').write_text(result.stdout+'\n'+result.stderr,encoding='utf8');print(result.stdout,flush=True);result.check_returncode()
    subprocess.run(['scp',*options,'-P','5579',str(package/'build.json'),str(package/'bank-coop.service'),'dev@207.57.124.243:'+remote+'/'],check=True,timeout=90,creationflags=HIDDEN)
    check="import pathlib,hashlib,json;d=pathlib.Path("+repr(remote)+");b=json.loads((d/'build.json').read_text());p=d/b['executable'];h=hashlib.sha256(p.read_bytes()).hexdigest();assert h==b['sha256'];p.chmod(0o755);print(json.dumps({'binary':str(p),'sha256':h}))"
    verified=json.loads(ssh('python3 -c '+shlex.quote(check)))
    (package/'candidate-transfer.json').write_text(json.dumps(verified,indent=2),encoding='utf8');print(json.dumps(verified),flush=True)

if __name__=='__main__':main()
