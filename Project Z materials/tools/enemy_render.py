"""Противник для теста (раунд 2, правка 5): обычный человек — рабочий. Тот же скелет, SDF и рендер, что у героя.

Расчленёнка: модель режется плоскостями в координатах покоя (срез закрашивается мясом, в центре — кость),
выстрел в упор вычитает сферу из груди, серп вспарывает живот (кишки — отдельная деталь).

Выход (art/enemy/render):
  E_idle, E_walk (8), E_flinch (2)   живой, 64x96, стопы в (32,93), 8 направлений
  C_<исход>_<падение>  труп (раунд 6): падение на спину, вперёд, влево, вправо; 4 кадра падения + лежит,
             192x192, точка на полу в центре, 8 направлений
  обгоревшие листы <имя>_s делает tools/enemy_scorch.py: те же кадры, цвета перекрашены таблицей по палитре (раунд 7)
  P_<кусок>  отлетающий кусок: 8 кадров кувырка, 48x48, центр куска в центре
  E_air_*    живой в воздухе (раунд 4): подброс, висит, удар, падение; 128x128, стопы в (64,125), таз на месте
  T_<исход>  тело, убитое в воздухе: 8 кадров кувырка с тем же исходом, 128x128, центр тела в центре
  enemy.json — кадры, длительности, исходы

python tools/enemy_render.py        # всё
python tools/enemy_render.py air    # только воздух и описание
python tools/enemy_render.py corpse # только трупы и описание
"""
import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hero_render as hr  # noqa: E402
import mocap  # noqa: E402

OUT = os.path.join(HERE, "..", "art", "enemy")
RENDER = os.path.join(OUT, "render")
J = hr.J

# у человека правая рука как левая (у героя справа протез)
J["sh_r"], J["el_r"], J["wr_r"] = np.array([12.6, 0.3, 77.5]), np.array([14.8, 0.8, 64.0]), np.array([14.6, 2.2, 52.0])

hr.RAMPS.update({
    "shirt": ["322e40", "4a4558", "6b6578", "948ea0", "c4bfcc"],
    "vest": ["0b0a10", "15131d", "3b1f28", "6e3440"],
    "trou": ["0b0a10", "15131d", "3b1f28", "4a3a1c"],
    "meat": ["2a0509", "4f0a12", "7d0f1c", "b3162a", "e02a3c"],
    "gut": ["4f0a12", "6e3440", "a35a5a", "d49a86", "f0cdb4"],
    "char": ["0b0a10", "15131d", "211e2c", "322e40"],
})
hr.SHADE.update({"shirt": (1, 4), "vest": (1, 3), "trou": (1, 3), "meat": (1, 4), "gut": (1, 3)})
hr.SPEC.update({"meat": 4, "gut": 4})


def hand(p, s):
    d = hr.capsule(p, (s * 14.5, 2.4, 50.5), (s * 14.2, 3.0, 44.5), 2.4, 2.1)
    return hr.smin(d, hr.sphere(p, (s * 12.9, 4.4, 47.5), 1.2), 0.8)


def cap(p):
    crown = hr.ellipsoid(p, (0, -0.3, 98.6), (6.4, 6.9, 2.9))
    crown = np.maximum(crown, 96.9 - p[:, 2])
    visor = hr.obox(p, (0, 3.5, 97.3), (0, 9.8, 96.6), (1, 0, 0), 4.4, 0.45)
    return np.minimum(crown, visor)


GUT_PTS = [(-3.5, 6.2, 55.5), (1.0, 8.6, 56.5), (3.8, 7.4, 53.0), (0.0, 9.6, 51.5), (-3.0, 8.0, 49.0),
           (1.5, 10.2, 47.0), (3.5, 8.5, 44.0)]


def guts(p):
    d = None
    for a, b in zip(GUT_PTS, GUT_PTS[1:]):
        di = hr.capsule(p, a, b, 1.5)
        d = di if d is None else np.minimum(d, di)
    return d - 0.25 * np.sin(p[:, 0] * 2.1) * np.sin(p[:, 2] * 1.7)


