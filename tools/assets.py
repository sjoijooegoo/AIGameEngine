"""Asset pipeline CLI. Mutation/render commands share the same implementation as MCP jobs."""
import argparse
import json
from pathlib import Path

from lab import ROOT, atomic_json
from asset_jobs import Job
from asset_library import ingest, prepare, preview_asset, search, inspect_asset
from scene_pipeline import build_scene, validate_scene, preview_scene

OPERATIONS={'asset_ingest':ingest,'asset_prepare':prepare,'asset_preview':preview_asset,'scene_build':build_scene,'scene_preview':preview_scene}


def demo(job=None):
    job=job or Job('demo')
    for name in ('counter','chair','door','terminal'):
        ingest(str(ROOT/'tests/asset_fixtures'/(name+'.glb')),'demo.'+name,title=name,tags=['bank',name],source_note='Original repository-generated fixture',usage='project_owned',job=job)
        prepare('demo.'+name,job=job)
    ingest(str(ROOT/'tests/asset_fixtures/wood.png'),'demo.wood',tags=['wood','albedo'],source_note='Original fixture',usage='project_owned',job=job)
    prepare('demo.wood',job=job)
    recipe=json.loads((ROOT/'recipes/bank_room.json').read_text())
    return build_scene(recipe,job=job)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation',choices=[*OPERATIONS,'asset_search','asset_inspect','scene_validate','demo'])
    parser.add_argument('--args',default='{}')
    parser.add_argument('--args-file',type=Path)
    args=parser.parse_args()
    payload=json.loads(args.args_file.read_text(encoding='utf-8')) if args.args_file else json.loads(args.args)
    if args.operation in ('asset_search','asset_inspect','scene_validate'):
        result={'asset_search':search,'asset_inspect':inspect_asset,'scene_validate':validate_scene}[args.operation](**payload)
    else:
        job=Job(args.operation)
        try:
            job.state['status']='running';job.persist()
            result=(demo if args.operation=='demo' else OPERATIONS[args.operation])(job=job,**payload)
            job.state.update(status='completed',result=result)
        except Exception as error:
            job.state.update(status='failed',error=str(error));job.persist();raise
        job.persist()
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
