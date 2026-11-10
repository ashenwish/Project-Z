"""Слоёные спрайты героя (правки 1, 3, 5): движок накладывает три слоя и сочетает их свободно.

  L_<анимация>   ноги: таз, бёдра, сапоги. Направление — по движению. Привязаны к полу.
  U_<анимация>   корпус, голова, правая рука с модулем протеза. Направление — по прицелу.
                 Нарисован с грудью в точке покоя; движок сдвигает его на смещение таза из кадра ног.
  A_<источник>   левая рука с револьвером, отдельно для каждого кадра корпуса (рука держится за плечо)
                 в 4 состояниях: готов, выстрел, отдача 1, отдача 2. Части руки, закрытые торсом, вырезаны,
                 поэтому слой A всегда рисуется поверх U.

Кадры: art/hero/layers/render/<слой>_<имя>_<направление>_<кадр>.png; описание: art/hero/layers/layers.json.

python tools/hero_layers.py            # всё
python tools/hero_layers.py legs       # только один вид слоёв: legs | upper | arm
"""
import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import attacks  # noqa: E402
import hero_render as hr  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "art", "hero", "layers")
RENDER = os.path.join(OUT, "render")
MODULES = ("blade", "sickle", "shotgun")
# Холст слоёв 128x128 (раунд 3): на 64x96 оружие и руки упирались в край и обрезались. Стопы в 3 px от низа, как раньше.
hr.W, hr.H, hr.PIVOT = 128, 128, (64, 125)

# Левая рука с револьвером (правка 3): локоть за боком, кисть у пояса, стрельба от бедра самовзводом.
PISTOL = [(-15, 95, -6), (-15, 111, -6), (-15, 103, -6), (-15, 98, -6)]   # готов, выстрел, отдача 1, 2
PISTOL_MS = [0, 40, 50, 60]
# Перезарядка револьвера (правка 6, раунд 3): слой R_ поверх корпуса, 3 позы левой руки.
PISTOL_RELOAD = [(2, 118, -4), (18, 136, -8), (0, 108, -5)]
PISTOL_RELOAD_MS = [260, 420, 300, 220]                 # кадры: поза 0, 1, 2, 0 = 1,2 с
PISTOL_RELOAD_SEQ = [0, 1, 2, 0]

# Обрез в протезе (правка 3): рука вытянута вперёд и отведена от тела; (рука, наклон, разворот, мс).
AIM_R = (86, 2, 14)
GUN = {
    "gun_aim": [(AIM_R, 0, 0, 200)],
    "gun_raise": [((20, 12, 4), 0, 0, 40), ((48, 8, 9), 0, 0, 40), ((72, 4, 12), 0, 0, 40)],
    "gun_lower": [((72, 4, 12), 0, 0, 60), ((48, 8, 9), 0, 0, 60), ((20, 12, 4), 0, 0, 60)],
    "gun_shoot": [(AIM_R, 0, 0, 40), ((108, -4, 18), -6, -4, 50), ((118, -10, 20), -8, -5, 70),
                  ((102, -2, 16), -5, -3, 80), ((92, 0, 15), -2, -1, 90), (AIM_R, 0, 0, 110)],
}
# Перезарядка обреза (правка 6, раунд 3), 2 с: опустить, выброс гильз, ствол вверх, зарядка паром, вернуть прицел.
GUN_RELOAD = [((48, 8, 9), 0, 0, 120), ((20, 12, 4), 4, 0, 140), ((10, 5, 0), 6, -4, 420), ((35, 70, 6), 2, 0, 150),
              ((45, 95, 8), 0, 4, 700), ((60, 60, 10), 0, 2, 150), ((72, 25, 12), 0, 0, 220), (AIM_R, 0, 0, 100)]
GUN["gun_reload"] = GUN_RELOAD
GUN["gun_reload_run"] = [(arm, ln + 6, tw, ms) for arm, ln, tw, ms in GUN_RELOAD]
# Мощный выстрел двумя стволами и ульта-поджигание (раунд 6): отдача сильнее, у ульты подъём ствола перед выстрелом (кадр 3).
GUN_SHOOT2 = [(AIM_R, 0, 0, 40), ((122, -8, 20), -10, -6, 60), ((138, -14, 22), -14, -8, 90), ((118, -8, 18), -10, -5, 110),
              ((102, -2, 16), -5, -3, 110), ((92, 0, 15), -2, -1, 110), (AIM_R, 0, 0, 120)]
