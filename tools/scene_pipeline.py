"""Resolve explicit asset anchors and validate conservative space budgets before packing a scene."""
from __future__ import annotations
from collections import deque
import json
import math
from pathlib import Path

from asset_jobs import Job
from asset_library import inspect_asset, identifier, canonical, engine, fs_path, res_path, digest, MUTATION_LOCK
from lab import ROOT, atomic_json, godot_path


def numbers(value, count, label):
    if not isinstance(value, list) or len(value) != count or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in value):
        raise ValueError(label + " must be a finite numeric array of length " + str(count))
    return list(map(float, value))


def rotate(x, z, yaw):
    a = math.radians(yaw)
    return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)


def rectangle(entity, expansion=0):
    width, _, depth = entity["size"]
    x, _, z = entity["position"]
    return [(x + dx, z + dz) for dx, dz in (rotate(a * (width/2+expansion), b*(depth/2+expansion), entity["yaw"]) for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)])]


def overlap(a, b):
    for polygon in (a, b):
        for p, q in zip(polygon, polygon[1:] + polygon[:1]):
            axis = (p[1]-q[1], q[0]-p[0])
            aa = [x*axis[0] + z*axis[1] for x,z in a]
            bb = [x*axis[0] + z*axis[1] for x,z in b]
            if max(aa) <= min(bb) + 1e-6 or max(bb) <= min(aa) + 1e-6:
                return False
    return True


def inside_point(x, z, polygon):
    signs=[]
    for p,q in zip(polygon,polygon[1:]+polygon[:1]):
        signs.append((q[0]-p[0])*(z-p[1])-(q[1]-p[1])*(x-p[0]))
    return all(v >= -1e-7 for v in signs) or all(v <= 1e-7 for v in signs)


def plan_scene(recipe):
    identifier(recipe["id"])
    room = numbers(recipe["room"],3,"room")
    if not all(2 <= room[i] <= 40 for i in (0,2)) or not 2 <= room[1] <= 10:
        raise ValueError("Room outside supported 2..40m footprint / 2..10m height")
    spawn = numbers(recipe.get("spawn", [0,0,room[2]/2-1]),3,"spawn")
    exit_point = numbers(recipe.get("exit", [0,0,-room[2]/2-1]),3,"exit")
    if abs(spawn[1]) > 0.001 or abs(exit_point[1]) > 0.001:
        raise ValueError("Single-floor rooms require spawn and exit at y=0")
    if abs(spawn[0]) >= room[0]/2 or abs(spawn[2]) >= room[2]/2 or not -room[2]/2-1.5 <= exit_point[2] < -room[2]/2-0.4:
        raise ValueError("Spawn must be inside and exit just outside the north wall")
    entities = recipe.get("entities", [])
    if not 1 <= len(entities) <= 100:
        raise ValueError("Expected 1..100 scene entities")
    source = {identifier(e["id"]): e for e in entities}
    if len(source) != len(entities):
        raise ValueError("Duplicate entity ID")
    resolved = {}

    def resolve(entity_id, stack):
        if entity_id in resolved:
            return resolved[entity_id]
        if entity_id in stack:
            raise ValueError("Placement dependency cycle")
        if entity_id not in source:
            raise ValueError("Unknown support entity: " + entity_id)
        entity = source[entity_id]
        asset = inspect_asset(entity["asset"])
        if asset["kind"] != "model" or "prepared" not in asset:
            raise ValueError("Scene entity requires a prepared model")
        prepared = asset.get("preparations",{}).get(entity["revision"]) if entity.get("revision") else asset["prepared"]
        if not prepared or not fs_path(prepared["resource"]).is_file():
            raise ValueError("Requested preparation revision is not available")
        folder = fs_path(prepared["resource"]).parent
        if any(not (folder/name).is_file() or digest(folder/name) != sha for name,sha in prepared["artifact_hashes"].items()):
            raise ValueError("Prepared asset modified; run asset_prepare again")
        size = prepared["measured"]["size_m"]
        yaw = float(entity.get("yaw", 0))
        if not math.isfinite(yaw):
            raise ValueError("Non-finite yaw")
        placement = entity.get("placement", {})
        pos = numbers(entity.get("position",[0,0,0]),3,"position")
        if "on" in placement:
            parent = resolve(placement["on"],stack|{entity_id})
            if placement.get("anchor","top") != "top":
                raise ValueError("Supported parent anchor is top")
            offset=numbers(placement.get("offset",[0,0,0]),3,"offset")
            dx,dz=rotate(offset[0],offset[2],parent["yaw"])
            pos=[parent["position"][0]+dx,parent["position"][1]+parent["size"][1]+offset[1],parent["position"][2]+dz]
            yaw += parent["yaw"]
        if "against" in placement:
            wall = placement["against"]
            margin=float(placement.get("margin",0.1))
            if not math.isfinite(margin) or margin < 0:
                raise ValueError("Invalid wall margin")
            ex=abs(math.cos(math.radians(yaw)))*size[0]/2+abs(math.sin(math.radians(yaw)))*size[2]/2
            ez=abs(math.sin(math.radians(yaw)))*size[0]/2+abs(math.cos(math.radians(yaw)))*size[2]/2
            if wall=="north": pos[2]=-room[2]/2+ez+margin
            elif wall=="south": pos[2]=room[2]/2-ez-margin
            elif wall=="west": pos[0]=-room[0]/2+ex+margin
            elif wall=="east": pos[0]=room[0]/2-ex-margin
            else: raise ValueError("Unknown wall")
        behavior=entity.get("behavior","")
        if behavior not in ("","door"):
            raise ValueError("Only static props and an interactive door are supported")
        if behavior=="door":
            if yaw % 360 != 0:
                raise ValueError("MVP portal supports north-wall doors with yaw 0")
            pos[2]=-room[2]/2
            pos[1]=0
        value={"id":entity_id,"asset":asset["id"],"revision":prepared["key"],"scene":prepared["resource"],"size":size,"position":pos,"yaw":yaw,"behavior":behavior,"placement":placement}
        resolved[entity_id]=value
        return value
    for entity_id in source:
        resolve(entity_id,set())
    doors=[e for e in resolved.values() if e["behavior"]=="door"]
    if len(doors)!=1:
        raise ValueError("MVP rooms require exactly one north-wall door")
    door=doors[0]
    return {"version":1,"id":recipe["id"],"room":room,"spawn":spawn,"exit":exit_point,"entities":sorted(resolved.values(),key=lambda e:e["id"]),"portal":{"x":door["position"][0],"width":door["size"][0]+0.08},"player_radius":0.3,"source_recipe":recipe}