LIMB_AXES = {"arm_l": ("sh_l", "el_l"), "farm_l": ("el_l", "wr_l"), "arm_r": ("sh_r", "el_r"), "farm_r": ("el_r", "wr_r"),
             "leg_r": ("hip_r", "knee_r")}

BASE = [
    ("boot_l", "boot", "shin_l", lambda p: hr.boot_at(p, J["ankle_l"]), True),
    ("boot_r", "boot", "shin_r", lambda p: hr.boot_at(p, J["ankle_r"]), True),
    ("blouse_l", "trou", "shin_l", lambda p: hr.blouse_at(p, J["ankle_l"]), False),
    ("blouse_r", "trou", "shin_r", lambda p: hr.blouse_at(p, J["ankle_r"]), False),
    ("leg_l", "trou", "thigh_l", lambda p: hr.thigh_at(p, J["hip_l"] * [0.75, 1, 1], J["knee_l"]), False),
    ("leg_r", "trou", "thigh_r", lambda p: hr.thigh_at(p, J["hip_r"] * [0.75, 1, 1], J["knee_r"]), False),
    ("torso", "shirt", "chest", hr.torso, False),
    ("neck", "skin", "chest", lambda p: hr.capsule(p, (0, 0.6, 83), (0, 0.8, 89), 3.4), False),
    ("head", "skin", "chest", hr.head, False),
    ("hair", "hair", "chest", hr.hair, False),
    ("cap", "cloth", "chest", cap, False),
    ("arm_l", "shirt", "uarm_l", lambda p: hr.sleeve_up(p, J["sh_l"], J["el_l"]), False),
    ("farm_l", "skin", "farm_l", lambda p: hr.capsule(p, J["el_l"], J["wr_l"], 3.0, 2.6), False),
    ("hand_l", "skin", "farm_l", lambda p: hand(p, -1), False),
    ("arm_r", "shirt", "uarm_r", lambda p: hr.sleeve_up(p, J["sh_r"], J["el_r"]), False),
    ("farm_r", "skin", "farm_r", lambda p: hr.capsule(p, J["el_r"], J["wr_r"], 3.0, 2.6), False),
    ("hand_r", "skin", "farm_r", lambda p: hand(p, 1), False),
    ("guts", "gut", "chest", guts, False),
]
UPPER_BODY = {"torso", "neck", "head", "hair", "cap", "arm_l", "farm_l", "hand_l", "arm_r", "farm_r", "hand_r", "guts"}
HEAD = {"head", "hair", "cap", "neck"}
ARM_R, ARM_L = {"arm_r", "farm_r", "hand_r"}, {"arm_l", "farm_l", "hand_l"}

# Плоскость косого разреза тяжёлым клинком: от правого плеча к левому бедру.
SPLIT_N, SPLIT_C = np.array([0.814, 0.0, -0.581]), -38.4
CRATER = (np.array([0.0, 7.0, 69.0]), 7.5)
CRUSH = (np.array([0.0, 3.0, 82.0]), 10.0)       # раздавленная грудь и шея
STAB = (np.array([0.0, 7.0, 68.0]), 4.0)         # пробитая грудь
LEG_CUT, WAIST_CUT = 36.0, 57.0