GUN_ULT = [((48, 8, 9), 0, 0, 40), ((72, 4, 12), 0, 0, 50), (AIM_R, -2, 0, 70), ((124, -10, 20), -12, -6, 80),
           ((132, -12, 20), -12, -6, 110), ((105, -3, 16), -6, -3, 130), ((92, 0, 15), -2, 0, 120), (AIM_R, 0, 0, 100)]
for _n, _k in (("gun_shoot2", GUN_SHOOT2), ("gun_ult", GUN_ULT)):
    GUN[_n] = _k
    GUN[_n + "_run"] = [(arm, ln + 6, tw, ms) for arm, ln, tw, ms in _k]
MELEE_MODULE = {n: ("blade" if n.startswith("blade") else "sickle") for n in attacks.ATTACKS}
# Обрез на ходу и на бегу (правка 4, раунд 2): корпус с наклоном шага, прицел в такт ногам, выстрел с отдачей.
GAIT_LEAN = {"walk": 3, "run": 6}
MOVING_GUN = [f"gun_{s}_{g}" for g in ("walk", "run") for s in ("aim", "shoot")]

# Наведённые руки (раунд 11): рука поворачивается отдельно от корпуса, 16 направлений относительно груди (шаг 22,5°).
# A_aim — левая рука с револьвером, S_aim — правая рука с обрезом; корпус обреза в этих состояниях без правой руки (_noarm).
AIM_OFFSETS = [o * 22.5 if o * 22.5 <= 180 else o * 22.5 - 360 for o in range(16)]
PISTOL_AIM_KICK = [0, 16, 9, 3]                  # готов, выстрел, отдача 1, 2
SG_AIM_KICK = [0, 6, 16, 22, 32, 36, 52]         # отдача обреза: подъём руки, градусы
SG_FRAME_STATE = {"gun_aim": [0], "gun_shoot": [0, 3, 4, 2, 1, 0], "gun_shoot2": [0, 5, 6, 4, 2, 1, 0]}
NOARM = ["gun_aim", "gun_shoot", "gun_shoot2", "gun_aim_run", "gun_shoot_run", "gun_shoot2_run"]


# Поворот головы к наведённой руке (раунд 12): варианты корпусов, поверх которых рука наводится.
HEAD_YAWS = {"hl2": -12.0, "hl1": -6.0, "hr1": 6.0, "hr2": 12.0}
HEAD_BASE = ([(f"{s}_{m}", s, m) for m in MODULES for s in ("idle", "run")]
             + [(n + "_noarm", n, "shotgun_noarm") for n in NOARM])
HEAD_UPPER = [(f"{n}_{k}", s, m, y, n) for n, s, m in HEAD_BASE for k, y in HEAD_YAWS.items()]


def aim_base():
    return anchored(hr.make_pose(attacks.STANCE, bob=0.0, arm_l=(0, 0), arm_r=AIM_R))

# Рывок (правка 8, раунд 3) собран на скелете: низкий выпад, корпус вперёд, руки назад.
DASH = [
    (dict(l=(-5.6, -6, 4), r=(5.6, 6, 4)), -6, 12, (-10, 50), (-10, 40), 30),
    (dict(l=(-5.6, -20, 4), r=(5.6, 18, 8)), -9, 30, (-50, 40), (-45, 35), 50),
    (dict(l=(-5.6, -26, 8), r=(5.6, 22, 6)), -10, 36, (-70, 30), (-60, 25), 70),
    (dict(l=(-5.6, -22, 12), r=(5.6, 20, 4)), -10, 34, (-65, 30), (-55, 25), 60),
    (dict(l=(-5.6, -10, 6), r=(5.6, 12, 4)), -6, 18, (-25, 50), (-20, 40), 40),
]

