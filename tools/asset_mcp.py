"""High-level MCP surface for asset queries and bounded background jobs."""
from asset_library import search, inspect_asset
from scene_pipeline import validate_scene
from assets import OPERATIONS


def tool(name, description, properties, required=()):
    return {"name":name,"description":description,"inputSchema":{"type":"object","properties":properties,"required":list(required),"additionalProperties":False}}


ID={"type":"string"}
TOOLS=[
    tool('asset_search','Search the local asset catalogue by words, kind and readiness.',{'query':ID,'kind':{'type':'string','enum':['model','texture']},'status':ID,'limit':{'type':'integer','minimum':1,'maximum':100}}),
    tool('asset_inspect','Read provenance, explicit conventions, measured geometry and dependency issues.',{'asset_id':ID},['asset_id']),
    tool('asset_ingest','Snapshot a local GLB/glTF/FBX/image package. Returns a job ID; never edits source files.',{'path':ID,'asset_id':ID,'title':ID,'tags':{'type':'array','items':ID},'source_note':ID,'usage':ID},['path','asset_id']),
    tool('asset_prepare','Prepare an immutable version using explicit scale/rotation and optional texture-role asset IDs. Returns a job ID.',{'asset_id':ID,'unit_scale':{'type':'number'},'yaw_degrees':{'type':'number'},'textures':{'type':'object','additionalProperties':ID}},['asset_id']),
    tool('asset_preview','Render actual Godot model views or texture channels. Returns a job ID.',{'asset_id':ID,'lighting':{'type':'string','enum':['neutral','dark','raking']}},['asset_id']),
    tool('scene_build','Resolve a room recipe, validate footprints/anchors/door sweep/reachability, then pack a playable Godot scene. Returns a job ID.',{'recipe':{'type':'object'}},['recipe']),
    tool('scene_validate','Read-only scene validation. Supply recipe OR an existing scene_id. A conservative route is not proof of gameplay.',{'recipe':{'type':'object'},'scene_id':ID}),
    tool('scene_preview','Render a built room using overview, reverse and player cameras. Returns a job ID.',{'scene_id':ID},['scene_id']),
    tool('asset_job_status','Read progress/results of an asset job; completed previews include a rendered image.',{'job_id':ID},['job_id']),
    tool('asset_job_cancel','Request cancellation of a queued/running asset job. Keeps logs and partial evidence.',{'job_id':ID},['job_id'])
]


def dispatch(jobs,name,args):
    if name=='asset_search':return search(**args)
    if name=='asset_inspect':return inspect_asset(**args)
    if name=='scene_validate':return validate_scene(**args)
    if name=='asset_job_status':return jobs.status(**args)
    if name=='asset_job_cancel':return jobs.cancel(**args)
    return jobs.submit(name,OPERATIONS[name],args)