# ---------- исходы ----------
# cut: (детали, нормаль, c, рваный край) — оставляем n·p - c <= 0; drop — детали убраны; crater — выбоина
def outcome(name):
    up, down = np.array([0, 0, 1.0]), np.array([0, 0, -1.0])
    if name == "intact":
        return dict(drop=set() | {"guts"}, cuts=[])
    if name == "decap":
        return dict(drop={"head", "hair", "cap", "guts"}, cuts=[({"neck"}, up, 86.0, 0.0)])
    if name == "arm_off_r":
        return dict(drop={"farm_r", "hand_r", "guts"}, cuts=[({"arm_r"}, down, -74.0, 0.0)])
    if name == "split":   # левая рука целиком уходит с верхней половиной
        return dict(drop={"guts"} | ARM_L, cuts=[(UPPER_BODY - ARM_L, -SPLIT_N, -SPLIT_C, 0.0)])
    if name == "gut":
        return dict(drop={"farm_l", "hand_l"}, cuts=[({"arm_l"}, down, -74.0, 0.9)], gash=True)
    if name == "blast":
        return dict(drop={"head", "hair", "cap", "farm_r", "hand_r", "guts"},
                    cuts=[({"neck"}, up, 85.0, 1.2), ({"arm_r"}, down, -74.0, 1.2)], crater=CRATER)
    if name == "arm_off_l":
        return dict(drop={"farm_l", "hand_l", "guts"}, cuts=[({"arm_l"}, down, -74.0, 0.0)])
    if name == "leg_off":
        return dict(drop={"boot_r", "blouse_r", "guts"}, cuts=[({"leg_r"}, down, -LEG_CUT, 0.8)])
    if name == "waist":   # остаются ноги: верх улетает куском torso_top
        return dict(drop=UPPER_BODY - {"torso"}, cuts=[({"torso"}, up, WAIST_CUT, 1.0)])
    if name == "crush":
        return dict(drop={"head", "hair", "cap", "guts"}, cuts=[({"neck"}, up, 84.0, 1.4)], crater=CRUSH)
    if name == "stab":
        return dict(drop={"guts"}, cuts=[], crater=STAB)
    raise KeyError(name)


PIECES = {  # кусок: (детали, разрезы, центр куска в координатах покоя)
    "head": (HEAD, [({"neck"}, np.array([0, 0, -1.0]), -86.0, 0.0)], (0, 1.5, 93.0)),
    "arm_r": (ARM_R, [({"arm_r"}, np.array([0, 0, 1.0]), 74.0, 0.0)], (14.6, 1.2, 62.0)),
    "arm_l": (ARM_L, [({"arm_l"}, np.array([0, 0, 1.0]), 74.0, 0.9)], (-14.6, 1.2, 62.0)),
    "upper_half": (UPPER_BODY - {"guts"}, [(UPPER_BODY - ARM_L, SPLIT_N, SPLIT_C, 0.0)], (-4.0, 0.5, 80.0)),
    "leg_r": ({"leg_r", "blouse_r", "boot_r"}, [({"leg_r"}, np.array([0, 0, 1.0]), LEG_CUT, 0.8)], (6.4, 0.6, 20.0)),
    "torso_top": (UPPER_BODY - {"guts"}, [({"torso"}, np.array([0, 0, -1.0]), -WAIST_CUT, 1.0)], (0.0, 0.5, 74.0)),
}

CUR = {"cuts": [], "crater": None, "gash": False}


def cut_val(p, n, c, rag):
    v = p @ n - c
    if rag:
        v = v + rag * np.sin(p[:, 0] * 2.3 + p[:, 1] * 1.7) * np.sin(p[:, 1] * 1.9 - p[:, 2] * 0.7)
    return v


def wrap(name, f):
    def g(p):
        d = f(p)
        for parts, n, c, rag in CUR["cuts"]:
            if name in parts:
                d = np.maximum(d, cut_val(p, n, c, rag))
        if CUR["crater"] is not None and name == "torso":
            ctr, r = CUR["crater"]
            d = np.maximum(d, -(hr.length(p - ctr) - r))
        return d
    return g


def setup(parts_keep=None, cuts=(), crater=None, gash=False, drop=(), noclip=False):
    CUR.update(cuts=list(cuts), crater=crater, gash=gash)
    hr.PARTS[:] = [(n, r, b, wrap(n, f), cl and not noclip) for n, r, b, f, cl in BASE
                   if n not in drop and (parts_keep is None or n in parts_keep)]
    hr.NAMES = np.array([n for n, *_ in hr.PARTS])
    hr.ACTIVE = list(range(len(hr.PARTS)))


def dist_seg(p, a, b):
    pa, ba = p - a, b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return hr.length(pa - h[:, None] * ba)