# Вращение клинка (раунд 8), собрано на скелете. Рука вытянута вбок, клинок горизонтально, присед, ноги шагают вокруг оси,
# корпус наклонён; направления крутит движок. Кадры: замах, 4 шага вращения, возврат.
SPIN_ARM = (0, 2, 74)          # чуть ниже горизонтали: кончик клинка не упирается в край холста
SPIN = [
    (dict(l=(-9, 4, 4), r=(9, -4, 4)), -5, 8, -18, (40, 30, 40), 80),
    (dict(l=(-12, 6, 4), r=(12, -6, 4)), -8, 12, 6, SPIN_ARM, 60),
    (dict(l=(-12, 2, 8), r=(12, -2, 4)), -7, 12, 10, SPIN_ARM, 60),
    (dict(l=(-12, -6, 4), r=(12, 6, 4)), -8, 12, 6, SPIN_ARM, 60),
    (dict(l=(-12, -2, 4), r=(12, 2, 8)), -7, 12, 2, SPIN_ARM, 60),
    (dict(l=(-8, 2, 4), r=(8, -2, 4)), -3, 5, 0, (25, 25, 25), 100),
]
SPIN_ARM_L = (-5, 8, 70)        # револьвер отведён в сторону, против клинка

# Раунд 9, собрано на скелете. Строка: ступни l и r (y, z), таз, наклон, рука-протез, мс.
_ARM = (5, 45, 8)
MOTION = {
    # разгон: наклон вперёд, толчок
    "run_start": [((-6, 4), (10, 6), -4, 16, _ARM, 50), ((-14, 6), (16, 4), -5, 20, (15, 50, 10), 50), ((-18, 12), (18, 4), -3, 14, (25, 55, 12), 50)],
    # торможение: упор передней ногой, корпус назад
    "run_stop": [((-8, 8), (20, 4), -4, 2, (20, 40, 12), 60), ((-4, 4), (22, 4), -6, -8, (30, 30, 14), 70), ((0, 4), (14, 4), -4, -3, (15, 25, 10), 60)],
    # приземление и присед на взлёте: глубоко, средне, почти встал
    "land": [((3, 4), (-2, 4), -14, 14, (0, 50, 10), 60), ((3, 4), (-2, 4), -9, 9, _ARM, 60), ((3, 4), (-2, 4), -4, 4, (0, 30, 6), 60)],
}
# Смена оружия: рука уходит к груди, в середине протез перестраивается (за клубом пара), возвращается.
SWITCH = [((20, 40, 8), 50), ((50, 70, 10), 60), ((65, 85, 12), 60), ((50, 60, 10), 60), ((20, 30, 6), 50)]

# Точки привязки эффектов (координаты покоя, кость): дуло, выброс гильз, вытяжка пара, острие и основание лезвия.
ANCHORS = {
    "muzzle": ("farm_r", (16.2, 3.9, 40.5)), "breech": ("farm_r", (16.05, 3.0, 48.0)),
    "eject": ("farm_r", (20.4, 1.6, 54.0)),
    "vent": ("farm_r", (20.6, -1.0, 53.6)), "hose_top": ("uarm_r", (14.8, -3.6, 75.5)),
    "blade_tip": ("farm_r", tuple(hr.WRIST_R + hr.FA_DIR * 25.0)), "blade_base": ("farm_r", tuple(hr.WRIST_R + hr.FA_DIR * 3.0)),
    "sickle_tip": ("farm_r", tuple(hr.flip_fa(hr.SICKLE_C + hr.SICKLE_R * np.array([0, math.cos(math.radians(338)), math.sin(math.radians(338))])))),
    "sickle_base": ("farm_r", tuple(hr.flip_fa(hr.SICKLE_C + hr.SICKLE_R * np.array([0, math.cos(math.radians(200)), math.sin(math.radians(200))])))),
}
PISTOL_ANCHORS = {"pmuzzle": ("farm_l", tuple(hr.PISTOL_MUZZLE)),
                  "pbreech": ("farm_l", tuple(hr.PISTOL_GRIP + (np.array([-14.2, 4.9, 41.6]) - hr.PISTOL_GRIP) * hr.PISTOL_SCALE))}


