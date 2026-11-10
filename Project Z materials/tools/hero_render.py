"""Чернов: 3D-модель из SDF-примитивов на скелете -> пиксельные спрайты в палитре PZ-28.

Ортографическая камера, наклон PITCH, 8 направлений. Свет привязан к экрану
(сверху-слева-спереди), поэтому все ракурсы освещены одинаково.
Каждая деталь привязана к кости: её SDF и роспись считаются в позе покоя,
поэтому складки, пуговицы и шнуровка двигаются вместе с телом.

python tools/hero_render.py art/hero/render            # все анимации
python tools/hero_render.py art/hero/render walk run   # выбранные
"""
import math
import os
import sys

import numpy as np
from PIL import Image

W, H = 64, 96             # холст
PIVOT = (32, 93)          # точка стоп (bottom-center, 2 px под тень)
PITCH = math.radians(30)  # наклон камеры, как на референсе
DIRS = {"s": 0, "se": 45, "e": 90, "ne": 135, "n": 180, "nw": 225, "w": 270, "sw": 315}
UNIT_M = 1 / 56           # 1 единица модели = 1 px = 1/56 м
RAY_NEAR, RAY_FAR = 120, 260  # старт луча до модели и предел; крупным моделям (мехи) больше

# ---------- палитра и рампы ----------
PAL = ["0b0a10", "15131d", "211e2c", "322e40", "4a4558", "6b6578", "948ea0", "c4bfcc", "ece8ee",
       "2a0509", "4f0a12", "7d0f1c", "b3162a", "e02a3c", "f0505a",
       "3b1f28", "6e3440", "a35a5a", "d49a86", "f0cdb4",
       "1d2a33", "34505c", "5d8591", "9fc5c9",
       "4a3a1c", "9a7a2e", "e0b84a", "7fa05a",
       "3e2c1c", "74582a"]  # brass-dark, brass-mid (2026-11-10)
RAMPS = {
    "cloth":   ["0b0a10", "15131d", "211e2c", "322e40", "4a4558"],
    "pants":   ["0b0a10", "15131d", "211e2c", "322e40"],
    "boot":    ["0b0a10", "15131d", "211e2c", "3b1f28"],
    "leather": ["0b0a10", "15131d", "3b1f28", "4a3a1c"],
    "skin":    ["3b1f28", "6e3440", "a35a5a", "d49a86", "f0cdb4"],
    "hair":    ["0b0a10", "15131d", "3b1f28", "6e3440"],
    "steel":   ["15131d", "322e40", "4a4558", "6b6578", "948ea0", "c4bfcc", "ece8ee"],
    "core":    ["0b0a10", "15131d", "211e2c", "322e40"],
    "brass":   ["4a3a1c", "9a7a2e", "e0b84a"],
    "blade":   ["322e40", "4a4558", "6b6578", "948ea0", "c4bfcc", "ece8ee"],
    "gun":     ["0b0a10", "211e2c", "4a4558", "6b6578", "948ea0", "c4bfcc"],
    "hose":    ["2a0509", "3b1f28", "6e3440", "a35a5a", "d49a86"],
    "shell":   ["2a0509", "4f0a12", "7d0f1c", "b3162a"],
}
# диапазон тонов при обычном освещении (низ, верх); 0 остаётся под контур и стыки
SHADE = {"pants": (1, 2), "cloth": (1, 3), "boot": (1, 3), "leather": (1, 3), "skin": (1, 4), "hair": (1, 2),
         "steel": (1, 4), "core": (1, 3), "brass": (0, 1), "hose": (2, 3), "blade": (1, 4), "gun": (1, 3), "shell": (1, 2)}
LIFT = {"skin": 0.22, "hair": 0.1, "blade": 0.3}  # подъём яркости для лица и волос
SPEC = {"gun": 5, "blade": 5, "steel": 5, "brass": 2, "hair": 3, "core": 3, "hose": 3, "shell": 3}  # блик

# ---------- SDF ----------
def length(v):
    return np.sqrt((v * v).sum(-1))


def sphere(p, c, r):
    return length(p - np.array(c)) - r


def ellipsoid(p, c, r):
    q = (p - np.array(c)) / np.array(r)
    k0 = length(q)
    k1 = length(q / np.array(r))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def capsule(p, a, b, ra, rb=None):
    rb = ra if rb is None else rb
    a, b = np.array(a, float), np.array(b, float)
    pa, ba = p - a, b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return length(pa - h[:, None] * ba) - (ra + (rb - ra) * h)


def torus_x(p, c, R, r):
    q = p - np.array(c)
    a = np.sqrt(q[:, 1] ** 2 + q[:, 2] ** 2) - R
    return np.sqrt(a * a + q[:, 0] ** 2) - r


def ring_z(p, c, r, h):
    """Цилиндр по оси z (воротник): центр c, радиус r, полувысота h."""
    q = p - np.array(c)
    dr = np.sqrt(q[:, 0] ** 2 + q[:, 1] ** 2) - r
    dz = np.abs(q[:, 2]) - h
    return np.minimum(np.maximum(dr, dz), 0) + length(np.stack([np.maximum(dr, 0), np.maximum(dz, 0)], -1))


def ring_seg(p, a, b, r, h):
    """Бандаж на отрезке a-b: цилиндр радиуса r, полувысота h вдоль оси, центр в середине."""
    a, b = np.array(a, float), np.array(b, float)
    c = (a + b) / 2
    ax = (b - a) / np.linalg.norm(b - a)
    q = p - c
    along = q @ ax
    radial = length(q - along[:, None] * ax)
    dr, dz = radial - r, np.abs(along) - h
    return np.minimum(np.maximum(dr, dz), 0) + length(np.stack([np.maximum(dr, 0), np.maximum(dz, 0)], -1))