def paint(p, part, ramp, idx, fixed):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    name = hr.NAMES[part]

    def fix(m, hexc):
        fixed[m] = hr.PAL.index(hexc)

    t = name == "torso"
    # штаны до пояса, ремень, жилет с открытым воротом
    ramp[t & (z < 55.0)] = "trou"
    belt = t & (z >= 55.0) & (z < 57.0)
    ramp[belt] = "vest"
    idx[belt] = 1
    vest = t & (z >= 57.0) & (z < 80.5) & ~((np.abs(x) < 2.6) & (y > 2.0))
    ramp[vest] = "vest"
    fix(t & (z >= 60) & (z < 75) & (np.abs(x - 3.2) < 0.6) & (y > 2.0) & (np.round(z) % 5 == 0), "9a7a2e")
    # закатанные рукава: манжета у локтя
    for s in ("l", "r"):
        roll = (name == "arm_" + s) & (z < 66.5)
        idx[roll] = np.maximum(idx[roll] - 1, 0)
    # лицо: глаза, брови, усы
    h = name == "head"
    face = h & (y > 3.0)
    for s in (-1, 1):
        fix(face & (np.abs(x - s * 2.2) < 0.75) & (np.abs(z - 93.6) < 0.6), "15131d")
    ramp[h & (z > 90.9) & (z < 92.1) & (np.abs(x) < 2.8) & (y > 3.0)] = "hair"
    fix(face & (np.abs(z - 90.2) < 0.45) & (np.abs(x) < 1.1), "6e3440")

    # срезы: мясо, кость в центре конечности и позвоночник в шее
    for parts, n, c, rag in CUR["cuts"]:
        on = np.isin(name, list(parts)) & (np.abs(cut_val(p, n, c, rag)) < 0.9)
        ramp[on] = "meat"
        for limb, (a, b) in LIMB_AXES.items():
            bone = on & (name == limb) & (dist_seg(p, J[a], J[b]) < 1.0)
            fix(bone, "c4bfcc")
        fix(on & (name == "neck") & (np.hypot(x, y - 0.6) < 1.0), "c4bfcc")
        fix(on & (name == "torso") & (np.hypot(x, y + 3.5) < 1.0), "c4bfcc")
    if CUR["crater"] is not None:
        ctr, r = CUR["crater"]
        on = t & (np.abs(hr.length(p - ctr) - r) < 1.2)
        ramp[on] = "meat"
        fix(on & (np.abs(x) < 1.2) & (np.round(z) % 3 == 0), "c4bfcc")     # рёбра
    if CUR["gash"]:
        ramp[t & (y > 3.0) & (np.abs(x) < 4.8) & (z > 46.0) & (z < 58.0)] = "meat"


hr.paint = paint


# ---------- позы ----------
def rotate_bones(bones, R, pivot, t):
    pivot = np.array(pivot, float)
    return {k: (R @ Rb, R @ (jp - pivot) + pivot + t, jr) for k, (Rb, jp, jr) in bones.items()}


def pose_idle():
    return hr.make_pose({"l": (-7.0, 2.0, 4.0), "r": (7.0, -1.0, 4.0)}, bob=-0.5, arm_l=(4, 12, 4), arm_r=(4, 12, 4))


def pose_flinch(k):
    return hr.make_pose({"l": (-7.0, 1.0, 4.0), "r": (7.0, -3.0, 4.0)}, bob=-1.0 - k, lean=-10 + 4 * k,
                        twist=8 - 4 * k, arm_l=(28 - 10 * k, 45, 12), arm_r=(24 - 8 * k, 40, 12))


# Враг на цепи (раунд 9): его волочёт к герою, наклон вперёд; второй кадр — споткнулся на финише.
def pose_hooked(k):
    return hr.make_pose({"l": (-7.0, -10.0 - 4 * k, 5.0), "r": (7.0, 6.0 + 8 * k, 4.0)}, bob=-3.0 - 3 * k, lean=22 + 12 * k,
                        arm_l=(40 + 15 * k, 25, 16), arm_r=(35 + 20 * k, 25, 16))


FALL = [0, 25, 55, 80, 90]


def pose_dead(k):
    """Падение на спину: руки разлетаются в стороны и ложатся на пол."""
    return hr.make_pose({"l": (-8.0, 1.0, 4.0), "r": (8.0, -2.0, 4.0)}, bob=-1.0, lean=-6 * k,
                        arm_l=(20 - 30 * k, 25 - 15 * k, 20 + 45 * k), arm_r=(16 - 26 * k, 20 - 12 * k, 20 + 50 * k))


