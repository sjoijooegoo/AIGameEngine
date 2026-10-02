"""Original small GLB fixtures; optional Blender export supplies a real FBX test package."""
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw
from lab import ROOT

FIXTURES = ROOT / "tests/asset_fixtures"


def glb(path, parts, texture):
    faces=[((0,0,1),[(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]),((0,0,-1),[(1,-1,-1),(-1,-1,-1),(-1,1,-1),(1,1,-1)]),((1,0,0),[(1,-1,1),(1,-1,-1),(1,1,-1),(1,1,1)]),((-1,0,0),[(-1,-1,-1),(-1,-1,1),(-1,1,1),(-1,1,-1)]),((0,1,0),[(-1,1,1),(1,1,1),(1,1,-1),(-1,1,-1)]),((0,-1,0),[(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1)])]
    pos=[];norm=[];uv=[];idx=[]
    for i,(normal,corners) in enumerate(faces):
        for point,coord in zip(corners,[(0,1),(1,1),(1,0),(0,0)]):
            pos.extend(v/2 for v in point);norm.extend(normal);uv.extend(coord)
        idx.extend(i*4+n for n in [0,1,2,0,2,3])
    binary=bytearray();views=[]
    def add(data):
        binary.extend(b'\0'*(-len(binary)%4));views.append({'buffer':0,'byteOffset':len(binary),'byteLength':len(data)});binary.extend(data)
    for values,fmt in [(pos,'f'),(norm,'f'),(uv,'f'),(idx,'H')]:add(struct.pack('<'+str(len(values))+fmt,*values))
    add(texture.read_bytes())
    palette=[[.23,.39,.46,1],[.69,.45,.22,1],[.11,.16,.20,1],[.78,.83,.81,1]]
    materials=[{'name':['Teal','Wood','Metal','Panel'][i],'pbrMetallicRoughness':{'baseColorFactor':color,'roughnessFactor':.65,'metallicFactor':.6 if i==2 else 0,**({'baseColorTexture':{'index':0}} if i==1 else {})}} for i,color in enumerate(palette)]
    data={'asset':{'version':'2.0','generator':'AIGameEngine original fixtures'},'scene':0,'scenes':[{'nodes':list(range(len(parts)))}],'nodes':[{'name':p[0],'mesh':p[3],'translation':p[1],'scale':p[2]} for p in parts],'meshes':[{'primitives':[{'attributes':{'POSITION':0,'NORMAL':1,'TEXCOORD_0':2},'indices':3,'material':i}]} for i in range(4)],'materials':materials,'textures':[{'source':0}],'images':[{'bufferView':4,'mimeType':'image/png'}],'accessors':[{'bufferView':0,'componentType':5126,'count':24,'type':'VEC3','min':[-.5]*3,'max':[.5]*3},{'bufferView':1,'componentType':5126,'count':24,'type':'VEC3'},{'bufferView':2,'componentType':5126,'count':24,'type':'VEC2'},{'bufferView':3,'componentType':5123,'count':36,'type':'SCALAR'}],'bufferViews':views,'buffers':[{'byteLength':len(binary)}]}
    text=json.dumps(data,separators=(',',':')).encode();text+=b' '*(-len(text)%4);binary.extend(b'\0'*(-len(binary)%4))
    chunks=struct.pack('<II',len(text),0x4E4F534A)+text+struct.pack('<II',len(binary),0x004E4942)+binary
    path.write_bytes(struct.pack('<III',0x46546C67,2,12+len(chunks))+chunks)


def main():
    FIXTURES.mkdir(exist_ok=True)
    texture=Image.new('RGB',(128,128),'#ddbe85');draw=ImageDraw.Draw(texture)
    for y in range(0,128,16):draw.line((0,y,127,y),fill='#ac854e',width=2)
    texture.save(FIXTURES/'wood.png')
    models={
        'counter':[('Body',[0,.5,0],[2.1,1,.65],0),('Worktop',[0,1.05,0],[2.2,.1,.7],1),('Trim',[0,.25,-.331],[1.95,.08,.02],3)],
        'chair':[('Seat',[0,.45,0],[.55,.1,.55],0),('Back',[0,.72,.25],[.55,.36,.05],0)]+[(f'Leg{i}',[x,.2,z],[.05,.4,.05],2) for i,(x,z) in enumerate([(-.22,-.22),(.22,-.22),(-.22,.22),(.22,.22)])],
        'door':[('Door',[0,1.15,0],[1.25,2.3,.12],1),('Handle',[.45,1,-.085],[.16,.04,.05],2)],
        'terminal':[('Base',[0,.035,0],[.35,.07,.3],2),('Stem',[0,.15,0],[.07,.23,.06],2),('Display',[0,.3,0],[.45,.3,.06],3),('Screen',[0,.3,-.032],[.4,.24,.008],0)]}
    for name,parts in models.items():glb(FIXTURES/(name+'.glb'),parts,FIXTURES/'wood.png')
    missing=gltf_document_for_missing()
    (FIXTURES/'missing_texture.gltf').write_text(json.dumps(missing),encoding='utf-8')
    print(FIXTURES)


def gltf_document_for_missing():
    return {'asset':{'version':'2.0'},'images':[{'uri':'not_present.png'}],'scenes':[{}],'scene':0}


if __name__=='__main__':main()