def rbox(p, c, half, rr):
    q = np.abs(p - np.array(c)) - (np.array(half) - rr)
    return length(np.maximum(q, 0)) + np.minimum(q.max(-1), 0) - rr


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def band(z, lo, hi, soft=1.0):
    """Мягкая маска lo<z<hi для складок (без ступенек в SDF)."""
    return np.clip((z - lo) / soft, 0, 1) * np.clip((hi - z) / soft, 0, 1)


# ---------- скелет (поза покоя) ----------
J = {
    "pelvis": (0.0, 0.3, 47.0),
    "chest": (0.0, 0.3, 57.0),
    "hip_l": (-5.6, 0.4, 47.0), "knee_l": (-6.4, 0.6, 25.5), "ankle_l": (-6.8, 0.4, 4.0),
    "hip_r": (5.6, 0.4, 47.0), "knee_r": (6.4, 0.6, 25.5), "ankle_r": (6.8, 0.4, 4.0),
    "sh_l": (-12.6, 0.3, 77.5), "el_l": (-14.8, 0.8, 64.0), "wr_l": (-14.6, 2.2, 52.0),
    "sh_r": (15.0, 0.2, 73.5), "el_r": (15.9, 0.8, 61.5), "wr_r": (16.0, 2.6, 50.5),
}
J = {k: np.array(v) for k, v in J.items()}
L_THIGH = np.linalg.norm(J["knee_l"] - J["hip_l"])
L_SHIN = np.linalg.norm(J["ankle_l"] - J["knee_l"])

# ---------- детали модели (координаты покоя) ----------
def torso(p):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    zs = [43, 50, 57, 60.5, 66, 75, 81, 84]
    hx = np.interp(z, zs, [11.8, 10.8, 10.2, 11.0, 11.4, 12.4, 11.5, 8.0])
    hy = np.interp(z, zs, [6.8, 6.3, 6.0, 6.8, 6.8, 7.0, 6.0, 4.5])
    rc = 3.5
    qx, qy = np.abs(x) - (hx - rc), np.abs(y - 0.3) - (hy - rc)
    d2 = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - rc
    d = np.maximum(d2, np.maximum(43 - z, z - 84))
    d = smin(d, capsule(p, (-10.5, 0.2, 78.5), (10.5, 0.2, 78.5), 4.6), 2.0)
    # складки: сборка подола под ремнём (по кругу), напуск над ремнём, диагонали к подмышкам
    ang = np.arctan2(y - 0.3, x)
    fold = 0.5 * np.sin(ang * 13 + 0.5 + 0.8 * np.sin(ang * 3)) * (0.55 + 0.45 * np.sin(ang * 4 + 1)) * band(z, 44, 55.5)
    fold += 0.35 * np.sin(z * 1.7) * band(z, 59.8, 64.5)
    fold += 0.35 * np.sin(1.25 * (np.abs(x) * 0.85 - (z - 59))) * band(z, 60, 71) * np.clip(np.abs(x) - 2.5, 0, 1)
    return d - fold


def boot_at(p, ank):
    x, y, z = ank
    shaft = capsule(p, (x, y, z - 1), (x, y - 0.3, z + 16), 4.3, 4.0)
    foot = ellipsoid(p, (x, y + 3.2, z - 1.4), (4.2, 7.2, 3.0))
    return smin(shaft, foot, 1.5)


def blouse_at(p, ank):
    """Напуск галифе над голенищем, с радиальными складками."""
    x, y, z = ank
    d = ellipsoid(p, (x, y, z + 17.5), (5.4, 5.4, 3.6))
    ang = np.arctan2(p[:, 1] - y, p[:, 0] - x)
    return d - 0.45 * np.sin(ang * 6 + p[:, 2] * 0.9) - 0.2 * np.sin(p[:, 2] * 2.1)


def thigh_at(p, hip, knee):
    d = capsule(p, hip, knee, 5.6, 5.0)
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    fold = 0.35 * np.sin(z * 0.8 + y * 0.9 + x * 0.3) * band(z, 30, 45)
    fold += 0.35 * np.sin(z * 1.6 + x * 0.4) * band(z, 24, 30)
    return d - fold


def sleeve_up(p, sh, el):
    d = capsule(p, sh, el, 4.0, 3.6)
    return d - 0.35 * np.sin(p[:, 2] * 1.5 + p[:, 0] * 0.6) * band(p[:, 2], 62, 69)


def sleeve_lo(p, el, wr):
    d = capsule(p, el, wr, 3.6, 3.3)
    fold = 0.4 * np.sin(p[:, 2] * 1.5 + p[:, 0] * 0.6) * band(p[:, 2], 60, 66)
    fold += 0.3 * np.sin(p[:, 2] * 1.3) * band(p[:, 2], 53.5, 57)
    return d - fold


def hand_l(p):
    d = capsule(p, (-14.5, 2.4, 50.5), (-14.2, 3.0, 44.5), 2.4, 2.1)
    return smin(d, sphere(p, (-12.9, 4.4, 47.5), 1.2), 0.8)


def hair(p):
    d = ellipsoid(p, (0, -0.9, 97.4), (6.4, 6.9, 5.6))
    d -= 0.55 * np.sin(p[:, 0] * 1.7) * np.sin(p[:, 1] * 1.5 + 1) * np.sin(p[:, 2] * 1.9)
    face = np.maximum(2.0 - p[:, 1], p[:, 2] - 97.3)          # срезаем область лица
    side = np.maximum(np.abs(p[:, 0]) - 4.3, p[:, 2] - 95.5)  # не опускаем волосы на щёки спереди
    return np.maximum(np.maximum(d, -face), -np.maximum(side, 1.5 - p[:, 1]))


