import bpy
from mathutils import Matrix

sc = bpy.context.scene
feet = ['008','044','040','046','012','049','043','052']
assert len(bpy.data.collections['Mech'].objects) == 66
for frame in [1,2,9,19,30]:
    sc.frame_set(frame)
    for name in feet:
        assert all(abs(v) < 1e-6 for row in (bpy.data.objects['Mech_body.'+name].matrix_world-Matrix()) for v in row), (frame,name)
    M = bpy.data.objects['Mech_body'].matrix_world
    if frame in [2,9]:
        assert abs(M[1][2]) > 0.01, (frame,'missing tilt')
    else:
        assert all(abs(v) < 1e-6 for row in (M-Matrix()) for v in row), (frame,'rest')
assert len(sc.timeline_markers) == 4
assert sc.render.fps == 100
for o in bpy.data.collections['Mech'].objects:
    for m in o.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE':
                    # Packed images load pixels lazily after opening the .blend.
                    assert n.image and n.image.packed_file and len(n.image.pixels) > 0, 'Missing packed texture'
print('SCENE QA PASS: 66 animated parts; fixed feet; impact, rebound and rest; timeline markers; packed texture')