def pose_fall(i, forward=False):
    a = math.radians(FALL[i])
    s = FALL[i] / 90
    sign = -1 if forward else 1
    b = pose_dead(s)
    return rotate_bones(b, hr.rx(sign * a), (0, 0, 0), np.array([0, sign * 47.0 * s, 0]))


def pose_piece(center, k):
    b = pose_idle()
    R = hr.rx(math.radians(k * 45)) @ hr.rz(math.radians(20))
    return rotate_bones(b, R, center, -np.array(center, float))


# Живой в воздухе (раунд 4): кадры записей Mixamo, таз на постоянной высоте, подъём задаёт движок.
REFS = os.path.join(HERE, "..", "refs", "mixamo")
AIR = {
    "air_rise": ("hit_uppercut.dae", 0, [9, 12, 15], [90, 110, 150]),
    "air_hang": ("fall_midair_idle.dae", 0, [0, 12], [200, 200]),
    "air_hit": ("hit_uppercut.dae", 0, [15, 18], [80, 110]),
    "air_fall": ("fall_air_idle.dae", 0, [0, 6, 12, 18], [100, 100, 100, 100]),
}


def air_poses(name):
    src, face, frames, _ = AIR[name]
    b = mocap.load(os.path.join(REFS, src))
    rt = mocap.Retarget(b, 0, b.n - 1, yaw=("shoulders", face), pin=True)
    return [rt.pose(f) for f in frames]


TUMBLE_CENTER = (0.0, 0.5, 52.0)


def pose_tumble(k):
    """Вялое тело кувыркается вокруг центра: кадр k из 8."""
    b = hr.make_pose({"l": (-8.0, -4.0, 8.0), "r": (8.0, 6.0, 12.0)}, bob=-2.0,
                     arm_l=(25 + 15 * math.sin(k), 30, 40), arm_r=(35 - 15 * math.sin(k), 25, 45))
    R = hr.rx(math.radians(k * 45)) @ hr.rz(math.radians(15))
    return rotate_bones(b, R, TUMBLE_CENTER, -np.array(TUMBLE_CENTER))


OUTCOMES = ["intact", "decap", "arm_off_r", "split", "gut", "blast", "arm_off_l", "leg_off", "waist", "crush", "stab"]
# Падения (раунд 6): кадры записей Mixamo; у каждого исхода свои веса, движок выбирает случайно.
FALLS = {"back": ("death_back.dae", (6, 15, 24, 33, 48)), "forward": ("death_forward.dae", (9, 21, 27, 33, 45)),
         "left": ("death_left.dae", (45, 48, 51, 57, 81)), "right": ("death_right.dae", (42, 51, 57, 63, 90))}
FALL_WEIGHTS = {"stab": {"forward": 5, "left": 1, "right": 1}, "crush": {"forward": 4, "back": 1},
                "leg_off": {"right": 4, "forward": 2, "back": 1}, "arm_off_r": {"left": 3, "back": 2, "forward": 1},
                "arm_off_l": {"right": 3, "back": 2, "forward": 1}}
FALL_DEFAULT = {"back": 4, "forward": 2, "left": 1, "right": 1}
# у перерубленного ноги ещё стоят мгновение, потом падают
CORPSE_MS = {"waist": [700, 70, 80, 90, 1000]}


def fall_poses(fall):
    src, frames = FALLS[fall]
    b = mocap.load(os.path.join(REFS, src))
    rt = mocap.Retarget(b, 0, b.n - 1, yaw=0.0)
    return [rt.pose(f) for f in frames]


# ---------- задания ----------
def canvas(w, h, pivot):
    hr.W, hr.H, hr.PIVOT = w, h, pivot


