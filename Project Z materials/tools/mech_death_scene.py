"""Blender: отдельная сцена механической гибели и обгоревшего остова, без замены исходника."""
import math
import os
from pathlib import Path
import runpy
import sys

import bpy
from mathutils import Vector

output=Path(sys.argv[sys.argv.index('--')+1]).resolve()
assert output.suffix=='.blend' and output!=Path(bpy.data.filepath).resolve()
rd=os.environ.get('PZ_MECH_RENDER_DIR',str(output.parent/'render'))
ns=runpy.run_path(str(Path(__file__).with_name('mech_blender.py')),init_globals={'ANIM':'die','PREVIEW':0,'OUTD':rd})
col=ns['COL']
original=bpy.data.images.load(ns['TEX'],check_existing=False);original.pack()
charred=bpy.data.images.load(str(output.parent/'textures/mech_scout_charred.png'),check_existing=False);charred.pack()
materials={m for o in col.objects for m in o.data.materials if m and m.use_nodes}
for m in materials:
    nt=m.node_tree
    tex=next(n for n in nt.nodes if n.type=='TEX_IMAGE');tex.image=original;tex.interpolation='Closest'
    burned=nt.nodes.new('ShaderNodeTexImage');burned.image=charred;burned.interpolation='Closest'
    mix=nt.nodes.new('ShaderNodeMixRGB');mix.name='Scorch';mix.blend_type='MIX'
    nt.links.new(tex.outputs['Color'],mix.inputs[1]);nt.links.new(burned.outputs['Color'],mix.inputs[2])
    bsdf=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    nt.links.new(mix.outputs[0],bsdf.inputs['Base Color'])
    for frame,value in [(1,0),(91,0),(107,1),(300,1)]:
        mix.inputs[0].default_value=value;mix.inputs[0].keyframe_insert(data_path='default_value',frame=frame)
poses=[(frame,'die',i) for i,frame in enumerate([1,11,25,43,65,91])]+[(107,'shatter',0),(115,'shatter',1),(125,'wreck',0),(300,'wreck',0)]
for frame,anim,i in poses:
    ns[anim+'_pose'](i);bpy.context.view_layer.update()
    for o in col.objects:
        o.rotation_mode='XYZ'
        for path in ['location','rotation_euler','scale']:o.keyframe_insert(data_path=path,frame=frame)
for item in list(col.objects)+[m.node_tree for m in materials]:
    action=item.animation_data.action;action.name='AN_Mech_Death_'+item.name
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='CONSTANT'
sc,cam=ns['sc'],ns['cam'];sc.render.fps=100;sc.render.fps_base=1;sc.frame_start=1;sc.frame_end=300
sc.timeline_markers.clear()
for frame,name in [(1,'PILOT_KILLED'),(25,'SMOKE'),(91,'EXPLOSION'),(107,'SHATTER'),(125,'WRECK_ON_FLOOR')]:
    sc.timeline_markers.new(name,frame=frame)
cam.rotation_euler=(math.pi/2-ns['PITCH'],0,math.pi-math.radians(45));bpy.context.view_layer.update()
R=cam.matrix_world.to_3x3();cam.location=(R@Vector((0,1,0)))*(218-128)/56-(R@Vector((0,0,-1)))*60
sc.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
output.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(output))
print('Death scene saved:',output)
