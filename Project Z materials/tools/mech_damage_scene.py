"""Внутри Blender: собрать отдельную сцену с ключами реакции, не трогая исходный .blend.

blender --background art/mech/Untitled.blend --python tools/mech_damage_scene.py -- output.blend
"""
import os
from pathlib import Path
import runpy
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--")+1:]
output = Path(args[0]).resolve()
assert output.suffix == ".blend" and output != Path(bpy.data.filepath).resolve(), "Use a new .blend path"
base = Path(__file__).with_name("mech_blender.py")
ns = runpy.run_path(str(base), init_globals={"ANIM": "hit", "PREVIEW": 0,
                                            "OUTD": os.environ.get("PZ_MECH_RENDER_DIR", str(output.parent / "render"))})
col = ns["COL"]
# У копии другой каталог: упакованная палитровая текстура не зависит от старых относительных путей.
texture = bpy.data.images.load(ns["TEX"], check_existing=False)
texture.pack()
for o in col.objects:
    for material in o.data.materials:
        if material and material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE":
                    node.image, node.interpolation = texture, "Closest"
for frame, pose in [(1, 2), (2, 0), (9, 1), (19, 2), (30, 2)]:
    ns["hit_pose"](pose)
    for o in col.objects:
        o.rotation_mode = "XYZ"
        o.keyframe_insert(data_path="location", frame=frame)
        o.keyframe_insert(data_path="rotation_euler", frame=frame)
for o in col.objects:
    action = o.animation_data.action
    action.name = "AN_Mech_Hit_" + o.name
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = "CONSTANT"
sc, cam = ns["sc"], ns["cam"]
sc.render.fps = 100
sc.render.fps_base = 1
sc.frame_start, sc.frame_end = 1, 120
sc.timeline_markers.clear()
for frame, name in [(1, "IDLE"), (2, "IMPACT"), (9, "REBOUND"), (19, "REST")]:
    sc.timeline_markers.new(name, frame=frame)
cam.rotation_euler = (ns["math"].pi/2 - ns["PITCH"], 0, ns["math"].pi - ns["math"].radians(45))
bpy.context.view_layer.update()
R = cam.matrix_world.to_3x3()
cam.location = (R @ Vector((0, 1, 0))) * (218-128) / 56 - (R @ Vector((0, 0, -1))) * 60
sc.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_perspective = "CAMERA"
            area.spaces.active.shading.type = "MATERIAL"
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(output))
print("Damage scene saved:", output)