def validate_plan(plan):
    issues=[]
    room=plan["room"]
    entities=plan["entities"]
    for entity in entities:
        x,y,z=entity["position"]
        polygon=rectangle(entity)
        if y < -0.001 or y+entity["size"][1]>room[1]+0.001:
            issues.append({"code":"vertical_bounds","entity":entity["id"]})
        if entity["behavior"] != "door" and any(abs(px)>room[0]/2-0.075+1e-4 or abs(pz)>room[2]/2-0.075+1e-4 for px,pz in polygon):
            issues.append({"code":"wall_intersection","entity":entity["id"]})
        if y>0.01 and "on" not in entity["placement"]:
            issues.append({"code":"unsupported_floating","entity":entity["id"]})
        if "on" in entity["placement"]:
            parent=next(e for e in entities if e["id"]==entity["placement"]["on"])
            if abs(y-parent["position"][1]-parent["size"][1])>0.005:
                issues.append({"code":"support_height_mismatch","entity":entity["id"]})
            if not all(inside_point(px,pz,rectangle(parent)) for px,pz in polygon):
                issues.append({"code":"outside_support_surface","entity":entity["id"]})
    for i,a in enumerate(entities):
        for b in entities[i+1:]:
            vertical=min(a["position"][1]+a["size"][1],b["position"][1]+b["size"][1])-max(a["position"][1],b["position"][1])
            if vertical>0.005 and overlap(rectangle(a),rectangle(b)):
                issues.append({"code":"asset_overlap","entities":[a["id"],b["id"]]})
    door=next(e for e in entities if e["behavior"]=="door")
    dx,_,dz=door["position"]
    width=door["size"][0]
    sweep=[(dx-width/2,dz),(dx+width/2,dz),(dx+width/2,dz+width),(dx-width/2,dz+width)]
    for e in entities:
        if e is not door and e["position"][1] < door["size"][1] and overlap(sweep,rectangle(e)):
            issues.append({"code":"door_sweep_blocked","entity":e["id"]})
    if abs(dx)+width/2 >= room[0]/2-0.2:
        issues.append({"code":"portal_outside_wall"})
    route=find_route(plan)
    if not route:
        issues.append({"code":"exit_unreachable_with_door_open"})
    return {"valid":not issues,"issues":issues,"route_with_doors_open":route,"method":"Conservative 2D footprint grid, radius-inflated props; not a navigation-mesh or full 3D proof"}