# ---------- источники поз ----------
def source(name):
    """-> (позы, длительности мс, доп. сведения)."""
    if name == "idle":
        # дыхание (раунд 9): плечи и таз на долю пикселя, цикл 6 кадров
        poses = []
        for i in range(6):
            k = math.sin(2 * math.pi * i / 6)
            poses.append(hr.make_pose({"l": (-7.0, 2.0, 4.0), "r": (7.0, -1.0, 4.0)}, bob=-0.6 - 0.7 * k, lean=1.2 * k,
                                      arm_l=(0, 0), arm_r=(1.5 * k, 2 + 2.5 * k)))
        return poses, [170] * 6, {}
    if name in MOTION:
        poses = [hr.make_pose({"l": (-6.0, ly, lz), "r": (6.0, ry, rz)}, bob=bob, lean=ln, arm_l=(0, 0), arm_r=ar)
                 for (ly, lz), (ry, rz), bob, ln, ar, _ in MOTION[name]]
        return poses, [row[-1] for row in MOTION[name]], {}
    if name == "switch":
        poses = [hr.make_pose(attacks.STANCE, bob=0.0, arm_l=(0, 0), arm_r=ar) for ar, _ in SWITCH]
        return poses, [ms for _, ms in SWITCH], {}
    if name == "hook":
        # упор на притяжении (раунд 9): корпус назад, рука рвёт цепь на себя
        poses, root = attacks.build_melee(name, attacks.MOVES[name])
        poses[3] = hr.make_pose(attacks.STANCE, bob=-1.0, lean=-10, twist=-8, arm_l=(0, 0), arm_r=(15, 80, 10))
        return poses, [d for _, d in attacks.MOVES[name]["keys"]], {}
    if name == "run":
        return attacks.run_poses(), [attacks.RUN_MS] * len(attacks.RUN_FRAMES), {"fps": round(1000 / attacks.RUN_MS, 2)}
    if name in hr.GAIT:
        g = hr.GAIT[name]
        f = hr.pose_gait(name)
        return [f(i / g["frames"]) for i in range(g["frames"])], [round(1000 / g["fps"])] * g["frames"], {"fps": g["fps"]}
    if name in GUN:
        poses = [hr.make_pose(attacks.STANCE, bob=0.0, lean=ln, twist=tw, arm_l=(0, 0), arm_r=arm)
                 for arm, ln, tw, _ in GUN[name]]
        return poses, [ms for *_, ms in GUN[name]], {}
    if name in MOVING_GUN:
        _, state, gait = name.split("_")
        if state == "aim":
            poses, durs, _ = source(gait)
            poses = list(poses)
            for b in poses:
                hr.set_arm(b, "r", AIM_R)
            return poses, durs, {}
        poses = [hr.make_pose(attacks.STANCE, bob=0.0, lean=GAIT_LEAN[gait] + ln, twist=tw, arm_l=(0, 0), arm_r=arm)
                 for arm, ln, tw, _ in GUN["gun_shoot"]]
        return poses, [ms for *_, ms in GUN["gun_shoot"]], {}
    if name in attacks.SLAM_SPEC:
        poses, durs = attacks.slam_poses(name)
        return poses, durs, {"impact": attacks.SLAM_IMPACT}
    if name == "ult_spin":
        poses = [hr.make_pose({k: tuple(v) for k, v in ft.items()}, bob=bob, lean=ln, twist=tw, arm_l=(0, 0), arm_r=ar)
                 for ft, bob, ln, tw, ar, _ in SPIN]
        return poses, [row[-1] for row in SPIN], {}
    if name == "dash":
        poses = [hr.make_pose({k: tuple(v) for k, v in ft.items()}, bob=bob, lean=ln, arm_l=al, arm_r=ar)
                 for ft, bob, ln, al, ar, _ in DASH]
        return poses, [row[-1] for row in DASH], {}
    spec = attacks.ATTACKS.get(name) or attacks.MOVES[name]
    poses, root = attacks.build_melee(name, spec)
    return poses, [d for _, d in spec["keys"]], {"hit": spec["hit"], "chain": spec.get("chain", [0]), "root_m": root}


def pelvis_offset(bones):
    """Смещение груди от точки покоя (в координатах тела): по нему корпус следует за ногами."""
    return bones["chest"][1] - hr.J["chest"]


def anchored(bones):
    """Корпус и руки с грудью в точке покоя."""
    off = pelvis_offset(bones)
    out = dict(bones)
    for k in ("chest", "uarm_l", "farm_l", "uarm_r", "farm_r", "head"):
        if k not in bones:
            continue
        R, jp, jr = bones[k]
        out[k] = (R, jp - off, jr)
    return out


def screen_offset(off, alpha_deg):
    """Смещение в пикселях экрана (x вправо, y вверх) для ракурса."""
    a = math.radians(alpha_deg)
    ca, sa = math.cos(a), math.sin(a)
    rot = np.array([[ca, sa, 0], [-sa, ca, 0], [0, 0, 1]])
    w = rot.T @ off
    Rv = np.array([-1.0, 0, 0])
    Uv = np.array([0, -math.sin(hr.PITCH), math.cos(hr.PITCH)])
    return [int(round(float(w @ Rv))), int(round(float(w @ Uv)))]


