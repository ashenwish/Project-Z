"""Боевые анимации героя: удары из Mixamo (ключевые кадры + длительности под вес оружия)
и стрельба, собранная на скелете героя. Все правые оружия — модули парового протеза.

Каждая анимация: список кадров (поза, длительность мс), кадры попадания/выстрела (hit),
смещение корпуса по кадрам (root, м) для движка. Выход: кадры PNG в render/ и <name>.json.

python tools/attacks.py art/hero/render                 # все
python tools/attacks.py art/hero/render blade_heavy     # выбранные
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_render as hr  # noqa: E402
import mocap  # noqa: E402

REFS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "refs", "mixamo")

# Удары: (кадр записи 30 fps, длительность мс). hit — номера кадров спрайта с попаданием.
# Тяжёлое оружие: долгий замах с удержанием, короткий удар, длинный хит-стоп.
# Лёгкое: короткий замах, удар без удержаний, быстрый возврат.
def combo(src, *parts):
    """Серия из отрезков: свой разворот лица у каждого (удар уходит вперёд) и сквозная нумерация кадров.
    Часть: dict(face=кадр записи, keys=[(кадр, мс)], hit=индекс кадра попадания внутри отрезка)."""
    keys, hit, chain, faces, srcs = [], [], [], [], []
    for p in parts:
        chain.append(len(keys))
        hit.append(len(keys) + p["hit"])
        faces += [p["face"]] * len(p["keys"])
        srcs += [p.get("src", src)] * len(p["keys"])    # у отрезка может быть своя запись
        keys += p["keys"]
    return dict(src=src, keys=keys, hit=hit, chain=chain, faces=faces, srcs=srcs, face=parts[0]["face"])


_WRIST_CACHE = {}


def _wrist_path(src):
    if src not in _WRIST_CACHE:
        b = mocap.load(os.path.join(REFS, src))
        rt = mocap.Retarget(b, 0, b.n - 1, yaw=0.0)
        _WRIST_CACHE[src] = [np.array(rt.joints(f)["wr_r"], float) for f in range(b.n)]
    return _WRIST_CACHE[src]


def _arc_frames(path, a, b, n):
    """n кадров записи на [a, b) с равным шагом по пути кисти: медленный замах — редко, взмах — часто."""
    seg = [0.0]
    for f in range(a, b):
        seg.append(seg[-1] + float(np.linalg.norm(path[f + 1] - path[f])))
    total = seg[-1] or 1.0
    out = []
    for i in range(n):
        want = total * i / n
        f = a + min(range(len(seg)), key=lambda k: abs(seg[k] - want))
        if not out or f > out[-1]:
            out.append(f)
    return out


def _fit_ms(gaps, total, lo=25, hi=120):
    """Длительности по времени записи между кадрами, ужатые до total мс, в пределах lo..hi."""
    k_lo, k_hi = 0.1, 200.0
    for _ in range(40):
        k = (k_lo + k_hi) / 2
        s = sum(min(max(g * k, lo), hi) for g in gaps)
        k_lo, k_hi = (k, k_hi) if s < total else (k_lo, k)
    return [int(round(min(max(g * k, lo), hi))) for g in gaps]


def arc(src, a, hit, b, n_pre, pre_ms, n_post, post_ms, face=None):
    """Отрезок удара (раунд 10): кадры по ровному шагу кисти, лицо по плечам в кадре попадания.
    До попадания n_pre кадров на pre_ms, попадание и возврат n_post кадров на post_ms."""
    path = _wrist_path(src)
    pre = _arc_frames(path, a, hit, n_pre)
    post = _arc_frames(path, hit, b, n_post - 1) + [b]      # отрезок кончается ровно в b
    frames = pre + post
    gaps = [frames[i + 1] - frames[i] for i in range(len(frames) - 1)] + [frames[-1] - frames[-2]]
    ms = _fit_ms(gaps[:len(pre)], pre_ms) + _fit_ms(gaps[len(pre):], post_ms)
    return dict(src=src, face=hit if face is None else face, hit=len(pre), keys=list(zip(frames, ms)))


def damp_twist(b, keep):
    """Поворот плеч из записи x keep: корпус и руки поворачиваются вокруг груди, ноги остаются (раунд 10)."""
    R, cp, _ = b["chest"]
    side = R @ np.array([1.0, 0.0, 0.0])
    yaw = float(np.arctan2(side[1], side[0]))
    Rz = hr.rz(-yaw * (1 - keep))
    pivot = np.array(cp, float)
    for k in ("chest", "uarm_l", "farm_l", "uarm_r", "farm_r"):
        Rk, pk, jr = b[k]
        b[k] = (Rz @ Rk, Rz @ (np.array(pk, float) - pivot) + pivot, jr)


MELEE = {
    # 1. паровой клинок, тяжёлый удар сверху вниз
    # (раунд 1: тяжёлые x0.7; раунд 3: ещё x0.8; кадр удара не трогаем)
    # раунд 8: вся серия на 10 % медленнее
    "blade_heavy": combo("melee_downward.dae",
        dict(face=24, hit=5, keys=[(0, 50), (9, 55), (15, 68), (18, 111), (21, 50), (24, 66), (27, 92), (33, 62), (45, 55), (57, 62)]),
        # раунд 7: тройка Т-Т-Т: мощный горизонтальный и вертикальный завершающий
        dict(src="heavy_gs_power.dae", face=24, hit=3, keys=[(12, 50), (18, 94), (21, 44), (24, 44), (27, 60), (36, 66)]),
        dict(src="heavy_twohand_combo.dae", face=66, hit=3, keys=[(54, 50), (60, 99), (63, 44), (66, 39), (69, 60), (87, 77), (96, 77)])),
    # 2. паровой клинок, лёгкая тройка Л-Л-Л (раунд 3): Sword And Shield Slash Combo, щита в записи нет на скелете
    "blade_quick": combo("sword_shield_combo.dae",
        dict(face=21, hit=3, keys=[(9, 45), (15, 50), (18, 35), (21, 35), (24, 45), (27, 60)]),
        dict(face=36, hit=2, keys=[(30, 45), (33, 40), (36, 35), (39, 40), (42, 60)]),
        dict(face=72, hit=4, keys=[(57, 45), (63, 50), (66, 50), (69, 40), (72, 35), (75, 45), (78, 60), (90, 70), (102, 70)])),
    # 3. серп, быстрая тройка (булава одной рукой)
    # раунд 10: было дёргано — кадры через 6-9 кадров записи, удар в начале взмаха, плечи ходили на +-130°.
    # Теперь кадры по ровному шагу кисти, попадание в середине взмаха, лицо по каждому удару, поворот плеч x0,45.
    "sickle_quick": combo("club_combo.dae",
        arc("club_combo.dae", 3, 20, 28, 5, 120, 4, 110),
        arc("club_combo.dae", 30, 45, 55, 5, 120, 4, 110),
        arc("club_combo.dae", 57, 67, 102, 5, 120, 7, 330)),
    # 4. серп, тяжёлая двойка Т-Т (раунд 3): Two Hit Combo Attack With Axe
    "sickle_heavy": combo("axe_two_hit_a.dae",
        arc("axe_two_hit_a.dae", 6, 30, 40, 7, 255, 5, 165),
        arc("axe_two_hit_a.dae", 42, 53, 81, 6, 200, 7, 310)),
}
TWIST_KEEP = {"sickle_quick": 0.45, "sickle_heavy": 0.45}

# Удары в воздухе (раунд 4): корпус и правая рука из прыжковых атак Mixamo, ноги — лист прыжка.
_SS = dict(src="air_ss_jump_attack.dae", face=39, hit=3, keys=[(24, 40), (30, 45), (33, 35), (36, 35), (39, 45), (45, 55)])
_SPIN = dict(src="air_gs_high_spin.dae", face=33, hit=3, keys=[(21, 40), (27, 45), (30, 35), (33, 35), (36, 45), (42, 55)])
_GS = dict(src="air_gs_jump_attack.dae", face=33, hit=3, keys=[(21, 40), (27, 45), (30, 35), (33, 35), (36, 45), (42, 60)])
_SMASH_KEYS = [(39, 45), (42, 50), (45, 90), (48, 40), (51, 40), (54, 60), (63, 70), (75, 70)]
_SMASH = dict(src="air_axe_jump_attack.dae", face=51, hit=4, keys=_SMASH_KEYS)
AIR = {
    "blade_air_quick": combo("air_ss_jump_attack.dae", _SS, _SPIN, _GS),
    "blade_air_heavy": combo("air_axe_jump_attack.dae", _SMASH),          # удар вниз сбрасывает врага
    "sickle_air_quick": combo("air_gs_jump_attack.dae", _GS, _SS, _SPIN),
    "sickle_air_heavy": combo("air_gs_high_spin.dae",
        dict(src="air_gs_high_spin.dae", face=33, hit=3, keys=[(18, 45), (24, 85), (27, 45), (30, 40), (33, 45), (39, 60)]),
        _SMASH),                                                           # второй удар сбрасывает врага
}
ATTACKS = {**MELEE, **AIR}

# Перемещение: кадры записи для ног и корпуса. pin — таз на постоянной высоте, подъём задаёт движок.
MOVES = {
    "jump": dict(src="run_jump_run.dae", face=30, pin=True, keys=[
        (6, 70), (12, 80), (15, 80), (18, 80), (24, 80), (30, 80), (36, 80), (42, 70)], hit=[]),
    # Ульта серпа (раунд 6). Вращение клинка собрано на скелете: см. SPIN в hero_layers.py.
    # Хук: прицел с занесённой рукой, бросок, рука вытянута, рывок цепи на себя.
    "hook": dict(src="ult_throw.dae", face=27, keys=[(21, 100), (27, 60), (30, 100), (15, 100)], hit=[]),
}

# Стрельба: обрез в протезе (правая), пистолет в левой. Стойка с двумя стволами.
# Позы на скелете героя: (мах плеча вперёд, сгиб локтя), наклон корпуса (минус — назад).
STANCE = {"l": (-7.0, 3.0, 4.0), "r": (7.0, -2.0, 4.0)}
AIM_R, AIM_L = (84.0, 4.0), (82.0, 6.0)


def gun_pose(arm_r=AIM_R, arm_l=AIM_L, lean=0.0, twist=0.0, bob=-0.6):
    return hr.make_pose(STANCE, bob=bob, lean=lean, twist=twist, arm_l=arm_l, arm_r=arm_r)


GUNS = {
    # 5+6. стойка: оба ствола на линии огня
    "gun_aim": dict(keys=[(gun_pose(), 200), (gun_pose(bob=-0.9, arm_r=(83, 5), arm_l=(81, 7)), 200)], hit=[]),
    # 5. обрез: тяжёлая отдача — рука уходит вверх, корпус назад, медленный возврат
    "gun_shoot_r": dict(keys=[
        (gun_pose(), 40),
        (gun_pose(arm_r=(112, -6), lean=-6, twist=-4, bob=-0.2), 50),
        (gun_pose(arm_r=(122, -12), lean=-8, twist=-5, bob=0.0, arm_l=(86, 4)), 70),
        (gun_pose(arm_r=(106, -4), lean=-5, twist=-3, bob=-0.4), 80),
        (gun_pose(arm_r=(94, 0), lean=-2, twist=-1), 90),
        (gun_pose(), 110)], hit=[1]),
    # 6. пистолет: лёгкая отдача, быстрый возврат
    "gun_shoot_l": dict(keys=[
        (gun_pose(), 30),
        (gun_pose(arm_l=(98, -2), lean=-2, twist=2), 40),
        (gun_pose(arm_l=(90, 2), lean=-1, twist=1), 50),
        (gun_pose(), 60)], hit=[1]),
}


def build_melee(name, spec):
    n = len(spec["keys"])
    faces = spec.get("faces") or [spec["face"]] * n
    srcs = spec.get("srcs") or [spec["src"]] * n
    rts = {}
    for sc, fc in set(zip(srcs, faces)):
        b = mocap.load(os.path.join(REFS, sc))
        rts[(sc, fc)] = mocap.Retarget(b, 0, b.n - 1, yaw=("shoulders", fc), pin=spec.get("pin", False))
    poses, root, base, prev = [], [], np.zeros(2), None
    for (f, _), fc, sc in zip(spec["keys"], faces, srcs):
        rt = rts[(sc, fc)]
        b = rt.pose(f)
        if name in TWIST_KEEP:
            damp_twist(b, TWIST_KEEP[name])
        poses.append(b)
        rm = np.array(rt.root_motion(f), float)
        if prev is not None and prev != (sc, fc):    # новый отрезок серии: смещение продолжается с места
            base = np.array(root[-1], float) - rm
        root.append([round(float(v), 4) for v in base + rm])
        prev = (sc, fc)
    return poses, root

# Бег (раунд 7): цикл Running Fast, 16 кадров записи; шаг 2,62 м, поэтому 8 кадров по 63 мс = 5,2 м/с без скольжения стоп.
RUN_FRAMES = list(range(0, 16, 2))
RUN_MS = 63


def _run_swing():
    """-> (рекордер, фаза левой ноги -1..1 по кадрам): рука качается против своей ноги."""
    b = mocap.load(os.path.join(REFS, "run_fast.dae"))
    rt = mocap.Retarget(b, 0, b.n - 1, yaw=0.0)
    y = [float(rt.joints(f)["ankle_l"][1]) for f in RUN_FRAMES]
    mid, amp = (max(y) + min(y)) / 2, (max(y) - min(y)) / 2
    return rt, [(v - mid) / amp for v in y]


# В записи плечи ходят на +-20 градусов, а корпус вбок: на спрайте это «пьяная» качка (раунд 9).
RUN_TWIST_KEEP = 0.15     # раунд 11: было 0,3
RUN_SWAY_KEEP = 0.0       # раунд 11: корпус вбок не ходит совсем (было 0,5)


def _calm_torso(b):
    """Гасит поворот плеч и боковой сдвиг корпуса; ноги остаются из записи."""
    R, cp, jr = b["chest"]
    side = R @ np.array([1.0, 0.0, 0.0])
    yaw = float(np.arctan2(side[1], side[0]))
    cp = np.array(cp, float)
    cp[0] *= RUN_SWAY_KEEP
    b["chest"] = (hr.rz(-yaw * (1 - RUN_TWIST_KEEP)) @ R, cp, jr)


RUN_TRACK = 4.6        # раунд 10: стопы под бёдрами (в записи бег «по одной линии», щиколотки скрещивались)
RUN_TRACK_KEEP = 0.35  # доля бокового хода стопы из записи


def _wide_track(rt):
    orig = rt.joints

    def joints(fr):
        j = {k: np.array(v, float) for k, v in orig(fr).items()}
        for s, sign in (("l", -1.0), ("r", 1.0)):
            j["ankle_" + s][0] = j["ankle_" + s][0] * RUN_TRACK_KEEP + sign * RUN_TRACK
        return j
    rt.joints = joints


def run_poses():
    """Ноги и корпус из записи; рука-протез (раунд 8): мах шире и от корпуса, запись прижимала её к боку."""
    rt, s = _run_swing()
    _wide_track(rt)
    poses = []
    for f, k in zip(RUN_FRAMES, s):
        b = rt.pose(f)
        _calm_torso(b)
        hr.set_arm(b, "r", (12 + 34 * k, 55, 14))    # правая рука идёт вместе с левой ногой
        poses.append(b)
    return poses


def run_arm_l():
    """Левая рука с револьвером на бегу: качается против левой ноги, ствол вперёд-вниз."""
    _, s = _run_swing()
    return [(10 - 30 * k, 60 + 8 * k, 12) for k in s]


# Удар о землю (раунд 5). Падение: таз на месте, рука занесена. Удар и подъём: Hard Landing (клинок, серп),
# колено и выстрел Kneeling With Hand Cannon (обрез). Кадры 0-1 падение, с кадра 2 удар; кадр 1 держится до пола.
SLAM_IMPACT = 2
SLAM_FALL_ARM = {"slam": (165, 5, 6), "slam_gun": (55, 2, 10)}
SLAM_SPEC = {
    "slam": [("land", 21, None, 40), ("land", 24, None, 60), ("land", 30, None, 120),
             ("land", 48, None, 60), ("land", 57, None, 60), ("land", 66, None, 60)],
    "slam_gun": [("kneel", 21, (72, 0, 12), 40), ("kneel", 24, (104, -4, 16), 70), ("kneel", 27, (90, 0, 14), 90),
                 ("kneel", 30, (72, 2, 12), 110), ("land", 57, None, 60), ("land", 66, None, 60)],
}


def slam_poses(name):
    """-> (позы, длительности мс)."""
    land = mocap.load(os.path.join(REFS, "slam_hard_landing.dae"))
    kneel = mocap.load(os.path.join(REFS, "slam_kneel_cannon.dae"))
    rts = {"land": mocap.Retarget(land, 0, land.n - 1, yaw=("shoulders", 27)),
           "kneel": mocap.Retarget(kneel, 0, kneel.n - 1, yaw=("shoulders", 24))}
    air = mocap.Retarget(land, 0, land.n - 1, yaw=("shoulders", 27), pin=True)
    poses, durs = [], []
    for f, ms in ((12, 60), (15, 60)):
        b = air.pose(f)
        hr.set_arm(b, "r", SLAM_FALL_ARM[name])
        poses.append(b)
        durs.append(ms)
    for src, f, arm, ms in SLAM_SPEC[name]:
        b = rts[src].pose(f)
        if arm:
            hr.set_arm(b, "r", arm)
        poses.append(b)
        durs.append(ms)
    return poses, durs


def main(outdir, which):
    os.makedirs(outdir, exist_ok=True)
    for name in which:
        if name in MELEE:
            spec = MELEE[name]
            poses, root = build_melee(name, spec)
        else:
            spec = GUNS[name]
            poses, root = [p for p, _ in spec["keys"]], [[0.0, 0.0]] * len(spec["keys"])
        durs = [d for _, d in spec["keys"]]
        for dname, a in hr.DIRS.items():
            for i, bones in enumerate(poses):
                hr.compose(*hr.render(a, bones)).save(os.path.join(outdir, f"hero_{name}_{dname}_{i}.png"))
        meta = dict(frames=len(poses), durations_ms=durs, hit=spec["hit"], chain=spec.get("chain", [0]),
                    root_m=root, source=spec.get("src", "procedural"))
        with open(os.path.join(outdir, f"{name}.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False)
        print(f"{name}: {len(poses)} кадров, {sum(durs)} мс, удары {spec['hit']}, смещение {root[-1]}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:] or list(MELEE) + list(GUNS))
