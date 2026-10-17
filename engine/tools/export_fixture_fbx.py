"""Run only in a fresh Blender --background --factory-startup process."""
import sys
from pathlib import Path
import bpy

directory=Path(sys.argv[sys.argv.index('--')+1]).resolve()
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(directory/'chair.glb'))
for obj in bpy.context.scene.objects:
    if obj.type=='MESH':
        obj.data=obj.data.copy()
bpy.ops.export_scene.fbx(filepath=str(directory/'chair.fbx'),use_selection=False,path_mode='COPY',embed_textures=True,axis_forward='-Z',axis_up='Y',bake_anim=False)