def head(p):
    d = ellipsoid(p, (0, 0.6, 93.5), (5.0, 5.6, 6.4))
    d = smin(d, ellipsoid(p, (0, 2.0, 90.4), (4.5, 4.4, 3.4)), 1.5)    # челюсть
    d = smin(d, ellipsoid(p, (0, 6.0, 93.0), (1.0, 1.6, 1.8)), 0.6)    # нос
    for s in (-1, 1):
        d = np.minimum(d, sphere(p, (s * 5.1, 0.2, 93.5), 1.3))         # уши
    return d


UA = ((15.0, 0.2, 73.5), (15.8, 0.8, 62.5))   # плечо протеза
FA = ((15.8, 0.8, 60.5), (16.0, 2.6, 50.5))   # предплечье протеза


def rods(p, seg, off, r):
    a, b = seg
    return np.minimum(capsule(p, (a[0], a[1] - off, a[2]), (b[0], b[1] - off, b[2]), r),
                      capsule(p, (a[0], a[1] + off, a[2]), (b[0], b[1] + off, b[2]), r))


def hand_r(p):
    d = rbox(p, (16.1, 3.0, 47.3), (1.9, 2.5, 2.3), 0.9)
    for i, oy in enumerate((1.0, 2.3, 3.6, 4.9)):
        fz = 40.2 + (0.6 if i in (0, 3) else 0)
        d = np.minimum(d, capsule(p, (16.3, oy + 0.3, 45.4), (16.6, oy + 0.6, fz), 0.85))
    return np.minimum(d, capsule(p, (14.4, 4.6, 47.0), (14.3, 5.8, 44.0), 0.9))


# (имя, рампа, кость, sdf в координатах покоя, срез по полу)
PARTS = [
    ("boot_l", "boot", "shin_l", lambda p: boot_at(p, J["ankle_l"]), True),
    ("boot_r", "boot", "shin_r", lambda p: boot_at(p, J["ankle_r"]), True),
    ("blouse_l", "pants", "shin_l", lambda p: blouse_at(p, J["ankle_l"]), False),
    ("blouse_r", "pants", "shin_r", lambda p: blouse_at(p, J["ankle_r"]), False),
    ("leg_l", "pants", "thigh_l", lambda p: thigh_at(p, J["hip_l"] * [0.75, 1, 1], J["knee_l"]), False),
    ("leg_r", "pants", "thigh_r", lambda p: thigh_at(p, J["hip_r"] * [0.75, 1, 1], J["knee_r"]), False),
    ("torso", "cloth", "chest", torso, False),
    ("collar", "cloth", "chest", lambda p: ring_z(p, (0, 0.6, 85.0), 4.8, 1.8), False),
    ("neck", "skin", "chest", lambda p: capsule(p, (0, 0.6, 83), (0, 0.8, 89), 3.4), False),
    ("head", "skin", "head", head, False),
    ("hair", "hair", "head", hair, False),
    ("arm_l", "cloth", "uarm_l", lambda p: sleeve_up(p, J["sh_l"], J["el_l"]), False),
    ("farm_l", "cloth", "farm_l", lambda p: sleeve_lo(p, J["el_l"], J["wr_l"]), False),
    ("hand_l", "skin", "farm_l", hand_l, False),
    ("pauldron", "steel", "chest", lambda p: ellipsoid(p, (13.6, 0.2, 78.2), (4.6, 5.2, 4.6)), False),
    ("p_ring", "brass", "chest", lambda p: torus_x(p, (10.8, 0.2, 78.0), 4.7, 1.1), False),
    ("rods_u", "steel", "uarm_r", lambda p: rods(p, UA, 1.5, 1.35), False),
    ("core_u", "core", "uarm_r", lambda p: capsule(p, *UA, 1.7), False),
    ("band_e", "brass", "uarm_r", lambda p: ring_seg(p, (15.9, 0.8, 63.6), (15.9, 0.9, 61.8), 3.0, 0.9), False),
    ("joint", "steel", "farm_r", lambda p: sphere(p, (15.9, 0.8, 61.5), 2.6), False),
    ("rods_f", "steel", "farm_r", lambda p: rods(p, FA, 1.35, 1.25), False),
    ("core_f", "core", "farm_r", lambda p: capsule(p, *FA, 1.5), False),
    ("bands_f", "brass", "farm_r", lambda p: np.minimum(
        ring_seg(p, (15.9, 1.6, 57.0), (15.9, 1.9, 55.6), 2.9, 0.8),
        ring_seg(p, (16.0, 2.5, 51.6), (16.0, 2.7, 50.2), 2.6, 0.8)), False),
    ("hand_r", "steel", "farm_r", hand_r, False),
]


# ---------- модули протеза и револьвер (референсы refs/hero_modules) ----------
def obox(p, a, b, side, hw, ht, taper=0.0):
    """Брусок вдоль отрезка a-b: полуширина hw по направлению side, полутолщина ht; taper сужает к концу b."""
    a, b = np.array(a, float), np.array(b, float)
    L = np.linalg.norm(b - a)
    ax = (b - a) / L
    s = np.array(side, float)
    s = s - (s @ ax) * ax
    s /= np.linalg.norm(s)
    t = np.cross(ax, s)
    q = p - a
    u, v, w = q @ ax, q @ s, q @ t
    hwv = hw * (1 - taper * np.clip(u / L, 0, 1))
    k = np.stack([np.abs(u - L / 2) - L / 2, np.abs(v) - hwv, np.abs(w) - ht], -1)
    return length(np.maximum(k, 0)) + np.minimum(k.max(-1), 0)