def find_route(plan):
    room=plan["room"];radius=plan["player_radius"];step=0.2
    xmin=-room[0]/2+radius+0.08; xmax=room[0]/2-radius-0.08
    zmin=-room[2]/2-1.5; zmax=room[2]/2-radius-0.08
    obstacles=[rectangle(e,radius) for e in plan["entities"] if e["behavior"]!="door" and e["position"][1]<1.8]
    portal=plan["portal"]
    def point(cell): return xmin+cell[0]*step,zmin+cell[1]*step
    def cell(pos): return round((pos[0]-xmin)/step),round((pos[2]-zmin)/step)
    def free(c):
        x,z=point(c)
        if x<xmin or x>xmax or z<zmin or z>zmax: return False
        if abs(z+room[2]/2)<radius+0.1 and abs(x-portal["x"])>portal["width"]/2-radius: return False
        return not any(inside_point(x,z,p) for p in obstacles)
    start=cell(plan["spawn"]);end=cell(plan["exit"])
    if not free(start) or not free(end): return []
    queue=deque([start]);parents={start:None}
    while queue:
        c=queue.popleft()
        if c==end:
            path=[]
            while c is not None:
                x,z=point(c);path.append([round(x,3),0,round(z,3)]);c=parents[c]
            return list(reversed(path))
        for nx,nz in ((1,0),(-1,0),(0,1),(0,-1)):
            nxt=(c[0]+nx,c[1]+nz)
            if nxt not in parents and free(nxt):parents[nxt]=c;queue.append(nxt)
    return []


def validate_scene(recipe=None, scene_id=None):
    if recipe is not None:
        plan=plan_scene(recipe)
    else:
        plan=json.loads((ROOT/"game/generated"/identifier(scene_id)/"plan.json").read_text(encoding="utf-8"))
    return {"plan":plan,"validation":validate_plan(plan)}


def build_scene(recipe, job=None):
    job=job or Job("scene_build")
    with MUTATION_LOCK:
        plan=plan_scene(recipe)
        validation=validate_plan(plan)
        atomic_json(job.directory/"validation.json",validation)
        if not validation["valid"]:
            return {"built":False,"validation":validation,"report":str(job.directory/"validation.json")}
        target=ROOT/"game/generated"/identifier(plan["id"])
        target.mkdir(parents=True,exist_ok=True)
        scene=target/"scene.tscn"
        signature=canonical({"plan":plan,"worker":digest(ROOT/'game/asset_pipeline/worker.gd'),"runtime":digest(ROOT/'game/asset_pipeline/scene_runtime.gd')})
        manifest=target/"build.json"
        if manifest.exists():
            old=json.loads(manifest.read_text())
            if old.get("signature")==signature and scene.exists() and digest(scene)==old.get("scene_sha256"):
                return {"built":True,"cache_hit":True,"scene":res_path(scene),"validation":validation}
        temporary=target/"candidate.tscn"
        engine(job,"build",plan=plan,output=res_path(temporary))
        job.check()
        temporary.replace(scene)
        atomic_json(target/"plan.json",plan)
        atomic_json(manifest,{"signature":signature,"scene_sha256":digest(scene)})
        return {"built":True,"cache_hit":False,"scene":res_path(scene),"validation":validation}


def preview_scene(scene_id, job=None):
    from asset_report import preview_report
    job=job or Job("scene_preview")
    resource=res_path(ROOT/"game/generated"/identifier(scene_id)/"scene.tscn")
    if not fs_path(resource).exists():raise ValueError("Build the scene first")
    return preview_report({"scene_id":scene_id,"resource_sha256":digest(fs_path(resource)),**engine(job,"preview",rendered=True,source=resource,kind="scene",directory=str(job.directory))},job.directory,scene_id)