# ---------- задания ----------
def job_legs(src, d):
    poses, *_ = source(src)
    hr.configure("legs", None)
    for i, b in enumerate(poses):
        hr.compose(*hr.render(hr.DIRS[d], b)).save(os.path.join(RENDER, f"L_{src}_{d}_{i}.png"))
    return f"L_{src}_{d}"


def job_upper(name, src, module, d, head=0.0):
    poses, *_ = source(src)
    if module.endswith("_noarm"):
        hr.configure("upper_noarm", module[:-6])
    else:
        hr.configure("upper", module)
    for i, b in enumerate(poses):
        a = anchored(b)
        if head:
            hr.turn_head(a, head)          # раунд 12: голова в сторону наведённой руки
        hr.compose(*hr.render(hr.DIRS[d], a)).save(os.path.join(RENDER, f"U_{name}_{d}_{i}.png"))
    return f"U_{name}_{d}"


def pistol_states(src, i):
    """Позы левой руки на кадр корпуса: готовая поза зависит от движения, выстрел и отдача общие."""
    if src in ("run", "gun_aim_run"):
        return [attacks.run_arm_l()[i]] + PISTOL[1:]
    if src == "ult_spin" and 1 <= i <= 4:
        return [SPIN_ARM_L] + PISTOL[1:]
    return PISTOL


def job_arm(src, d):
    poses, *_ = source(src)
    for i, b in enumerate(poses):
        a = anchored(b)
        hr.configure("core", "blade")
        core_tt = hr.render(hr.DIRS[d], a)[4]
        hr.configure("arm", "blade")
        for k, pose_l in enumerate(pistol_states(src, i)):
            hr.set_arm(a, "l", pose_l)
            ramp, shade, fixed, part, tt = hr.render(hr.DIRS[d], a)
            hidden = core_tt < tt - 0.3          # рука за торсом — вырезаем
            part = part.copy()
            tt = tt.copy()
            part[hidden] = -1
            tt[hidden] = np.inf
            hr.compose(ramp, shade, fixed, part, tt).save(os.path.join(RENDER, f"A_{src}_{d}_{i * 4 + k}.png"))
    return f"A_{src}_{d}"


def aim_pose(kind, yaw, kick):
    a = aim_base()
    if kind == "pistol":
        hr.aim_arm(a, "l", yaw, up=84.0 + kick, bend=6.0)
    else:
        hr.aim_arm(a, "r", yaw, up=86.0 + kick, bend=2.0)
    return a


def core_union(d):
    """Глубина торса по всем позам, поверх которых рука наводится (покой, бег, прицел на бегу, голова +-12°),
    с запасом 1 px: рука не просвечивает сквозь голову ни на одном корпусе (раунд 12)."""
    hr.configure("core", "shotgun")
    poses = [aim_base()]
    for src in ("idle", "run", "gun_aim_run"):
        poses += [anchored(b) for b in source(src)[0]]
    turned = []
    for b in poses:
        for y in (-12.0, 12.0):
            t = dict(b)
            hr.turn_head(t, y)
            turned.append(t)
    tt = None
    for b in poses + turned:
        t = hr.render(hr.DIRS[d], b)[4]
        tt = t if tt is None else np.minimum(tt, t)
    out = tt.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        out = np.minimum(out, np.roll(np.roll(tt, dy, 0), dx, 1))
    return out


def job_aim_arm(kind, d):
    """Лист наведённой руки: кадр = направление x состояние, части за торсом вырезаны."""
    kicks = PISTOL_AIM_KICK if kind == "pistol" else SG_AIM_KICK
    core_tt = core_union(d)
    hr.configure("arm" if kind == "pistol" else "arm_r", "shotgun")
    pre = "A_aim" if kind == "pistol" else "S_aim"
    for o, yaw in enumerate(AIM_OFFSETS):
        for k, kick in enumerate(kicks):
            ramp, shade, fixed, part, tt = hr.render(hr.DIRS[d], aim_pose(kind, yaw, kick))
            hidden = core_tt < tt - 0.3
            part = part.copy()
            tt = tt.copy()
            part[hidden] = -1
            tt[hidden] = np.inf
            hr.compose(ramp, shade, fixed, part, tt).save(os.path.join(RENDER, f"{pre}_{d}_{o * len(kicks) + k}.png"))
    return f"{pre}_{d}"