WRIST_R = np.array([16.0, 2.7, 50.0])
FA_DIR = (np.array(FA[1]) - np.array(FA[0])) / np.linalg.norm(np.array(FA[1]) - np.array(FA[0]))


def hoses(p):
    """Медные паровые шланги от наплечника вдоль плеча протеза."""
    pts = [(14.8, -3.6, 75.5), (18.3, -2.8, 68.5), (18.8, -1.3, 61.5), (17.9, 0.0, 57.5)]
    d = None
    for a, b in zip(pts, pts[1:]):
        di = capsule(p, a, b, 0.95)
        d = di if d is None else np.minimum(d, di)
    return d


def blade(p):
    """Паровой клинок: широкое лезвие продолжает предплечье, плоскость — вперёд."""
    return obox(p, WRIST_R + FA_DIR * 1.0, WRIST_R + FA_DIR * 25.0, (0, 1, 0), 2.3, 0.45, taper=0.75)


SICKLE_C, SICKLE_R = np.array([16.1, 8.0, 45.0]), 7.5


def flip_fa(p):
    """Поворот на 180 градусов вокруг оси предплечья через запястье (правка 9, раунд 3): серп загнут в другую сторону."""
    v = np.asarray(p, float) - WRIST_R
    return WRIST_R + 2 * (v @ FA_DIR)[..., None] * FA_DIR - v


def sickle(p):
    """Серп: дуга от запястья и к острию, сужается к концу. Нарисован в исходной раскладке и развёрнут flip_fa."""
    p = flip_fa(p)
    angs = np.radians(np.linspace(143, 338, 11))
    pts = [SICKLE_C + SICKLE_R * np.array([0, math.cos(a), math.sin(a)]) for a in angs]
    d = capsule(p, WRIST_R, pts[0], 1.1)
    n = len(pts) - 1
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        d = np.minimum(d, capsule(p, a, b, 1.5 - 1.0 * i / n, 1.5 - 1.0 * (i + 1) / n))
    return d


def shells(p):
    d = None
    for oy in (-0.4, 1.6, 3.6):
        di = capsule(p, (20.4, oy, 52.0), (20.4, oy, 56.0), 0.95)
        d = di if d is None else np.minimum(d, di)
    return d


PISTOL_GRIP = np.array([-14.3, 3.4, 44.0])   # точка хвата: вокруг неё револьвер увеличен (правка 2, раунд 2)
PISTOL_SCALE = 1.6


def scaled(f, c=PISTOL_GRIP, k=PISTOL_SCALE):
    return lambda p: f(c + (p - c) / k) * k


PISTOL_PARTS = [
    ("ps_cyl", "gun", "farm_l", scaled(lambda p: ellipsoid(p, (-14.2, 4.5, 42.4), (1.15, 1.3, 1.5))), False),
    ("ps_barrel", "gun", "farm_l", scaled(lambda p: capsule(p, (-14.2, 4.9, 41.6), (-14.0, 5.4, 35.5), 0.7)), False),
    ("ps_hammer", "gun", "farm_l", scaled(lambda p: sphere(p, (-14.3, 3.9, 44.4), 0.55)), False),
    ("ps_grip", "leather", "farm_l", scaled(lambda p: capsule(p, (-14.3, 3.0, 43.4), (-14.45, -0.4, 44.6), 0.95)), False),
]
# дульный срез револьвера в координатах покоя (для вспышки)
PISTOL_MUZZLE = PISTOL_GRIP + (np.array([-14.0, 5.4, 35.0]) - PISTOL_GRIP) * PISTOL_SCALE

MODULE_PARTS = [
    # общее для всех модулей: крупный наплечник с латунной окантовкой, шланги
    ("pauldron_b", "steel", "chest", lambda p: ellipsoid(p, (13.8, 0.2, 78.4), (5.4, 5.9, 5.3)), False),
    ("p_ring_b", "brass", "chest", lambda p: torus_x(p, (10.4, 0.2, 78.2), 5.2, 1.3), False),
    ("hose", "hose", "uarm_r", hoses, False),
    # паровой клинок: латунный кожух с манометром, отвод пара, гарда, лезвие
    ("bl_house", "brass", "farm_r", lambda p: ring_seg(p, (15.85, 1.2, 58.5), (16.0, 2.4, 51.5), 3.1, 3.5), False),
    ("bl_gauge", "steel", "farm_r", lambda p: ellipsoid(p, (19.1, 1.6, 55.0), (0.8, 1.4, 1.4)), False),
    ("bl_vent", "brass", "farm_r", lambda p: capsule(p, (18.8, -0.2, 53.0), (20.6, -1.0, 53.6), 0.55), False),
    ("bl_guard", "brass", "farm_r", lambda p: ring_seg(p, (16.0, 2.6, 51.0), (16.0, 2.8, 49.4), 2.5, 0.8), False),
    ("bl_blade", "blade", "farm_r", blade, False),
    # серп: латунный хомут с манометром, шарнир, серповидное лезвие
    ("sk_house", "brass", "farm_r", lambda p: ring_seg(p, (15.9, 1.5, 57.0), (16.0, 2.2, 53.0), 2.6, 2.0), False),
    ("sk_gauge", "steel", "farm_r", lambda p: ellipsoid(p, (18.4, 1.8, 55.0), (0.7, 1.2, 1.2)), False),
    ("sk_joint", "brass", "farm_r", lambda p: sphere(p, (16.0, 2.8, 49.8), 1.9), False),
    ("sk_blade", "blade", "farm_r", sickle, False),
    # обрез: стальной блок с латунными бандажами, гильзы, толстый ствол вместо кисти
    ("sg_block", "steel", "farm_r", lambda p: obox(p, (15.85, 0.8, 60.0), (16.05, 2.9, 47.0), (0, 1, 0), 4.2, 3.8), False),
    ("sg_bands", "brass", "farm_r", lambda p: np.minimum(
        ring_seg(p, (15.9, 1.1, 58.9), (15.9, 1.3, 57.3), 4.7, 0.8),
        ring_seg(p, (16.0, 2.5, 50.0), (16.0, 2.7, 48.4), 4.7, 0.8)), False),
    ("sg_shells", "shell", "farm_r", shells, False),
    ("sg_barrel", "core", "farm_r", lambda p: capsule(p, (16.05, 3.0, 48.0), (16.2, 3.9, 40.5), 2.5), False),
]
PARTS += PISTOL_PARTS + MODULE_PARTS
NAMES = np.array([n for n, *_ in PARTS])
PART_BONE = {n: bone for n, _, bone, *_ in PARTS}

