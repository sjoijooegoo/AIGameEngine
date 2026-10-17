"""SourceIO-backed MDL decoder with complete mixed FRAMEANIM channel handling.

SourceIO is pinned in source-animation-tool.json; no Blender addon registration.
Static and animated channels coexist; absent channels retain the bind pose.
Section tails store their final frame in a separate one-frame block.
"""
import numpy as np
from SourceIO.library.models.mdl.structs.local_animation import ANIM_DTYPE, AnimDescFlags, AniBoneFlags
from SourceIO.library.models.mdl.structs.compressed_vectors import Quat48, Quat48S


def frame_block(buffer, bones, count, delta=False):
    start=buffer.tell()
    constant, animated, stride=buffer.read_fmt('3i');buffer.skip(12)
    flags=[AniBoneFlags(buffer.read_uint8()) for _ in bones]
    result={}
    for b in bones:
        values=np.zeros(count,ANIM_DTYPE)
        values['rot']=(0,0,0,1) if delta else b.quat
        values['pos']=(0,0,0) if delta else b.position
        result[b.name]=values
    if constant:
        buffer.seek(start+constant)
        for b,flag in zip(bones,flags):
            if flag&AniBoneFlags.CONST_ROT2:result[b.name]['rot']=Quat48S.read(buffer)
            if flag&AniBoneFlags.RAW_ROT:result[b.name]['rot']=Quat48.read(buffer)
            if flag&AniBoneFlags.RAW_POS:result[b.name]['pos']=buffer.read_fmt('3e')
            if flag&AniBoneFlags.CONST_POS2:result[b.name]['pos']=buffer.read_fmt('3f')
    if animated and stride:
        for i in range(count):
            buffer.seek(start+animated+i*stride)
            for b,flag in zip(bones,flags):
                if flag&AniBoneFlags.ANIM_ROT2:result[b.name]['rot'][i]=Quat48S.read(buffer)
                if flag&AniBoneFlags.ANIM_ROT:result[b.name]['rot'][i]=Quat48.read(buffer)
                if flag&AniBoneFlags.ANIM_POS:result[b.name]['pos'][i]=buffer.read_fmt('3e')
                if flag&AniBoneFlags.FULL_ANIM_POS:result[b.name]['pos'][i]=buffer.read_fmt('3f')
            if buffer.tell()>start+animated+(i+1)*stride:raise ValueError('Frame channels exceed stride')
    return result


def decode(desc, mdl_buffer, bones, ani_buffer, block_table):
    delta=bool(desc.flags&AnimDescFlags.DELTA)
    def block(block_id, offset, count):
        source=mdl_buffer if block_id==0 else ani_buffer
        source.seek(desc._entry_offset+offset if block_id==0 else block_table[block_id].data_offset+offset)
        if desc.flags&AnimDescFlags.FRAMEANIM:return frame_block(source,bones,count,delta)
        return desc._read_animation_frames(source,bones,count)
    sections=desc.get_sections(mdl_buffer)
    if not sections:return block(desc.animblock_id,desc.animblock_offset,desc.frame_count)
    result={b.name:np.zeros(desc.frame_count,ANIM_DTYPE) for b in bones}
    at=0
    while at<desc.frame_count:
        last=at==desc.frame_count-1
        section_id=desc.frame_count//desc.section_frame_count+1 if last else at//desc.section_frame_count
        count=1 if last else min(desc.section_frame_count,desc.frame_count-1-at)
        section=sections[section_id]
        values=block(section.anim_block,section.anim_offset,count)
        for b in bones:
            result[b.name]['pos'][at:at+count]=values[b.name]['pos'] if b.name in values else ((0,0,0) if delta else b.position)
            result[b.name]['rot'][at:at+count]=values[b.name]['rot'] if b.name in values else ((0,0,0,1) if delta else b.quat)
        at+=count
    return result