def job_reload(src, d):
    poses, *_ = source(src)
    for i, b in enumerate(poses):
        a = anchored(b)
        hr.configure("core", "blade")
        core_tt = hr.render(hr.DIRS[d], a)[4]
        hr.configure("arm", "blade")
        for k, pose_l in enumerate(PISTOL_RELOAD):
            hr.set_arm(a, "l", pose_l)
            ramp, shade, fixed, part, tt = hr.render(hr.DIRS[d], a)
            hidden = core_tt < tt - 0.3
            part = part.copy()
            tt = tt.copy()
            part[hidden] = -1
            tt[hidden] = np.inf
            hr.compose(ramp, shade, fixed, part, tt).save(os.path.join(RENDER, f"R_{src}_{d}_{i * 3 + k}.png"))
    return f"R_{src}_{d}"


def project(bones, bone, p_rest, alpha_deg):
    """Точка детали в позе -> пиксель холста слоя (x вправо, y вниз; стопы — PIVOT)."""
    R, jp, jr = bones[bone]
    p = R @ (np.array(p_rest, float) - jr) + jp
    a = math.radians(alpha_deg)
    ca, sa = math.cos(a), math.sin(a)
    w = np.array([[ca, sa, 0], [-sa, ca, 0], [0, 0, 1]]).T @ p
    u = float(w @ np.array([-1.0, 0, 0]))
    v = float(w @ np.array([0, -math.sin(hr.PITCH), math.cos(hr.PITCH)]))
    return [round(hr.PIVOT[0] + u, 1), round(hr.PIVOT[1] - v, 1)]


# След удара (правка 1, раунд 2): слой X_ на том же холсте, что и корпус.
TRAIL_PAD = 0
TRAIL_LOOK = {  # цвета следа: (кромка, тело, сердцевина), сколько кадров назад тянется след
    "blade_quick": (("6b6578", "c4bfcc", "ece8ee"), 1), "blade_heavy": (("4a4558", "948ea0", "ece8ee"), 2),
    "sickle_quick": (("6b6578", "c4bfcc", "ece8ee"), 1), "sickle_heavy": (("4a4558", "948ea0", "ece8ee"), 2),
    "blade_air_quick": (("6b6578", "c4bfcc", "ece8ee"), 1), "blade_air_heavy": (("4a4558", "948ea0", "ece8ee"), 2),
    "sickle_air_quick": (("6b6578", "c4bfcc", "ece8ee"), 1), "sickle_air_heavy": (("4a4558", "948ea0", "ece8ee"), 2),
}


def job_spin_trail(d):
    """След вращения: серп по пути кончика клинка за последние 70 градусов; что за спиной героя, не рисуем поверх него."""
    from PIL import Image, ImageDraw
    poses, *_ = source("ult_spin")
    a0 = hr.DIRS[d]
    tip, base = ANCHORS["blade_tip"][1], ANCHORS["blade_base"][1]
    pal = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,) for h in ("4a4558", "948ea0", "ece8ee")]
    fwd = np.array([0, -math.cos(hr.PITCH), -math.sin(hr.PITCH)])

    def behind(ab, alpha):
        R, jp, jr = ab["farm_r"]
        p = R @ (np.array(tip, float) - jr) + jp
        a = math.radians(alpha)
        ca, sa = math.cos(a), math.sin(a)
        return float((np.array([[ca, sa, 0], [-sa, ca, 0], [0, 0, 1]]).T @ p) @ fwd) > 0

    for i, b in enumerate(poses):
        im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        if 1 <= i <= 4:
            dr = ImageDraw.Draw(im)
            ab = anchored(b)
            steps = [k * 10 for k in range(8)]                 # назад по вращению: движок идёт по строкам вперёд
            for j, (k0, k1) in enumerate(zip(steps, steps[1:])):
                a1, a2 = a0 - k0, a0 - k1
                t1, b1 = project(ab, "farm_r", tip, a1), project(ab, "farm_r", base, a1)
                t2, b2 = project(ab, "farm_r", tip, a2), project(ab, "farm_r", base, a2)
                if behind(ab, a1) and abs(t1[0] - 64) < 18:
                    continue
                m1 = [(t1[0] * 2 + b1[0]) / 3, (t1[1] * 2 + b1[1]) / 3]
                m2 = [(t2[0] * 2 + b2[0]) / 3, (t2[1] * 2 + b2[1]) / 3]
                dr.polygon([tuple(t1), tuple(t2), tuple(m2), tuple(m1)], fill=pal[0 if j > 3 else 1])
                if j < 4:
                    dr.line([tuple(t1), tuple(t2)], fill=pal[2], width=1)
        im.save(os.path.join(RENDER, f"X_ult_spin_{d}_{i}.png"))
    return f"X_ult_spin_{d}"