def job_live(d):
    canvas(64, 96, (32, 93))
    setup(drop={"guts"})
    sets = {"idle": [pose_idle()], "walk": [hr.pose_gait("walk")(i / 8) for i in range(8)],
            "flinch": [pose_flinch(0), pose_flinch(1)], "hooked": [pose_hooked(0), pose_hooked(1)]}
    for n, poses in sets.items():
        for i, b in enumerate(poses):
            hr.compose(*hr.render(hr.DIRS[d], b)).save(os.path.join(RENDER, f"E_{n}_{d}_{i}.png"))
    return d


def job_air(d):
    canvas(128, 128, (64, 125))
    setup(drop={"guts"})
    for n in AIR:
        for i, b in enumerate(air_poses(n)):
            hr.compose(*hr.render(hr.DIRS[d], b)).save(os.path.join(RENDER, f"E_{n}_{d}_{i}.png"))
    return d


def job_tumble(o, d):
    canvas(128, 128, (64, 64))
    setup(noclip=True, **outcome(o))
    for k in range(8):
        hr.compose(*hr.render(hr.DIRS[d], pose_tumble(k))).save(os.path.join(RENDER, f"T_{o}_{d}_{k}.png"))
    return o + d


def job_corpse(o, fall, d):
    canvas(192, 192, (96, 96))     # лежащее тело длиннее 128 px: таз в центре, голова и ноги расходятся
    setup(**outcome(o))
    for i, b in enumerate(fall_poses(fall)):
        hr.compose(*hr.render(hr.DIRS[d], b)).save(os.path.join(RENDER, f"C_{o}_{fall}_{d}_{i}.png"))
    return o + fall + d


def job_piece(name):
    canvas(48, 48, (24, 24))
    parts, cuts, center = PIECES[name]
    setup(parts_keep=parts, cuts=cuts, noclip=True)
    for k in range(8):
        b = pose_piece(center, k)
        hr.compose(*hr.render(hr.DIRS["s"], b)).save(os.path.join(RENDER, f"P_{name}_s_{k}.png"))
    return name


def main(mode=""):
    """mode: air — только воздух; corpse — только трупы; пусто — всё. Описание пишется всегда."""
    os.makedirs(RENDER, exist_ok=True)
    with ProcessPoolExecutor(max_workers=max(1, (os.cpu_count() or 2) - 1)) as ex:
        jobs = []
        if mode == "live":
            jobs += [ex.submit(job_live, d) for d in hr.DIRS]
        if mode == "corpse":
            jobs += [ex.submit(job_corpse, o, fl, d) for o in OUTCOMES for fl in FALLS for d in hr.DIRS]
        if mode not in ("corpse", "meta", "live"):
            jobs += [ex.submit(job_air, d) for d in hr.DIRS]
            jobs += [ex.submit(job_tumble, o, d) for o in OUTCOMES for d in hr.DIRS]
        if not mode:   # meta — ничего не рендерить, только описание
            jobs += [ex.submit(job_live, d) for d in hr.DIRS]
            jobs += [ex.submit(job_corpse, o, fl, d) for o in OUTCOMES for fl in FALLS for d in hr.DIRS]
            jobs += [ex.submit(job_piece, n) for n in PIECES]
        for j in jobs:
            j.result()
    meta = {
        "live": {"idle": {"frames": 1, "durations_ms": [1000]}, "walk": {"frames": 8, "durations_ms": [100] * 8},
                 "flinch": {"frames": 2, "durations_ms": [90, 120]}, "hooked": {"frames": 2, "durations_ms": [150, 100]}},
        "corpse": {o: {"frames": 5, "durations_ms": CORPSE_MS.get(o, [60, 70, 80, 90, 1000]), "canvas": [192, 192],
                       "falls": FALL_WEIGHTS.get(o, FALL_DEFAULT)} for o in OUTCOMES},
        "pieces": {n: {"frames": 8, "canvas": [48, 48]} for n in PIECES},
        "air": {n: {"frames": len(v[2]), "durations_ms": v[3], "canvas": [128, 128]} for n, v in AIR.items()},
        "tumble": {o: {"frames": 8, "canvas": [128, 128]} for o in OUTCOMES},
        "walk_speed": hr.gait_speed("walk"),
    }
    with open(os.path.join(OUT, "enemy.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    print("противник готов:", len(jobs), "заданий")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