# Слои спрайта: ноги (движение), корпус с правой рукой (действие), левая рука с пистолетом.
LEGS = {"boot_l", "boot_r", "blouse_l", "blouse_r", "leg_l", "leg_r"}
ARM_L = {"arm_l", "farm_l", "hand_l"} | {n for n, *_ in PISTOL_PARTS}
TORSO_CORE = {"torso", "collar", "neck", "head", "hair", "pauldron", "p_ring", "pauldron_b", "p_ring_b"}
# какие детали к какому модулю: None — базовый протез без модуля (старые цельные спрайты)
# sickle_bare (раунд 6): протез серпа без лезвия, пока лезвие летит на цепи
ALL_MODULES = {"blade", "sickle", "sickle_bare", "shotgun"}
MODULE_OF = {"hand_r": {None}, "pauldron": {None}, "p_ring": {None}}
for n, *_ in PISTOL_PARTS:
    MODULE_OF[n] = ALL_MODULES
for n, *_ in MODULE_PARTS:
    pre = n.split("_")[0]
    MODULE_OF[n] = {"bl": {"blade"}, "sk": {"sickle", "sickle_bare"}, "sg": {"shotgun"}}.get(pre, ALL_MODULES)
MODULE_OF["sk_blade"] = {"sickle"}

ACTIVE = list(range(len(PARTS)))


def configure(layer=None, module=None):
    """Какие детали рендерить: layer — 'legs' | 'upper' | 'arm' | 'core' | None (всё тело); module — модуль протеза."""
    global ACTIVE
    keep = []
    for i, (n, *_) in enumerate(PARTS):
        if module not in MODULE_OF.get(n, ALL_MODULES | {None}):
            continue
        if layer == "legs" and n not in LEGS:
            continue
        if layer == "arm" and n not in ARM_L:
            continue
        if layer == "core" and n not in TORSO_CORE:
            continue
        if layer == "upper" and (n in LEGS or n in ARM_L):
            continue
        # раунд 11: корпус обреза без правой руки и правая рука отдельно (рука наводится независимо от корпуса)
        if layer == "upper_noarm" and (n in LEGS or n in ARM_L or PART_BONE[n] in ("uarm_r", "farm_r")):
            continue
        if layer == "arm_r" and PART_BONE[n] not in ("uarm_r", "farm_r"):
            continue
        keep.append(i)
    ACTIVE = keep


configure()


# ---------- позы ----------
def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rot_between(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v, c = np.cross(a, b), float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)


def leg_ik(hip, ankle):
    """Колено по двум костям, сгиб вперёд (+y). Возвращает (колено, достижимая лодыжка)."""
    d = ankle - hip
    dist = min(np.linalg.norm(d), L_THIGH + L_SHIN - 0.01)
    u = d / np.linalg.norm(d)
    a = (L_THIGH ** 2 - L_SHIN ** 2 + dist ** 2) / (2 * dist)
    h = math.sqrt(max(L_THIGH ** 2 - a * a, 0))
    fwd = np.array([0, 1.0, 0])
    b = fwd - (fwd @ u) * u
    b /= np.linalg.norm(b)
    return hip + a * u + h * b, hip + dist * u


REACH = 0.975   # доля полной длины ноги: колено в опоре чуть согнуто


def pelvis_drop(feet, cap):
    """Смещение таза по z (<=cap), при котором ни одна нога не перетянута.
    Таз садится в двойной опоре и поднимается в середине шага — покачивание получается само."""
    hip_y, hip_z = J["hip_l"][1], J["hip_l"][2]
    best = cap
    for s, f in feet.items():
        dx = f[0] - J["hip_" + s][0]
        dy = f[1] - hip_y
        h2 = (REACH * (L_THIGH + L_SHIN)) ** 2 - dx * dx - dy * dy
        best = min(best, f[2] + math.sqrt(max(h2, 0.0)) - hip_z)
    return best


