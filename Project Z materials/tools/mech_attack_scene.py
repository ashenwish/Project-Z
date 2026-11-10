"""Blender: отдельная сцена просмотра очереди и топота. Исходник не перезаписывать."""
import json
import math
import os
from pathlib import Path
import runpy
import sys

import bpy
from mathutils import Vector

output=Path(sys.argv[sys.argv.index('--')+1]).resolve()
assert output.suffix=='.blend' and output!=Path(bpy.data.filepath).resolve()
rd=Path(os.environ.get('PZ_MECH_RENDER_DIR',output.parent/'render'))
ns=runpy.run_path(str(Path(__file__).with_name('mech_blender.py')),init_globals={'ANIM':'shoot','PREVIEW':3,'OUTD':str(rd)})
texture=bpy.data.images.load(ns['TEX'],check_existing=False);texture.pack()
col=ns['COL']
for o in col.objects:
    for m in o.data.materials:
        if m and m.use_nodes:
            for node in m.node_tree.nodes:
                if node.type=='TEX_IMAGE':node.image,node.interpolation=texture,'Closest'
points={}
for name in ['muzzle','eject','foot_r']:
    o=bpy.data.objects.new('Anchor_'+name,None);bpy.context.scene.collection.objects.link(o)
    o.empty_display_size=.06;o.hide_render=True;points[name]=o
metadata={a:json.loads((rd/f'mech_{a}.json').read_text(encoding='utf-8')) for a in ['shoot','stomp']}
poses=[(1,'shoot',3)]
for start in [2,22,42]:
    poses.extend((start+off,'shoot',i) for i,off in enumerate([0,3,10,13]))
poses += [(62,'shoot',3)]+[(82+off,'stomp',i) for i,off in enumerate([0,10,20,29,36,47])]+[(150,'stomp',5)]
for frame,anim,i in poses:
    ns[anim+'_pose'](i)
    for o in col.objects:
        o.rotation_mode='XYZ';o.keyframe_insert(data_path='location',frame=frame);o.keyframe_insert(data_path='rotation_euler',frame=frame)
    for name,o in points.items():
        o.location=metadata[anim]['anchors_frames_m'][name][i]
        o.keyframe_insert(data_path='location',frame=frame)
for o in list(col.objects)+list(points.values()):
    action=o.animation_data.action;action.name='AN_Mech_Attacks_'+o.name
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='CONSTANT'
sc,cam=ns['sc'],ns['cam'];sc.render.fps=100;sc.render.fps_base=1;sc.frame_start=1;sc.frame_end=180
sc.timeline_markers.clear()
for frame,name in [(1,'IDLE'),(2,'MAXIM'),(82,'WINDUP'),(92,'LIFT'),(102,'READY'),(111,'STOMP'),(118,'RETRACT'),(129,'REST')]:
    sc.timeline_markers.new(name,frame=frame)
cam.rotation_euler=(math.pi/2-ns['PITCH'],0,math.pi-math.radians(45));bpy.context.view_layer.update()
R=cam.matrix_world.to_3x3();cam.location=(R@Vector((0,1,0)))*(218-128)/56-(R@Vector((0,0,-1)))*60
sc.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
output.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(output))
print('Attack scene saved:',output)