def job_trail(name, d):
    from PIL import Image, ImageDraw
    poses, *_ = source(name)
    spec = attacks.ATTACKS[name]
    kind = "blade" if name.startswith("blade") else "sickle"
    a = hr.DIRS[d]
    pts = []
    for b in poses:
        ab = anchored(b)
        pts.append((project(ab, "farm_r", ANCHORS[kind + "_tip"][1], a), project(ab, "farm_r", ANCHORS[kind + "_base"][1], a)))
    cols, back = TRAIL_LOOK[name]
    pal = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,) for h in cols]
    active = set()
    for h in spec["hit"]:
        active |= {h - 1, h, h + 1}
        if name in attacks.TWIST_KEEP:
            active.add(h - 2)                                   # раунд 10: у серпа взмах разложен на больше кадров
    for i in range(len(poses)):
        im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        if i in active and i >= 1:
            dr = ImageDraw.Draw(im)
            sh = lambda q: (q[0] + TRAIL_PAD, q[1] + TRAIL_PAD)
            for k in range(back, 0, -1):                       # старые отрезки — кромкой, новый — телом
                j0, j1 = max(i - k, 0), i - k + 1
                (t0, b0), (t1, b1) = pts[j0], pts[j1]
                mid0 = [(t0[0] + b0[0]) / 2, (t0[1] + b0[1]) / 2]
                mid1 = [(t1[0] + b1[0]) / 2, (t1[1] + b1[1]) / 2]
                dr.polygon([sh(mid0), sh(t0), sh(t1), sh(mid1)], fill=pal[0 if k > 1 else 1])
            (t0, _), (t1, _) = pts[i - 1], pts[i]
            dr.line([sh(t0), sh(t1)], fill=pal[2], width=1)       # острая кромка по пути острия
        im.save(os.path.join(RENDER, f"X_{name}_{d}_{i}.png"))
    return f"X_{name}_{d}"


MOVE_SRC = ["dash", "jump"]
ULT_SRC = ["ult_spin", "hook"]
SLAM_SRC = list(attacks.SLAM_SPEC)
LEG_SRC = ["idle", "walk", "run"] + list(attacks.MELEE) + MOVE_SRC + SLAM_SRC + ["ult_spin"] + list(MOTION)
ARM_SRC = ["idle", "walk", "run"] + list(GUN) + MOVING_GUN + list(attacks.ATTACKS) + MOVE_SRC + SLAM_SRC + ULT_SRC + list(MOTION) + ["switch"]
# перезарядка револьвера на всех корпусах (раунд 5), кроме ходьбы: героя водит бег
RELOAD_SRC = [s for s in ARM_SRC if "walk" not in s]
UPPER = ([(f"{s}_{m}", s, m) for m in MODULES for s in ["idle", "walk", "run"] + MOVE_SRC + list(MOTION) + ["switch"]]
         + [(g, g, "shotgun") for g in list(GUN) + MOVING_GUN]
         + [(n, n, MELEE_MODULE[n]) for n in attacks.ATTACKS]
         + [("slam_blade", "slam", "blade"), ("slam_sickle", "slam", "sickle"), ("slam_shotgun", "slam_gun", "shotgun"),
            ("ult_spin", "ult_spin", "blade"), ("hook_aim", "hook", "sickle"), ("hook", "hook", "sickle_bare")]
         + [(n + "_noarm", n, "shotgun_noarm") for n in NOARM])