def make_pose(feet, bob=0.0, sway=0.0, twist=0.0, lean=0.0, arm_l=(0.0, 0.0), arm_r=(0.0, 0.0), bob_cap=0.0):
    """feet: {"l": (x, y, z лодыжки)}; углы в градусах; arm_*: (мах плеча вперёд, сгиб локтя).
    Возвращает {кость: (R, точка в позе, точка покоя)}."""
    tw, ln = math.radians(twist), math.radians(lean)
    if bob is None:
        bob = pelvis_drop(feet, bob_cap)
    t = np.array([sway, 0, bob])
    Rp = rz(tw)

    def P(v):
        return Rp @ (v - J["pelvis"]) + J["pelvis"] + t

    Rc = Rp @ rz(-1.6 * tw) @ rx(-ln)   # плечи против таза, наклон вперёд
    cp = P(J["chest"])

    def C(v):
        return Rc @ (v - J["chest"]) + cp

    bones = {"chest": (Rc, cp, J["chest"])}
    for s in ("l", "r"):
        hip = P(J["hip_" + s])
        knee, ank = leg_ik(hip, np.array(feet[s], float))
        bones["thigh_" + s] = (rot_between(J["knee_" + s] - J["hip_" + s], knee - hip), hip, J["hip_" + s])
        bones["shin_" + s] = (rot_between(J["ankle_" + s] - J["knee_" + s], ank - knee), knee, J["knee_" + s])
        set_arm(bones, s, arm_l if s == "l" else arm_r)
    return bones


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def set_arm(bones, s, arm):
    """Рука от груди позы: arm = (мах плеча вперёд, сгиб локтя[, отведение плеча наружу]), градусы."""
    up, bend = arm[0], arm[1]
    out = arm[2] if len(arm) > 2 else 0.0
    side = 1 if s == "r" else -1
    Ra = ry(-side * math.radians(out))
    Ru = rx(math.radians(up)) @ Ra
    Rf = rx(math.radians(up + bend)) @ Ra
    Rc, cp, _ = bones["chest"]
    C = lambda v: Rc @ (v - J["chest"]) + cp
    sh, el = J["sh_" + s], J["el_" + s]
    bones["uarm_" + s] = (Rc @ Ru, C(sh), sh)
    bones["farm_" + s] = (Rc @ Rf, C(sh + Ru @ (el - sh)), el)


def aim_arm(bones, s, yaw, up=84.0, bend=4.0):
    """Рука наведена в сторону yaw (градусы от «вперёд» груди, плюс — вправо героя), раунд 11.
    Сначала мах вперёд-вверх на up, потом поворот вокруг вертикали груди: оружие не переворачивается."""
    side = 1 if s == "r" else -1
    cross = yaw * side < 0 and abs(yaw) < 180          # через грудь: плечо вперёд, в сторону уводит предплечье
    yaw_u = yaw * 0.35 if cross else yaw
    Ru = rz(-math.radians(yaw_u)) @ rx(math.radians(up))
    Rf = rz(-math.radians(yaw)) @ rx(math.radians(up + bend + (12 if cross else 0)))
    Rc, cp, _ = bones["chest"]
    C = lambda v: Rc @ (v - J["chest"]) + cp
    sh, el = J["sh_" + s], J["el_" + s]
    bones["uarm_" + s] = (Rc @ Ru, C(sh), sh)
    bones["farm_" + s] = (Rc @ Rf, C(sh + Ru @ (el - sh)), el)


NECK_PIVOT = np.array([0.0, 0.7, 86.0])


def turn_head(bones, yaw):
    """Голова повёрнута на yaw градусов вокруг шеи (плюс — вправо героя), раунд 12."""
    Rc, cp, _ = bones["chest"]
    piv = Rc @ (NECK_PIVOT - J["chest"]) + cp
    bones["head"] = (Rc @ rz(-math.radians(yaw)), piv, NECK_PIVOT)


def pose_idle(_):
    return make_pose({"l": (-7.0, 2.0, 4.0), "r": (7.0, -1.0, 4.0)}, bob=-0.5)


# параметры циклов: шаг (полуамплитуда стопы), подъём, доля опоры, кадры, fps
GAIT = {
    # цикл = два шага; скорость считает gait_speed()
    "walk": dict(A=16.0, lift=6.0, stance=0.6, frames=8, fps=10, foot_x=6.4),
    "run": dict(A=22.0, lift=13.0, stance=0.35, frames=8, fps=15, foot_x=5.6),   # раунд 4: быстрее на 15 %, позы те же
}


def foot_track(q, g):
    """Положение лодыжки (y, z) в фазе q для шага на месте (на опоре стопа уезжает назад)."""
    A, st = g["A"], g["stance"]
    if q < st:
        u = q / st
        return A * (1 - 2 * u), 4.0
    u = (q - st) / (1 - st)
    s = u * u * (3 - 2 * u)
    lift = g["lift"] * math.sin(math.pi * u ** 0.8)
    return -A + 2 * A * s, 4.0 + lift


def pose_gait(kind):
    g = GAIT[kind]

    def f(phi):
        feet = {}
        for s, off in (("r", 0.0), ("l", 0.5)):
            y, z = foot_track((phi + off) % 1.0, g)
            feet[s] = ((1 if s == "r" else -1) * g["foot_x"], y, z)
        c = lambda k, ph=0.0: math.cos(2 * math.pi * (k * phi - ph))
        if kind == "walk":
            # протез тяжелее: машет меньше
            return make_pose(feet, bob=None, bob_cap=-0.8, sway=0.8 * c(1, 0.3), twist=6 * c(1),
                             lean=3, arm_l=(16 * c(1), 12 + 8 * max(c(1), 0)),
                             arm_r=(13 * c(1, 0.5), 10 + 6 * max(c(1, 0.5), 0)))
        return make_pose(feet, bob=None, bob_cap=-2.5, sway=0.5 * c(1, 0.17), twist=9 * c(1),
                         lean=10, arm_l=(2 + 26 * c(1), 85), arm_r=(2 + 20 * c(1, 0.5), 80))
    return f


ANIMS = {"idle": (pose_idle, 1), "walk": (pose_gait("walk"), GAIT["walk"]["frames"]),
         "run": (pose_gait("run"), GAIT["run"]["frames"])}


# ---------- сцена ----------
def to_rest(p, bone, bones):
    R, jp, jr = bones[bone] if bone in bones else bones["chest"]     # кость головы необязательна (раунд 12)
    return (p - jp) @ R + jr


