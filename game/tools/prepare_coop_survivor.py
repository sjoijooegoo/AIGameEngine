"""Blender background script: local L4D2 Nick skin and three native locomotion clips.

Read-only installation -> immutable snapshots -> optional client-only GLB.
Requires the pinned SourceIO checkout; no Blender addon/global configuration changes.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'.tools'),str(ROOT/'engine/tools')]


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'game/runtime/coop/local_reference')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    import bpy
    from mathutils import Matrix,Vector,Quaternion
    from source_archive import Installation
    from source_animation_decode import decode
    from SourceIO.library.models.mdl.v49.mdl_file import MdlV49
    from SourceIO.library.models.mdl.structs.ani_file import read_anim_block_table
    from SourceIO.library.utils import FileBuffer,MemoryBuffer,TinyPath
    from SourceIO.library.shared.content_manager import ContentManager
    from SourceIO.library.shared.content_manager.providers.loose_files import LooseFilesContentProvider
    from SourceIO.blender_bindings.models.mdl49 import import_mdl49
    from SourceIO.blender_bindings.operators.import_settings_base import ModelOptions
    from SourceIO.library.source1.vtf import load_texture

    lock=json.loads((ROOT/'engine/vendor/sourceio.lock.json').read_text(encoding='utf8'))
    revision=subprocess.check_output(['git','-C',str(ROOT/'.tools/SourceIO'),'rev-parse','HEAD'],text=True).strip()
    assert revision==lock['commit'],'SourceIO must match the pinned commit'
    install=Installation(args.source)
    source=ROOT/'outerasset/source-snapshots/coop-gambler-v2'
    keys=['models/survivors/'+name for name in ['survivor_gambler.mdl','survivor_gambler.vvd','survivor_gambler.dx90.vtx','anim_gambler.mdl','anim_gambler.ani']]
    model_key=keys[0];mdl=MdlV49.from_buffer(MemoryBuffer(install.entries[model_key].read(model_key)))
    base_textures={}
    for mat in mdl.materials:
        folders=[folder.replace('\\','/').strip('/') for folder in mdl.materials_paths]
        candidates=[f'materials/{folder}/{mat.name}.vmt'.lower() for folder in folders]
        candidates.insert(0,f'materials/{mat.name}.vmt'.lower())
        vmt=next((key for key in candidates if key in install.entries),None)
        if not vmt:continue
        keys.append(vmt)
        text=install.entries[vmt].read(vmt).decode('utf8',errors='replace')
        match=re.search(r'"?\$(?:basetexture|iris)"?\s+"?([^"\s]+)',text,re.I)
        if not match:continue
        texture='materials/'+match[1].replace('\\','/').lower()+'.vtf'
        if texture in install.entries:keys.append(texture);base_textures[mat.name]=texture
    items=install.extract(keys,source)
    (source/'manifest.json').write_text(json.dumps({'items':items},indent=2),encoding='utf8')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    manager=ContentManager();manager.add_child(LooseFilesContentProvider(TinyPath(source.as_posix())))
    options=ModelOptions.default();options.scale=.0254;options.import_textures=False
    options.import_animations=False;options.create_flex_drivers=False;options.bodygroup_vis_switches=False
    options.generate_wrinkle_map_node_group=False
    container=import_mdl49(TinyPath(model_key),FileBuffer(str(source/model_key)),manager,options)
    mdl=container.mdl
    rig=container.armature
    if not rig.users_collection:bpy.context.scene.collection.objects.link(rig)
    chosen=[]
    for alternatives in container.bodygroups.values():
        if alternatives and alternatives[0] is not None:chosen.append(alternatives[0])
    if not chosen:chosen=container.objects
    for obj in chosen:
        if not obj.users_collection:bpy.context.scene.collection.objects.link(obj)
    # PBR base color only; no Source shader conversion is implied.
    for mat in mdl.materials:
        material=mat.bpy_material
        material.use_nodes=True;material.node_tree.nodes.clear()
        output=material.node_tree.nodes.new('ShaderNodeOutputMaterial')
        shader=material.node_tree.nodes.new('ShaderNodeBsdfPrincipled');shader.inputs['Roughness'].default_value=.85
        material.node_tree.links.new(shader.outputs['BSDF'],output.inputs['Surface'])
        texture=base_textures.get(mat.name)
        if texture:
            pixels,height,width=load_texture(FileBuffer(str(source/texture)))
            image=bpy.data.images.new(mat.name+'_albedo',width=width,height=height,alpha=True)
            # VTF decoder rows are top-first; Blender's pixel buffer is bottom-first.
            image.pixels.foreach_set(pixels[::-1].reshape(-1));image.pack()
            node=material.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
            material.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
            if 'hair' in mat.name:
                material.node_tree.links.new(node.outputs['Alpha'],shader.inputs['Alpha'])
                material.surface_render_method='DITHERED'
    path=source/'models/survivors/anim_gambler.mdl';buffer=FileBuffer(str(path));anim_mdl=MdlV49.from_buffer(buffer)
    ani=FileBuffer(str(path.with_suffix('.ani')))
    blocks=read_anim_block_table(buffer,anim_mdl.header.anim_block_offset,anim_mdl.header.anim_block_count)
    selected={'idle':'@Idle_Calm_Pistol','walk':'a_WalkN_Rifle','run':'a_RunN_Rifle'}
    anim_bones={bone.name:bone for bone in anim_mdl.bones}
    rig.rotation_euler.z=math.pi/2 # Source +X -> Blender +Y -> Godot -Z.
    rig.animation_data_create();bpy.context.scene.render.fps=30
    def quat(v):return Quaternion((float(v[3]),float(v[0]),float(v[1]),float(v[2]))).normalized()
    metadata={}
    for clip,name in selected.items():
        desc=next(a for a in anim_mdl.anim_descs if a.name==name)
        assert not int(desc.flags)&4,'Only complete, non-additive clips are accepted'
        samples=decode(desc,buffer,anim_mdl.bones,ani,blocks)
        action=bpy.data.actions.new(clip);rig.animation_data.action=action
        for frame in range(desc.frame_count):
            bpy.context.scene.frame_set(frame)
            for bone in rig.pose.bones:
                rest=bone.bone.matrix_local.copy()
                if bone.parent:rest=bone.parent.bone.matrix_local.inverted()@rest
                src=anim_bones.get(bone.name)
                if src and bone.name in samples:
                    sample=samples[bone.name][frame];p=Vector(sample['pos']);q=quat(sample['rot'])
                    if src.parent_id<0:
                        p.x-=float(samples[bone.name]['pos'][:,0].mean());p.y-=float(samples[bone.name]['pos'][:,1].mean())
                    p=rest.translation+(p-Vector(src.position))*.0254
                    q=rest.to_quaternion()@quat(src.quat).inverted()@q
                    local=Matrix.Translation(p)@q.to_matrix().to_4x4()
                else:local=rest
                bone.matrix=(bone.parent.matrix@local) if bone.parent else local
                bone.rotation_mode='QUATERNION'
                bone.keyframe_insert(data_path='location',frame=frame)
                bone.keyframe_insert(data_path='rotation_quaternion',frame=frame)
            bpy.context.view_layer.update()
        track=rig.animation_data.nla_tracks.new();track.name=clip
        strip=track.strips.new(clip,0,action);strip.action_slot=action.slots[0];track.mute=True
        metadata[clip]={'source':name,'frames':desc.frame_count,'source_fps':desc.fps,'duration':(desc.frame_count-1)/30.0}
    rig.animation_data.action=None
    for track in rig.animation_data.nla_tracks:track.mute=False
    bpy.context.scene.frame_set(0)
    for obj in bpy.context.scene.objects:obj.select_set(obj==rig or obj in chosen)
    bpy.context.view_layer.objects.active=rig
    args.output.mkdir(parents=True,exist_ok=True)
    target=args.output/'survivor.glb'
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,
        export_skins=True,export_animations=True,export_animation_mode='NLA_TRACKS',
        export_apply=False,export_def_bones=False,export_morph=False,export_rest_position_armature=True)
    versioned=args.output/('survivor_'+sha(target)[:12]+'.glb')
    if not versioned.exists():shutil.copy2(target,versioned)
    report={'source':'Left 4 Dead 2 / survivor_gambler (Nick)','rights':'local_reference_only_rights_unverified',
        'source_manifest':str(source/'manifest.json'),'sourceio_commit':revision,'converter_sha256':sha(__file__),
        'units':'0.0254 metre per Source unit','forward':'Godot -Z','texture_roles':['albedo (sRGB)'],
        'root_motion':'horizontal mean removed; gameplay owns translation','bones':len(rig.data.bones),'clips':metadata,
        'output_sha256':sha(target),'resource':'res://coop/local_reference/'+versioned.name,
        'source_preserved':all(sha(source/item['path'])==item['sha256'] for item in items)}
    (args.output/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('COOP_SURVIVOR',json.dumps(report),flush=True)


if __name__=='__main__':main()
