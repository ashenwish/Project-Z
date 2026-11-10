import bpy
from mathutils import Matrix

sc=bpy.context.scene;col=bpy.data.collections['Mech']
assert len(col.objects)==66
def identity(M):return all(abs(v)<1e-5 for row in M-Matrix.Identity(4) for v in row)
for frame in [1,11,25,43,65,91]:
    sc.frame_set(frame)
    for name in ['008','044','040','046','012','049','043','052']:
        assert identity(bpy.data.objects['Mech_body.'+name].matrix_world),(frame,name,'feet move')
sc.frame_set(91)
assert abs(bpy.data.objects['Mech_body'].matrix_world[1][2])>.6,'Missing cabin tilt'
for frame in [107,115,125,300]:
    sc.frame_set(frame)
    for o in col.objects:
        low=min((o.matrix_world@v.co).z for v in o.data.vertices)
        assert low>=-0.0001,(frame,o.name,'below floor',low)
sc.frame_set(125)
high=max((o.matrix_world@v.co).z for o in col.objects for v in o.data.vertices)
assert high<1.1,('wreck too tall',high)
for m in {m for o in col.objects for m in o.data.materials if m and m.use_nodes}:
    assert abs(m.node_tree.nodes['Scorch'].inputs[0].default_value-1)<1e-6
    for n in m.node_tree.nodes:
        if n.type=='TEX_IMAGE':assert n.image.packed_file and len(n.image.pixels)>0,'Missing texture'
assert sc.render.fps==100 and sc.frame_end==300 and len(sc.timeline_markers)==5
print('DEATH SCENE QA PASS: 66 parts; fixed feet before blast; 38 degree tilt; no geometry below floor; flat wreck; charred material; packed textures')
