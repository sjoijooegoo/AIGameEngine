"""Current bank calculation contracts; reference actor is extracted without changing the checkout."""
import argparse, datetime, hashlib, json, subprocess
from pathlib import Path
from game.tools.coop import ROOT, HIDDEN, godot

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project',required=True,choices=['bank'])
    p.add_argument('--reference',default='190f416')
    args=p.parse_args()
    folder=ROOT/'logs/sessions'/('bank-coop-optimization-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    reference=folder/'reference';reference.mkdir(parents=True)
    revision=subprocess.check_output(['git','rev-parse',args.reference],cwd=ROOT,text=True).strip()
    hashes={}
    for name in ['infected.gd','infected_native_motion.gd','infected_ragdoll.gd','infected_reactions.gd']:
        source=subprocess.check_output(['git','show',f'{revision}:game/runtime/scripts/{name}'],cwd=ROOT)
        hashes[name]=hashlib.sha256(source).hexdigest()
        if name=='infected.gd':
            for dep in ['infected_native_motion.gd','infected_ragdoll.gd','infected_reactions.gd']:
                source=source.replace(('res://scripts/'+dep).encode(),(reference/dep).as_posix().encode())
        (reference/name).write_bytes(source)
    exe=godot();direct=exe.with_name(exe.name.replace('_console.exe','.exe'))
    if direct.is_file():exe=direct
    report={'reference_revision':revision,'reference_hashes':hashes,'checks':[],'scope':'Math/replication contracts only; real input combat and visual sequences run separately.'}
    print(folder,flush=True)
    try:
        for script,marker in [('verify_coop_pose_equivalence','BANK_POSE_EQUIVALENCE_PASS'),('verify_crowd_cache','CROWD_CACHE_PASS'),('verify_snapshot_delta','BANK_DELTA_PASS'),('verify_world_presentation_work','BANK_PRESENTATION_WORK_PASS'),('verify_network_components','BANK_NETWORK_COMPONENTS_PASS')]:
            command=[str(exe),'--headless','--path',str(ROOT/'game/runtime'),'--script',str(ROOT/f'game/tests/{script}.gd')]
            if script=='verify_coop_pose_equivalence':command+=['--','--reference-dir='+reference.as_posix()]
            log=folder/(script+'.log')
            with log.open('w',encoding='utf8') as stream:
                result=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=60,creationflags=HIDDEN)
            output=log.read_text(encoding='utf8')
            passed=result.returncode==0 and marker in output and 'SCRIPT ERROR' not in output and '\nERROR:' not in output
            report['checks'].append({'name':script,'status':'pass' if passed else 'fail','log':log.name,'output':[line for line in output.splitlines() if marker in line]})
            print(script,passed,flush=True)
            assert passed,output[-3000:]
        report['passed']=True
    finally:
        (folder/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')

if __name__=='__main__':main()
