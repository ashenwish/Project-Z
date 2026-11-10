"""Мех-разведчик в Blender: модель Tripo + наша текстура в палитре + позы + служебные проходы для спрайта.

Внутри Blender (MCP / Text Editor):
  ANIM, DIRS = "walk", ["se"]; exec(open(r"D:/PRZ/Project Z materials/tools/mech_blender.py", encoding="utf-8").read())
ANIM: idle | walk | hit | shoot | stomp | die | shatter | wreck | piece_cover | piece_shield | piece_cap.
OUTD можно задать отдельно для пробного рендера. REBUILD = True — заново импортировать модель.
Подготовка (один раз): импорт FBX -> разворот на 180° (перед модели был -Y, у нас +Y) и масштаб: пилот ростом
с героя x 1.35 (грудь пилота ~2.1 м — только двойной прыжок) -> разбивка на куски, пилот Tripo удаляется
(наш — из hero_render) -> текстура mech_scout_pz.png (Closest).
Позы: ноги — обратное колено (шагоход): бедро вращается вокруг шарнира бедра, голень с коленом — вокруг колена,
стопа остаётся горизонтальной; колено по двум костям (как leg_ik героя, но сгиб назад). Корпус качается по z.
Проходы (камера как у героя: орто, 30°, 1 px = 1/56 м) в EXR: id, normal, pos, uv ->
  art/mech/render/passes_<anim>_<dir>_<n>.npz  +  mech_<anim>.json (кадры, длительности, качание корпуса, скорость)
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = r"D:/PRZ/Project Z materials"
FBX = ROOT + "/art/mech/model/tripo_convert_454ac044-999a-4753-a79a-429154625d5d.fbx"
TEX = ROOT + "/art/mech/textures/mech_scout_pz.png"
OUTD = globals().get("OUTD", ROOT + "/art/mech/render")
S = 1 / 56
UNIT_PX = 175.5                     # 130 px (пилот = рост героя) x 1.35: грудь пилота ~119 px — только двойной прыжок (0.9 м + 0.9 м)
CAN, PIVOT = 256, (128, 218)
PITCH = math.radians(30)
ALL = {"s": 0, "se": 45, "e": 90, "ne": 135, "n": 180, "nw": 225, "w": 270, "sw": 315}
DIRS = globals().get("DIRS", ["se"])
ANIM = globals().get("ANIM", "idle")
os.makedirs(OUTD, exist_ok=True)
sc = bpy.context.scene
k = UNIT_PX * S


# ---------- модель (один раз) ----------
def build():
    col = bpy.data.collections.get("Mech")
    if col:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        col = bpy.data.collections.new("Mech")
        sc.collection.children.link(col)
    for o in sc.objects:                                # прочее не в кадр
        if o.type in ("MESH", "CURVE"):
            o.hide_render = True
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=FBX)
    src = [o for o in bpy.data.objects if o not in before and o.type == "MESH"][0]
    for c in list(src.users_collection):
        c.objects.unlink(src)
    col.objects.link(src)
    src.name = "Mech_body"
    src.data.transform(Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(k, 4))
    src.matrix_world = Matrix()
    m = src.data.materials[0]
    img = bpy.data.images.load(TEX, check_existing=True)
    img.reload()
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE":
            n.image, n.interpolation = img, "Closest"
    # пилот Tripo — по габаритам (оси Tripo, ед. модели): тело, голова, сапоги
    pilot = [((-0.127, -0.087, 0.593), (0.033, 0.096, 0.874)), ((-0.085, 0.015, 0.846), (-0.007, 0.094, 0.945)),
             ((0.04, -0.085, 0.494), (0.064, 0.009, 0.559)), ((-0.164, -0.086, 0.496), (-0.14, 0.008, 0.562))]
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = src
    src.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    removed = 0
    for o in list(col.objects):
        vs = [o.matrix_world @ v.co / k for v in o.data.vertices]
        mn = Vector((-max(v.x for v in vs), -max(v.y for v in vs), min(v.z for v in vs)))
        mx = Vector((-min(v.x for v in vs), -min(v.y for v in vs), max(v.z for v in vs)))
        if any(all(abs(mn[i] - a[i]) < 0.004 and abs(mx[i] - b[i]) < 0.004 for i in range(3)) for a, b in pilot):
            bpy.data.objects.remove(o, do_unlink=True)
            removed += 1
    assert removed == 4, f"пилот Tripo: удалено {removed} кусков из 4"
    for i, o in enumerate(sorted(col.objects, key=lambda o: o.name)):
        o.pass_index = i + 1
        for p in o.data.polygons:
            p.use_smooth = True
    sc["mech_ready"] = UNIT_PX


if globals().get("REBUILD") or sc.get("mech_ready") != UNIT_PX or not bpy.data.collections.get("Mech"):
    build()
COL = bpy.data.collections["Mech"]

# ---------- ноги: куски (номера после разбивки), суставы в px (оси меха) ----------
LEGS = {
    "l": dict(thigh=["009", "034", "005", "001"], shin=["057", "060", "041", "051"], foot=["008", "044", "040", "046"],
              hip=(-27.0, 100.5), knee=(-33.3, 48.0), ankle=(-12.3, 16.0)),
    "r": dict(thigh=["007", "037", "006", "029"], shin=["059", "042", "055"], foot=["012", "049", "043", "052"],
              hip=(-28.5, 103.0), knee=(-36.2, 51.5), ankle=(-14.9, 17.0)),
}
LEG_OBJ = {n for L in LEGS.values() for g in ("thigh", "shin", "foot") for n in L[g]}
# шаг: полуамплитуда стопы, подъём, доля опоры, кадры, fps (тяжёлый медленный шаг)
GAIT = dict(A=14.0, lift=9.0, stance=0.6, frames=8, fps=8)
REACH = 0.97


def obj(n):
    return bpy.data.objects["Mech_body." + n]


def foot_track(q):
    """Стопа (dy, dz) в фазе q: на опоре едет назад по полу, в переносе — дугой вперёд (как foot_track героя)."""
    A, st = GAIT["A"], GAIT["stance"]
    if q < st:
        return A * (1 - 2 * q / st), 0.0
    u = (q - st) / (1 - st)
    s = u * u * (3 - 2 * u)
    return -A + 2 * A * s, GAIT["lift"] * math.sin(math.pi * u ** 0.8)


def ik(h, a, L1, L2):
    """Колено в плоскости (y, z), сгиб назад (-y)."""
    d = a - h
    dist = min(d.length, L1 + L2 - 0.01)
    u = d.normalized()
    x = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
    hh = math.sqrt(max(L1 * L1 - x * x, 0))
    back = Vector((-u.y, u.x)) if Vector((-u.y, u.x)).x < 0 else Vector((u.y, -u.x))   # перпендикуляр назад
    return h + u * x + back * hh, h + u * dist


def rot_about(angle, py, pz):
    """Поворот вокруг оси x через точку (y, z) в px -> матрица в метрах."""
    p = Vector((0, py, pz)) * S
    return Matrix.Translation(p) @ Matrix.Rotation(angle, 4, "X") @ Matrix.Translation(-p)


def angle2(v0, v1):
    return math.atan2(v1.y, v1.x) - math.atan2(v0.y, v0.x)    # v = (y, z): поворот вокруг +x


def pose(phi):
    """Кадр шага в фазе phi (0..1). Возвращает смещение корпуса по z, px."""
    feet = {}
    for s, off in (("r", 0.0), ("l", 0.5)):
        feet[s] = foot_track((phi + off) % 1.0)
    # корпус: тяжёлое оседание на каждом шаге + не перетягивать ноги
    bob = -1.5 * (0.5 + 0.5 * math.cos(4 * math.pi * phi))
    for s, L in LEGS.items():
        h0, k0, a0 = (Vector(L[j]) for j in ("hip", "knee", "ankle"))
        L1, L2 = (k0 - h0).length, (a0 - k0).length
        dy, dz = feet[s]
        a = a0 + Vector((dy, dz))
        dyh = a.x - h0.x
        bob = min(bob, a.y + math.sqrt(max((REACH * (L1 + L2)) ** 2 - dyh * dyh, 0)) - h0.y)
    body = Matrix.Translation((0, 0, bob * S))
    for o in COL.objects:
        if o.name.split(".")[-1] not in LEG_OBJ:
            o.matrix_world = body
    for s, L in LEGS.items():
        h0, k0, a0 = (Vector(L[j]) for j in ("hip", "knee", "ankle"))
        L1, L2 = (k0 - h0).length, (a0 - k0).length
        dy, dz = feet[s]
        h = h0 + Vector((0, bob))
        kn, an = ik(h, a0 + Vector((dy, dz)), L1, L2)
        mt = Matrix.Translation((0, (h.x - h0.x) * S, (h.y - h0.y) * S)) @ rot_about(angle2(k0 - h0, kn - h), h0.x, h0.y)
        ms = Matrix.Translation((0, (kn.x - k0.x) * S, (kn.y - k0.y) * S)) @ rot_about(angle2(a0 - k0, an - kn), k0.x, k0.y)
        mf = Matrix.Translation((0, (an.x - a0.x) * S, (an.y - a0.y) * S))
        for g, M in (("thigh", mt), ("shin", ms), ("foot", mf)):
            for n in L[g]:
                obj(n).matrix_world = M
    return bob


def rest():
    for o in COL.objects:
        o.matrix_world = Matrix()


def gait_speed():
    """Скорость без проскальзывания стоп, м/с (как gait_speed героя)."""
    cycle = 2 * GAIT["A"] / GAIT["stance"]
    return cycle * S / (GAIT["frames"] / GAIT["fps"])


def hit_pose(frame):
    """Отдача назад, обратное качание, покой; стопы неподвижны, колени держат кабину."""
    if int(frame) == 2:
        rest()
        return 0.0
    body = rot_about(math.radians((7, -2.5, 0)[int(frame)]), -24, 101)
    for o in COL.objects:
        if o.name.split(".")[-1] not in LEG_OBJ:
            o.matrix_world = body
    for side, L in LEGS.items():
        h0, k0, a0 = (Vector(L[j]) for j in ("hip", "knee", "ankle"))
        hp = body @ (Vector((-27 if side == "l" else 44, h0.x, h0.y)) * S)
        h = Vector((hp.y / S, hp.z / S))
        kn, an = ik(h, a0, (k0 - h0).length, (a0 - k0).length)
        mt = Matrix.Translation((0, (h.x - h0.x) * S, (h.y - h0.y) * S)) @ rot_about(angle2(k0 - h0, kn - h), h0.x, h0.y)
        ms = Matrix.Translation((0, (kn.x - k0.x) * S, (kn.y - k0.y) * S)) @ rot_about(angle2(a0 - k0, an - kn), k0.x, k0.y)
        for g, M in (("thigh", mt), ("shin", ms), ("foot", Matrix())):
            for n in L[g]:
                obj(n).matrix_world = M
    return 0.0


GUN = ["013", "014", "015", "016", "017", "020", "021", "024", "025", "026", "027", "030", "032", "036"]
STOMP = [((0, 0), 2, -2), ((14, 22), 2, -1), ((30, 26), -1, 0),
         ((30, 0), -3, -4), ((10, 7), -1, -1), ((0, 0), 0, 0)]


def shoot_pose(frame):
    """Два выстрела за цикл: откат узла оружия отдельно от лёгкой отдачи кабины."""
    frame = int(frame)
    rest()
    body = rot_about(math.radians((0.6, 0.15, 0.6, 0)[frame]), -24, 101)
    for o in COL.objects:
        if o.name.split(".")[-1] not in LEG_OBJ:
            o.matrix_world = body
    recoil = Matrix.Translation((0, -(3, 0.5, 3, 0)[frame] * S, 0))
    for n in GUN:
        obj(n).matrix_world = body @ recoil
    return 0.0


def stomp_pose(frame):
    """Правая нога бьёт вперёд; левая стопа остаётся на полу, колени решаются по IK."""
    frame = int(frame)
    rest()
    if frame == 5:
        return 0.0
    (dy, dz), angle, bob = STOMP[frame]
    lean = rot_about(math.radians(angle), -24, 101)
    # Кабина оседает до досягаемости ноги, чтобы удар действительно пришёлся в пол.
    for side, L in LEGS.items():
        h0, k0, a0 = (Vector(L[j]) for j in ("hip", "knee", "ankle"))
        hp = lean @ (Vector((-27 if side == "l" else 44, h0.x, h0.y)) * S)
        target = a0 + (Vector((dy, dz)) if side == "r" else Vector((0, 0)))
        reach = REACH * ((k0-h0).length + (a0-k0).length)
        bob = min(bob, target.y + math.sqrt(max(reach**2-(target.x-hp.y/S)**2, 0)) - hp.z/S)
    body = Matrix.Translation((0, 0, bob*S)) @ lean
    for o in COL.objects:
        if o.name.split(".")[-1] not in LEG_OBJ:
            o.matrix_world = body
    for side, L in LEGS.items():
        h0, k0, a0 = (Vector(L[j]) for j in ("hip", "knee", "ankle"))
        hp = body @ (Vector((-27 if side == "l" else 44, h0.x, h0.y)) * S)
        h = Vector((hp.y/S, hp.z/S))
        fd = Vector((dy, dz)) if side == "r" else Vector((0, 0))
        kn, an = ik(h, a0+fd, (k0-h0).length, (a0-k0).length)
        mt = Matrix.Translation((0, (h.x-h0.x)*S, (h.y-h0.y)*S)) @ rot_about(angle2(k0-h0, kn-h), h0.x, h0.y)
        ms = Matrix.Translation((0, (kn.x-k0.x)*S, (kn.y-k0.y)*S)) @ rot_about(angle2(a0-k0, an-kn), k0.x, k0.y)
        mf = Matrix.Translation((0, (an.x-a0.x)*S, (an.y-a0.y)*S))
        for group, M in (("thigh", mt), ("shin", ms), ("foot", mf)):
            for n in L[group]:
                obj(n).matrix_world = M
    return bob


def die_pose(frame):
    """После смерти пилота кабина заваливается вперёд на шарнире; ноги остаются на земле."""
    rest()
    body = rot_about(math.radians((0, -6, -14, -25, -32, -38)[int(frame)]), -24, 101)
    for o in COL.objects:
        if o.name.split(".")[-1] not in LEG_OBJ:
            o.matrix_world = body
    return 0.0


def wreck_pose(_frame):
    """Разбитые узлы лежат на полу: разная ориентация групп, плоский остов и отдельные детали."""
    rest()
    scraps = {"033", "020", "050"}
    body = [o for o in COL.objects if o.name.split(".")[-1] not in LEG_OBJ | set(GUN) | scraps]
    groups = [(body, (0, -4), 88, -15),
              ([obj(n) for L in [LEGS["l"]] for g in ("thigh", "shin", "foot") for n in L[g]], (-52, -15), 88, 38),
              ([obj(n) for L in [LEGS["r"]] for g in ("thigh", "shin", "foot") for n in L[g]], (48, -5), 98, -35),
              ([obj(n) for n in GUN if n not in scraps], (-34, 53), 90, 55),
              ([obj("033")], (56, 46), 90, 20), ([obj("020")], (-66, -43), 92, -25),
              ([obj("050")], (12, 63), 90, 40)]
    placed = []
    for objects, (x, y), pitch, yaw in groups:
        vs = [v.co for o in objects for v in o.data.vertices]
        center = Vector(tuple((min(v[j] for v in vs)+max(v[j] for v in vs))/2 for j in range(3)))
        M = Matrix.Translation((x*S, y*S, 0)) @ Matrix.Diagonal((1, 1, .28, 1)) \
            @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(pitch), 4, "X") @ Matrix.Translation(-center)
        low = min((M@v).z for v in vs)
        M = Matrix.Translation((0, 0, .003-low)) @ M
        for o in objects:
            o.matrix_world = M
            placed.append(o.name)
        # Blender раскладывает матрицу на rotation/scale; опору уточняем по фактической геометрии.
        bpy.context.view_layer.update()
        correction = .003-min((o.matrix_world@v.co).z for o in objects for v in o.data.vertices)
        for o in objects:
            actual = o.matrix_world.copy()
            actual.translation.z += correction
            o.matrix_world = actual
    assert len(placed)==len(set(placed))==len(COL.objects), "Every wreck part must occur exactly once"
    return 0.0


def shatter_pose(frame):
    die_pose(5)
    start = {o.name:o.matrix_world.copy() for o in COL.objects}
    wreck_pose(0)
    for o in COL.objects:
        M = start[o.name].lerp(o.matrix_world, (.42, .8)[int(frame)])
        low = min((M@v.co).z for v in o.data.vertices)
        if low < .003:
            M = Matrix.Translation((0,0,.003-low)) @ M
        o.matrix_world = M
    bpy.context.view_layer.update()
    for o in COL.objects:
        low = min((o.matrix_world@v.co).z for v in o.data.vertices)
        if low < .003:
            actual = o.matrix_world.copy()
            actual.translation.z += .003-low
            o.matrix_world = actual
    return 0.0


if ANIM == "wreck":
    PIVOT = (128, 128)
if ANIM == "shatter":
    PIVOT = (128, 200)


# Настоящие детали исходного меша: боковой кожух, щиток пулемёта, круглая крышка.
PIECES = {"cover": ["033"], "shield": ["020"], "cap": ["050"]}
piece = ANIM.removeprefix("piece_") if ANIM.startswith("piece_") else None
if piece is not None:
    visible_before = {o.name: o.hide_render for o in COL.objects}
    selected = [obj(n) for n in PIECES[piece]]
    vs = [v.co for o in selected for v in o.data.vertices]
    center = Vector(tuple((min(v[j] for v in vs) + max(v[j] for v in vs)) / 2 for j in range(3)))
    source_center_px = [round(v / S, 3) for v in center]
    for o in COL.objects:
        o.hide_render = o not in selected
    CAN, PIVOT = 64, (32, 32)


def piece_pose(frame):
    # Кувырок на месте: баллистическое перемещение задаёт движок, как у P_ врагов.
    t = frame / 8 * 2 * math.pi
    M = Matrix.Rotation(t, 4, "X") @ Matrix.Rotation(t * 2, 4, "Z") @ Matrix.Translation(-center)
    for o in selected:
        o.matrix_world = M
    return 0.0


ANIMS = {"idle": ([0.0], [1000], lambda phi: (rest(), 0.0)[1]),
         "walk": ([i / GAIT["frames"] for i in range(GAIT["frames"])], [round(1000 / GAIT["fps"])] * GAIT["frames"], pose),
         "hit": ([0, 1, 2], [70, 100, 110], hit_pose),
         "shoot": (list(range(4)), [30, 70, 30, 70], shoot_pose),
         "stomp": (list(range(6)), [100, 100, 90, 70, 110, 130], stomp_pose),
         "die": (list(range(6)), [100, 140, 180, 220, 260, 160], die_pose),
         "shatter": ([0,1], [80,100], shatter_pose),
         "wreck": ([0], [1000], wreck_pose)}
for name in PIECES:
    ANIMS["piece_" + name] = (list(range(8)), [70] * 8, piece_pose)


# ---------- проходы ----------
def override(name, build_):
    mt = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mt.use_nodes = True
    nt = mt.node_tree
    nt.nodes.clear()
    em, out = nt.nodes.new("ShaderNodeEmission"), nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    nt.links.new(build_(nt), em.inputs["Color"])
    return mt


def mul_add(nt, sock, a, b):
    v = nt.nodes.new("ShaderNodeVectorMath")
    v.operation = "MULTIPLY_ADD"
    nt.links.new(sock, v.inputs[0])
    v.inputs[1].default_value, v.inputs[2].default_value = (a,) * 3, (b,) * 3
    return v.outputs[0]


def b_id(nt):
    oi, cc = nt.nodes.new("ShaderNodeObjectInfo"), nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(oi.outputs["Object Index"], cc.inputs[0])
    return cc.outputs[0]


OVR = {"id": override("MP_id", b_id),
       "normal": override("MP_normal", lambda nt: mul_add(nt, nt.nodes.new("ShaderNodeNewGeometry").outputs["Normal"], 0.5, 0.5)),
       "pos": override("MP_pos", lambda nt: mul_add(nt, nt.nodes.new("ShaderNodeNewGeometry").outputs["Position"], 0.05, 0.5)),
       "uv": override("MP_uv", lambda nt: nt.nodes.new("ShaderNodeTexCoord").outputs["UV"])}

sc.render.engine = "CYCLES"
sc.cycles.samples = 1
sc.cycles.use_denoising = False
sc.cycles.pixel_filter_type = "BOX"
sc.cycles.filter_width = 0.01
sc.cycles.max_bounces = 0
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = CAN
sc.render.resolution_percentage = 100
vts = [i.identifier for i in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items]
sc.view_settings.view_transform = "Raw" if "Raw" in vts else "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure, sc.view_settings.gamma = 0, 1
sc.render.image_settings.file_format = "OPEN_EXR"
sc.render.image_settings.color_depth = "32"
sc.render.image_settings.color_mode = "RGBA"

cam = bpy.data.objects.get("Mech_Camera")
if cam is None:
    cam = bpy.data.objects.new("Mech_Camera", bpy.data.cameras.new("Mech_Camera"))
    sc.collection.objects.link(cam)
cam.data.type, cam.data.ortho_scale, cam.data.clip_end = "ORTHO", CAN * S, 200
sc.camera = cam
vl = bpy.context.view_layer

PREVIEW = globals().get("PREVIEW")      # фаза: поставить позу во вьюпорте без рендера
phases, durs, fn = ANIMS[ANIM]
if PREVIEW is not None:
    print("поза", ANIM, PREVIEW, "корпус dz", round(fn(PREVIEW), 2))
    phases = []
bobs, body_matrices, gun_matrices, foot_matrices = [], [], [], []
for i, phi in enumerate(phases):
    bobs.append(fn(phi))
    for name, matrices in (("Mech_body", body_matrices), ("Mech_body.021", gun_matrices), ("Mech_body.012", foot_matrices)):
        bm = bpy.data.objects[name].matrix_world.copy()
        bm.translation /= S
        matrices.append([list(row) for row in bm])
    vl.update()
    for d in DIRS:
        cam.rotation_euler = (math.pi / 2 - PITCH, 0, math.pi - math.radians(ALL[d]))
        vl.update()
        R = cam.matrix_world.to_3x3()
        fwd, up = R @ Vector((0, 0, -1)), R @ Vector((0, 1, 0))
        cam.location = up * (PIVOT[1] - CAN / 2) * S - fwd * 60    # точка пола (0,0,0) -> пиксель PIVOT
        out = {}
        for key, mt in OVR.items():
            vl.material_override = mt
            path = os.path.join(OUTD, f"_pass_{ANIM}_{key}.exr")
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            im = bpy.data.images.load(path, check_existing=False)
            out[key] = np.array(im.pixels[:], np.float32).reshape(CAN, CAN, 4)[::-1]
            bpy.data.images.remove(im)
            os.remove(path)
        vl.material_override = None
        np.savez_compressed(os.path.join(OUTD, f"passes_{ANIM}_{d}_{i}.npz"), **out)
if PREVIEW is None:
    rest()
    if piece is not None:
        for o in COL.objects:
            o.hide_render = visible_before[o.name]
    meta = {"frames": len(phases), "durations_ms": durs, "body_dz_px": [round(b, 2) for b in bobs],
            "canvas": [CAN, CAN], "pivot": list(PIVOT), "body_matrix_px": body_matrices}
    if ANIM in ("shoot", "stomp", "walk", "idle", "hit", "die"):
        meta.update(gun_matrix_px=gun_matrices, foot_r_matrix_px=foot_matrices)
    if ANIM == "die":
        meta.update(pilot_death=[0, .25, .55, .85, 1.0, None], pilot_outcome="bullet",
                    events={"pilot_killed": [0], "smoke": [2], "explode": [5]}, loop=False)
    if ANIM == "wreck":
        meta.update(pilot=False, floor=True, floor_basis={"yaw_degrees": 45, "pitch_degrees": -90, "scale_y": 2}, loop=False)
    if ANIM == "shatter":
        meta.update(pilot=False, loop=False)
    if ANIM == "shoot":
        meta.update(events={"fire": [0, 2]}, loop=True)
    if ANIM == "stomp":
        meta.update(events={"impact": [3]}, loop=False)
    if ANIM == "walk":
        meta["speed_mps"] = round(gait_speed(), 3)
    if piece is not None:
        meta.update(pilot=False, source_objects=[o.name for o in selected],
                    source_center_px=source_center_px, source_ids=[o.pass_index for o in selected])
    json.dump(meta, open(os.path.join(OUTD, f"mech_{ANIM}.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(ANIM, DIRS, meta)