def scene(p, bones):
    ds = []
    for i in ACTIVE:
        _, _, bone, f, clip = PARTS[i]
        d = f(to_rest(p, bone, bones))
        if clip:
            d = np.maximum(d, -p[:, 2])
        ds.append(d)
    ds = np.stack(ds)
    return ds.min(0), np.array(ACTIVE)[ds.argmin(0)]


# ---------- роспись поверхности (детали) ----------
def paint(p, part, ramp, idx, fixed):
    """Меняет рампу/тон/фикс. цвет по точке попадания в координатах покоя. fixed: индекс PAL или -1."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    name = NAMES[part]
    R = lambda m, r: ramp.__setitem__(m, r)

    def fix(m, hexc):
        fixed[m] = PAL.index(hexc)

    t = name == "torso"
    front = y > 3.0
    # ремень и пряжка
    belt = t & (z > 56.0) & (z < 59.6)
    R(belt, "leather")
    fix(belt & front & (np.abs(x + 1.0) < 1.8), "9a7a2e")
    fix(belt & front & (np.abs(x + 1.0) < 0.6) & (np.abs(z - 57.8) < 0.7), "15131d")
    # пуговицы планки
    for zb in (80.0, 75.0, 70.0, 65.0):
        fix(t & front & ((x + 1.0) ** 2 + (z - zb) ** 2 < 0.8), "9a7a2e")
    # нагрудный карман справа (у героя), блокнот
    pk = t & front & (x > 3.6) & (x < 9.8) & (z > 64.5) & (z < 72.5)
    edge = pk & ((np.abs(x - 3.6) < 0.7) | (np.abs(x - 9.8) < 0.7) | (np.abs(z - 64.5) < 0.7) | (np.abs(z - 70.6) < 0.6))
    idx[edge] -= 1
    fix(t & front & (x > 5.0) & (x < 8.6) & (z > 71.0) & (z < 73.6), "6e3440")
    # орёл на левой груди
    eagle = t & front & (np.abs(x + 7.2) < 2.2) & (np.abs(z - 73.8) < 1.1)
    fix(eagle, "9a7a2e")
    fix(eagle & (np.abs(x + 7.2) < 0.7), "e0b84a")
    # нижние карманы с клапанами
    for s in (-1, 1):
        flap = t & front & (np.abs(x - s * 7.0) < 3.2) & (z > 50.6) & (z < 54.4)
        idx[flap & (np.abs(z - 50.8) < 0.7)] -= 1
        fix(flap & (np.abs(x - s * 7.0) < 0.6) & (np.abs(z - 51.8) < 0.7), "9a7a2e")
    # подол гимнастёрки: тёмная кромка
    idx[t & (z < 44.2)] -= 1

    # манжета левой руки
    idx[(name == "farm_l") & (z < 53.4)] -= 1

    # сапоги: шнуровка спереди, подошва
    for s in ("l", "r"):
        ax, ay, az = J["ankle_" + s]
        nm = name == "boot_" + s
        b = nm & (z > az + 1.5) & (z < az + 15.5) & (y - ay > 2.3) & (np.abs(x - ax) < 1.6)
        fix(b & (np.round(z) % 3 == 0), "4a3a1c")
        R(nm & (z < az - 2.8), "core")

    h = name == "head"
    face = h & (y > 3.0)
    # борода (щетина) и усы
    R(h & (z < 91.6) & (y > -1.5), "hair")
    R(h & (z > 91.2) & (z < 92.2) & (np.abs(x) < 2.4) & front, "hair")
    fix(face & (np.abs(z - 90.6) < 0.5) & (np.abs(x) < 1.3), "3b1f28")  # рот
    # глаза
    for s in (-1, 1):
        fix(face & (np.abs(x - s * 2.2) < 0.75) & (np.abs(z - 93.6) < 0.6), "15131d")
    # шрам через левый глаз
    scar = face & (x < -0.8) & (x > -4.6) & (np.abs((z - 93.6) + 1.3 * (x + 2.2)) < 0.55) & (np.abs(z - 93.6) < 3.2)
    fix(scar & ~((np.abs(x + 2.2) < 0.75) & (np.abs(z - 93.6) < 0.6)), "6e3440")

    # манометры: светлый циферблат наружу, тёмная ось стрелки
    for g, cx, cy in (("bl_gauge", 19.1, 1.6), ("sk_gauge", 18.4, 1.8)):
        face_g = (name == g) & (x > cx + 0.25)
        fix(face_g, "c4bfcc")
        fix(face_g & (np.abs(y - cy) < 0.5) & (np.abs(z - 55.0) < 0.5), "15131d")
    # дуло обреза и латунные донца гильз
    fix((name == "sg_barrel") & (z < 41.6) & (np.hypot(x - 16.2, y - 3.85) < 1.5), "0b0a10")
    R((name == "sg_shells") & (z < 52.8), "brass")


# ---------- рендер ----------
def render(alpha_deg, bones):
    a = math.radians(alpha_deg)
    ca, sa = math.cos(a), math.sin(a)
    rot = np.array([[ca, sa, 0], [-sa, ca, 0], [0, 0, 1]])  # мир -> тело (поворот на -alpha)

    f = np.array([0, -math.cos(PITCH), -math.sin(PITCH)])
    Rv = np.array([-1.0, 0, 0])
    Uv = np.array([0, -math.sin(PITCH), math.cos(PITCH)])
    L = -0.55 * Rv + 0.70 * Uv - 0.45 * f
    L /= np.linalg.norm(L)

    cols, rows = np.meshgrid(np.arange(W), np.arange(H))
    u = (cols + 0.5 - PIVOT[0]).ravel()
    v = (PIVOT[1] - (rows + 0.5)).ravel()
    o = u[:, None] * Rv + v[:, None] * Uv - RAY_NEAR * f
    o, d = o @ rot.T, np.tile(f @ rot.T, (len(u), 1))
    Lb, Vb = L @ rot.T, -(f @ rot.T)

    sc = lambda q: scene(q, bones)
    t = np.zeros(len(u))
    hit = np.zeros(len(u), bool)
    alive = np.ones(len(u), bool)
    for _ in range(240):
        idx = np.nonzero(alive)[0]
        if not len(idx):
            break
        dist, _ = sc(o[idx] + t[idx, None] * d[idx])
        h = dist < 0.02
        hit[idx[h]] = True
        alive[idx[h]] = False
        t[idx[~h]] += np.maximum(dist[~h] * 0.7, 0.02)
        alive &= t <= RAY_FAR

    n = len(u)
    ramp = np.array(["" for _ in range(n)], dtype=object)
    shade = np.zeros(n, int)
    fixed = -np.ones(n, int)
    part = -np.ones(n, int)

    hi = np.nonzero(hit)[0]
    p = o[hi] + t[hi, None] * d[hi]
    _, pid = sc(p)
    e = 0.05
    nrm = np.stack([sc(p + np.eye(3)[k] * e)[0] - sc(p - np.eye(3)[k] * e)[0] for k in range(3)], -1)
    nrm /= np.maximum(length(nrm), 1e-6)[:, None]

    lam = np.clip(nrm @ Lb, 0, 1)
    val = 0.12 + 0.88 * lam
    val = np.clip(val + np.array([LIFT.get(PARTS[i][1], 0) for i in pid]), 0, 1)
    val *= 0.82 + 0.18 * np.clip(p[:, 2] / 45.0, 0, 1)  # темнее к низу
    refl = 2 * (nrm @ Lb)[:, None] * nrm - Lb
    spec = np.clip(refl @ Vb, 0, 1) ** 18

    rp = np.array([PARTS[i][1] for i in pid], dtype=object)
    lo = np.array([SHADE[r][0] for r in rp])
    hi_ = np.array([SHADE[r][1] for r in rp])
    sidx = np.minimum(lo + np.floor(val * (hi_ - lo + 1)).astype(int), hi_)
    for r, top in SPEC.items():
        sidx[(rp == r) & (spec > 0.55)] = top

    # роспись в координатах покоя своей кости
    prest = np.zeros_like(p)
    for i, (_, _, bone, _, _) in enumerate(PARTS):
        m = pid == i
        if m.any():
            prest[m] = to_rest(p[m], bone, bones)
    ramp_h, idx_h, fix_h = rp.copy(), sidx.copy(), -np.ones(len(hi), int)
    paint(prest, pid, ramp_h, idx_h, fix_h)
    ramp[hi], shade[hi], fixed[hi], part[hi] = ramp_h, idx_h, fix_h, pid

    tt = np.full(n, np.inf)
    tt[hi] = t[hi]
    return (ramp.reshape(H, W), shade.reshape(H, W), fixed.reshape(H, W),
            part.reshape(H, W), tt.reshape(H, W))


def compose(ramp, shade, fixed, part, tt):
    hit = part >= 0
    shade = shade.copy()
    # стыки по глубине: пиксель за краем более близкой детали темнеет на шаг
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb = np.roll(np.roll(tt, dy, 0), dx, 1)
        nbp = np.roll(np.roll(part, dy, 0), dx, 1)
        m = hit & (nb < tt - 3.0) & (nbp != part)
        shade[m] -= 1
    shade = np.maximum(shade, 0)

    img = np.zeros((H, W, 4), np.uint8)
    protect = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            if not hit[y, x]:
                continue
            if fixed[y, x] >= 0:
                hx = PAL[fixed[y, x]]
                protect[y, x] = True
            else:
                r = RAMPS[ramp[y, x]]
                hx = r[min(shade[y, x], len(r) - 1)]
            img[y, x] = [int(hx[i:i + 2], 16) for i in (0, 2, 4)] + [255]

    # чистка одиночных пикселей шума (детали не трогаем)
    out = img.copy()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if not hit[y, x] or protect[y, x]:
                continue
            nb = [tuple(img[y + dy, x + dx]) for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0))]
            if all(n == nb[0] for n in nb) and nb[0] != tuple(img[y, x]) and nb[0][3] == 255:
                out[y, x] = nb[0]
    img = out

    # sel-out: внешний контур самым тёмным тоном рампы соседа
    out = img.copy()
    for y in range(H):
        for x in range(W):
            if img[y, x, 3]:
                continue
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and hit[ny, nx]:
                    hx = RAMPS[ramp[ny, nx] or "cloth"][0]
                    out[y, x] = [int(hx[i:i + 2], 16) for i in (0, 2, 4)] + [255]
                    break
    return Image.fromarray(out, "RGBA")


def gait_speed(kind):
    """Скорость без проскальзывания стоп, м/с: стопа проходит 2A за долю опоры цикла."""
    g = GAIT[kind]
    cycle_units = 2 * g["A"] / g["stance"]
    return cycle_units * UNIT_M / (g["frames"] / g["fps"])


def main(outdir, which):
    os.makedirs(outdir, exist_ok=True)
    for anim in which:
        pose_fn, frames = ANIMS[anim]
        poses = [pose_fn(i / frames) for i in range(frames)]
        for dname, a in DIRS.items():
            for i, bones in enumerate(poses):
                compose(*render(a, bones)).save(os.path.join(outdir, f"hero_{anim}_{dname}_{i}.png"))
        extra = f", fps {GAIT[anim]['fps']}, скорость {gait_speed(anim):.2f} м/с" if anim in GAIT else ""
        print(f"{anim}: {frames} кадр. x 8 направлений{extra}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:] or list(ANIMS))