def build_meta():
    meta = {"canvas": [hr.W, hr.H], "pivot": list(hr.PIVOT), "dirs": list(hr.DIRS),
            "pistol_ms": PISTOL_MS, "pistol_reload": {"ms": PISTOL_RELOAD_MS, "seq": PISTOL_RELOAD_SEQ, "states": len(PISTOL_RELOAD), "src": RELOAD_SRC},
            "legs": {}, "upper": {}, "arm": {}}
    cache = {}
    for src in sorted(set(LEG_SRC + ARM_SRC)):
        cache[src] = source(src)
    for src in LEG_SRC:
        poses, durs, extra = cache[src]
        offs = {d: [screen_offset(pelvis_offset(b), a) for b in poses] for d, a in hr.DIRS.items()}
        meta["legs"][src] = dict(frames=len(poses), durations_ms=durs, offsets_px=offs, **extra)
    for name, src, module in UPPER:
        poses, durs, extra = cache[src]
        anchors = {}
        for d, a in hr.DIRS.items():
            anchors[d] = [{k: project(anchored(b), bone, pt, a) for k, (bone, pt) in ANCHORS.items()} for b in poses]
        meta["upper"][name] = dict(src=src, module=module, frames=len(poses), durations_ms=durs, anchors=anchors,
                                   trail=name in attacks.ATTACKS or name == "ult_spin",
                                   **{k: v for k, v in extra.items() if k in ("hit", "chain", "impact")})
    for src in ARM_SRC:
        poses = cache[src][0]
        anchors = {}
        for d, a in hr.DIRS.items():
            row = []
            for b in poses:
                ab = anchored(b)
                hr.set_arm(ab, "l", PISTOL[1])            # точка дула в кадре выстрела
                row.append({k: project(ab, bone, pt, a) for k, (bone, pt) in PISTOL_ANCHORS.items()})
            anchors[d] = row
        meta["arm"][src] = dict(frames=len(poses), states=len(PISTOL), anchors=anchors)
    for n, _, _, _, base in HEAD_UPPER:
        meta["upper"][n] = dict(meta["upper"][base])
    meta["trail_pad"] = TRAIL_PAD
    aim = {"offsets": AIM_OFFSETS, "pistol": {"states": len(PISTOL_AIM_KICK), "anchors": {}},
           "shotgun": {"states": len(SG_AIM_KICK), "frame_state": SG_FRAME_STATE, "anchors": {}}}
    for d, a in hr.DIRS.items():
        aim["pistol"]["anchors"][d] = [{k: project(aim_pose("pistol", y, kk), bone, pt, a) for k, (bone, pt) in PISTOL_ANCHORS.items()}
                                       for y in AIM_OFFSETS for kk in PISTOL_AIM_KICK]
        aim["shotgun"]["anchors"][d] = [{k: project(aim_pose("shotgun", y, kk), bone, pt, a) for k, (bone, pt) in ANCHORS.items()}
                                        for y in AIM_OFFSETS for kk in SG_AIM_KICK]
    meta["aim_arm"] = aim
    return meta


def main(kinds, only=None):
    """only — множество имён (анимаций или источников), которые перерендерить; None — все."""
    os.makedirs(RENDER, exist_ok=True)
    ok = lambda n: only is None or n in only
    jobs = []
    with ProcessPoolExecutor(max_workers=max(1, (os.cpu_count() or 2) - 1)) as ex:
        for d in hr.DIRS:
            if "legs" in kinds:
                jobs += [ex.submit(job_legs, s, d) for s in LEG_SRC if ok(s)]
            if "upper" in kinds:
                jobs += [ex.submit(job_upper, n, s, m, d) for n, s, m in UPPER if ok(n)]
                jobs += [ex.submit(job_upper, n, s, m, d, y) for n, s, m, y, _ in HEAD_UPPER if ok(n)]
            if "arm" in kinds:
                jobs += [ex.submit(job_arm, s, d) for s in ARM_SRC if ok(s)]
            if "reload" in kinds:
                jobs += [ex.submit(job_reload, s, d) for s in RELOAD_SRC if ok(s)]
            if "aim" in kinds:
                jobs += [ex.submit(job_aim_arm, k, d) for k in ("pistol", "shotgun") if ok("aim_" + k)]
            if "trail" in kinds:
                jobs += [ex.submit(job_trail, n, d) for n in attacks.ATTACKS if ok(n)]
                if ok("ult_spin"):
                    jobs.append(ex.submit(job_spin_trail, d))
        for k, j in enumerate(jobs):
            j.result()
            if k % 20 == 0:
                print(f"{k + 1}/{len(jobs)}", flush=True)
    meta = build_meta()
    with open(os.path.join(OUT, "layers.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    print("готово:", len(jobs), "заданий")


if __name__ == "__main__":
    args = sys.argv[1:]
    only = next((set(a[5:].split(",")) for a in args if a.startswith("only=")), None)
    kinds = [a for a in args if not a.startswith("only=")] or ["legs", "upper", "arm", "reload", "trail", "aim"]
    main(kinds, only)
