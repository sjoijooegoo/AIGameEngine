"""Read-only L4D2 world weapons -> versioned skinned GLBs with explicit source metadata.

Run in the pinned Blender/SourceIO environment, never against the live .blend file.
"""
import argparse,hashlib,json,re,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'.tools'),str(ROOT/'engine/tools')]
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',required=True,type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    import bpy
    from source_archive import Installation
    from SourceIO.library.models.mdl.v49.mdl_file import MdlV49
    from SourceIO.library.utils import FileBuffer,MemoryBuffer,TinyPath
    from SourceIO.library.shared.content_manager import ContentManager
    from SourceIO.library.shared.content_manager.providers.loose_files import LooseFilesContentProvider
    from SourceIO.blender_bindings.models.mdl49 import import_mdl49
    from SourceIO.blender_bindings.operators.import_settings_base import ModelOptions
    from SourceIO.library.source1.vtf import load_texture
    lock=json.loads((ROOT/'engine/vendor/sourceio.lock.json').read_text(encoding='utf8'))
    revision=subprocess.check_output(['git','-C',str(ROOT/'.tools/SourceIO'),'rev-parse','HEAD'],text=True).strip()
    assert revision==lock['commit']
    installation=Installation(args.source);output=ROOT/'game/runtime/coop/local_reference';output.mkdir(exist_ok=True)
    source=ROOT/'outerasset/source-snapshots/coop-world-weapons-v1'
    manifest={'sourceio_commit':revision,'converter_sha256':sha(__file__),'units':'0.0254 metre per Source unit',
              'rights':'local_reference_only_rights_unverified','texture_roles':['albedo (sRGB)'],'weapons':{}}
    records=[]
    for weapon,stem in [('pistol','w_pistol_a'),('shotgun','w_pumpshotgun_a')]:
        model_key=f'models/w_models/weapons/{stem}.mdl';mdl=MdlV49.from_buffer(MemoryBuffer(installation.entries[model_key].read(model_key)))
        keys=[f'models/w_models/weapons/{stem}{ext}' for ext in ['.mdl','.vvd','.dx90.vtx']];textures={}
        for material in mdl.materials:
            name=material.name.replace('\\','/');folders=[folder.replace('\\','/').strip('/') for folder in mdl.materials_paths]
            candidates=[f'materials/{name}.vmt'.lower()]+[f'materials/{folder}/{name}.vmt'.lower() for folder in folders if folder]
            vmt=next((key for key in candidates if key in installation.entries),None)
            assert vmt,material.name
            keys.append(vmt);text=installation.entries[vmt].read(vmt).decode('utf8',errors='replace')
            match=re.search(r'"?\$basetexture"?\s+"?([^"\s]+)',text,re.I);assert match,vmt
            texture='materials/'+match[1].replace('\\','/').lower()+'.vtf';assert texture in installation.entries,texture
            textures[material.name]=texture;keys.append(texture)
        records+=installation.extract(keys,source)
        bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
        manager=ContentManager();manager.add_child(LooseFilesContentProvider(TinyPath(source.as_posix())))
        options=ModelOptions.default();options.scale=.0254;options.import_textures=False;options.import_animations=False
        options.create_flex_drivers=False;options.bodygroup_vis_switches=False;options.generate_wrinkle_map_node_group=False
        container=import_mdl49(TinyPath(model_key),FileBuffer(str(source/model_key)),manager,options)
        rig=container.armature
        if not rig.users_collection:bpy.context.scene.collection.objects.link(rig)
        for obj in container.objects:
            if not obj.users_collection:bpy.context.scene.collection.objects.link(obj)
        for material in container.mdl.materials:
            mat=material.bpy_material;mat.use_nodes=True;mat.node_tree.nodes.clear()
            end=mat.node_tree.nodes.new('ShaderNodeOutputMaterial');shader=mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
            shader.inputs['Roughness'].default_value=.52;shader.inputs['Metallic'].default_value=.25
            mat.node_tree.links.new(shader.outputs['BSDF'],end.inputs['Surface'])
            pixels,height,width=load_texture(FileBuffer(str(source/textures[material.name])))
            image=bpy.data.images.new(weapon+'_'+material.name+'_albedo',width=width,height=height,alpha=True)
            image.pixels.foreach_set(pixels[::-1].reshape(-1));image.pack()
            node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
            mat.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
        for obj in bpy.context.scene.objects:obj.select_set(obj==rig or obj in container.objects)
        bpy.context.view_layer.objects.active=rig
        target=output/(weapon+'_world.glb')
        bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_skins=True,
            export_animations=False,export_apply=False,export_def_bones=False,export_morph=False,export_rest_position_armature=True)
        versioned=output/(weapon+'_world_'+sha(target)[:12]+'.glb')
        if not versioned.exists():shutil.copy2(target,versioned)
        muzzle=next(a for a in mdl.attachments if a.name=='muzzle_flash')
        manifest['weapons'][weapon]={'resource':'res://coop/local_reference/'+versioned.name,'output_sha256':sha(target),
            'source':model_key,'attach_bone':'ValveBiped.weapon_bone','muzzle_in_bone':[x*.0254 for x in muzzle.pos],
            'bones':[b.name for b in mdl.bones],'polygons':sum(len(o.data.polygons) for o in container.objects if o.type=='MESH')}
    manifest['source_manifest']=str(source/'manifest.json');manifest['source_preserved']=all(sha(source/r['path'])==r['sha256'] for r in records)
    (source/'manifest.json').write_text(json.dumps({'items':records},indent=2),encoding='utf8')
    (output/'weapons.json').write_text(json.dumps(manifest,indent=2),encoding='utf8');print('COOP_WEAPONS',json.dumps(manifest),flush=True)

if __name__=='__main__':main()
