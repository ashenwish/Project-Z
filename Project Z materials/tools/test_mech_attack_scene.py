"""Blender smoke-check: геометрия пола, откат оружия, якоря и возврат в стойку."""
import bpy
from mathutils import Matrix, Vector

sc=bpy.context.scene
left=['008','044','040','046'];right=['012','049','043','052']
def identity(M):
    return all(abs(v)<1e-5 for row in M-Matrix.Identity(4) for v in row)

for frame in [1,2,5,12,15,22,62]:
    sc.frame_set(frame)
    for n in left+right:
        assert identity(bpy.data.objects['Mech_body.'+n].matrix_world),(frame,n,'moving shooting foot')
sc.frame_set(2)
gun=bpy.data.objects['Mech_body.021'].matrix_world
body=bpy.data.objects['Mech_body'].matrix_world
assert abs((body.inverted()@gun).translation.y*56+3)<0.001,'Missing independent gun recoil'
assert (bpy.data.objects['Anchor_muzzle'].location-gun@(Vector((-30.55,66.3,149.7))/56)).length<.0002,'Muzzle is detached'
for frame,lift in [(82,0),(92,22),(102,26),(111,0),(118,7),(129,0)]:
    sc.frame_set(frame)
    for n in left:
        assert identity(bpy.data.objects['Mech_body.'+n].matrix_world),(frame,n,'support foot')
    for n in right:
        o=bpy.data.objects['Mech_body.'+n]
        assert abs(o.matrix_world.translation.z*56-lift)<.01,(frame,n,'incorrect foot height')
        assert min((o.matrix_world@v.co).z for v in o.data.vertices)>=-1e-5,(frame,n,'below floor')
sc.frame_set(129)
for o in bpy.data.collections['Mech'].objects:
    assert identity(o.matrix_world),(o.name,'not at rest')
    for m in o.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type=='TEX_IMAGE':assert n.image and n.image.packed_file and len(n.image.pixels)>0
assert sc.render.fps==100 and sc.frame_end==180
assert len(sc.timeline_markers)==8
print('ATTACK SCENE QA PASS: 66 parts; independent recoil; muzzle binding; fixed support foot; lifted and grounded striking foot; exact rest; packed texture')
