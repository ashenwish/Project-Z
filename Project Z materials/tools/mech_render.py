"""Спрайт меха-разведчика: модель из Blender (tools/mech_blender.py) + пилот из пайплайна героя/врагов.

python tools/mech_render.py [dir ...]   -> art/mech/render/mech_scout_idle_<dir>_0.png
Мех: материал и мелкая деталь — из карты текстуры (tools/mech_texture.py) по UV, свет — как в hero_render.render.
Пилот: детали рабочего из enemy_render (без кепки) + кожаный шлем с очками, тёмный китель, сидит в кабине.
Пилот и мех сводятся по глубине и вместе проходят hero_render.compose: стыки и контур sel-out общие.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.environ.get("PZ_MATERIALS_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools")
sys.path.insert(0, HERE)
import hero_render as hr  # noqa: E402
import enemy_render as er  # noqa: E402  (правая рука человека, детали рабочего)
import mech_texture as mt  # noqa: E402

RD = os.environ.get("PZ_MECH_RENDER_DIR", os.path.join(ROOT, "art", "mech", "render"))
S = 1 / 56
CAN, PIVOT = 256, (128, 218)           # как в mech_blender.py

hr.RAMPS.update(mt.RAMPS)
hr.RAMPS.update({"tunic": ["0b0a10", "15131d", "211e2c", "322e40", "4a4558"]})
hr.SHADE.update({"mbrass": (1, 4), "wood": (1, 3), "tunic": (1, 3)})
hr.SPEC.update({"mbrass": 5})
GAMMA = {"mbrass": 1.5}                # латунь: средние тона темнее, тени коричневые
EDGE = {"mbrass": (0.88, 5)}           # фаска прямо на свет -> яркая кромка
PILOT_OUTCOME = "live"

# ---------- пилот ----------
PILOT_AT = np.array([8.2, -9.5, 88.0])    # пол кабины под пилотом (px, оси меха): габариты пилота Tripo x 1.35


def helmet(p):
    crown = np.maximum(hr.ellipsoid(p, (0, -0.4, 96.8), (6.6, 7.2, 5.8)), 93.4 - p[:, 2])
    flaps = np.minimum(hr.capsule(p, (-6.0, -0.6, 94.0), (-5.6, 0.2, 89.6), 1.7),
                       hr.capsule(p, (6.0, -0.6, 94.0), (5.6, 0.2, 89.6), 1.7))
    return np.minimum(crown, flaps)


def goggles(p):
    return np.minimum(hr.ring_seg(p, (-2.5, 5.2, 97.6), (-2.5, 6.6, 97.8), 2.0, 0.7),
                      hr.ring_seg(p, (2.5, 5.2, 97.6), (2.5, 6.6, 97.8), 2.0, 0.7))


REMAP = {"shirt": "tunic", "trou": "pants"}
PILOT_PARTS = [(n, REMAP.get(r, r), b, f, False) for n, r, b, f, _ in er.BASE if n not in ("cap", "guts", "hair")]
PILOT_PARTS = [(n, "tunic" if n.startswith("farm") else ("leather" if n.startswith("hand") else r), b, f, c)
               for n, r, b, f, c in PILOT_PARTS]
PILOT_PARTS += [("helmet", "leather", "chest", helmet, False), ("goggles", "steel", "chest", goggles, False)]


def pilot_paint(p, part, ramp, idx, fixed):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    name = hr.NAMES[part]

    def fix(m, hexc):
        fixed[m] = hr.PAL.index(hexc)

    t = name == "torso"
    ramp[t & (z < 55.0)] = "pants"
    belt = t & (z >= 55.0) & (z < 57.4)
    ramp[belt] = "leather"
    front = y > 2.0
    for s in (-1, 1):
        fix(t & front & (np.abs(x - s * 3.6) < 1.2) & (np.abs(z - 81.0) < 1.0), "7d0f1c")    # петлицы
    fix(t & front & (np.abs(x + 0.8) < 0.6) & (np.round(z) % 5 == 0) & (z > 60) & (z < 78), "9a7a2e")  # пуговицы
    h = name == "head"
    face = h & (y > 3.0)
    for s in (-1, 1):
        fix(face & (np.abs(x - s * 2.2) < 0.75) & (np.abs(z - 93.6) < 0.6), "15131d")
    fix(face & (np.abs(z - 90.2) < 0.45) & (np.abs(x) < 1.1), "6e3440")
    fix((name == "goggles") & (y > 6.3), "6b6578")
    if PILOT_OUTCOME == "bullet":
        ctr, radius = er.CUR["crater"]
        wound = t & (np.abs(hr.length(p-ctr)-radius)<1.2)
        fix(wound, "b3162a")
        fix(wound & (x<0), "7d0f1c")
        fix(t & front & (np.abs(x)<2) & (z>59) & (z<75), "7d0f1c")
    if PILOT_OUTCOME in ("decap", "head_piece"):
        cut = (name=="neck") & (np.abs(z-86)<1)
        fix(cut, "b3162a")
        fix(cut & (np.hypot(x,y-.6)<1.1), "c4bfcc")


def pilot_layers(dz=0.0, death=0.0, outcome="live"):
    """dz — смещение корпуса меха в кадре (mech_<anim>.json, body_dz_px): пилот едет вместе с кабиной."""
    global PILOT_OUTCOME
    PILOT_OUTCOME = outcome
    cuts, crater, drop = [], None, set()
    if outcome == "bullet":
        crater = (np.array([0.0, 7.0, 77.0]), 5.5)
    if outcome == "decap":
        drop = {"head", "helmet", "goggles"}
        cuts = [({"neck"}, np.array([0., 0., 1.]), 86., .6)]
    if outcome == "head_piece":
        drop = {n for n, *_ in PILOT_PARTS} - {"head", "helmet", "goggles", "neck"}
        cuts = [({"neck"}, np.array([0., 0., -1.]), -86., .6)]
    er.CUR.update(cuts=cuts, crater=crater, gash=False)
    hr.PARTS[:] = [(n, r, bone, er.wrap(n, fn), clip) for n,r,bone,fn,clip in PILOT_PARTS if n not in drop] if outcome!="live" else PILOT_PARTS
    hr.NAMES = np.array([n for n, *_ in hr.PARTS])
    hr.ACTIVE = list(range(len(hr.PARTS)))
    hr.paint = pilot_paint
    hr.W, hr.H, hr.PIVOT = CAN, CAN, PIVOT
    # сидит: таз опущен на высоту сиденья, стопы вперёд на полу, руки на рычагах перед собой
    b = hr.make_pose({"l": (-6.8, 18.0, 4.0), "r": (6.8, 18.0, 4.0)}, bob=-26.0-4*death, lean=6+35*death,
                     arm_l=(52-45*death, 34-20*death), arm_r=(52-45*death, 34-20*death))
    b = er.rotate_bones(b, np.eye(3), (0, 0, 0), PILOT_AT + np.array([0, 0, dz]))
    return b


# ---------- сборка ----------
def light(d):
    a = math.radians(hr.DIRS[d])
    ca, sa = math.cos(a), math.sin(a)
    rot = np.array([[ca, sa, 0], [-sa, ca, 0], [0, 0, 1]])
    f = np.array([0, -math.cos(hr.PITCH), -math.sin(hr.PITCH)])
    Rv, Uv = np.array([-1.0, 0, 0]), np.array([0, -math.sin(hr.PITCH), math.cos(hr.PITCH)])
    L = -0.55 * Rv + 0.70 * Uv - 0.45 * f
    return (L / np.linalg.norm(L)) @ rot.T, -(f @ rot.T), f @ rot.T


def compose(anim, d, i, dz=0.0, body_matrix=None, pilot=True, death=0.0, outcome="live", geometry=None):
    P = np.load(os.path.join(RD, f"passes_{geometry or anim}_{d}_{i}.npz"))
    mat = np.array(Image.open(os.path.join(HERE, "..", "art", "mech", "textures", "mech_scout_mat.png")))
    idp, nrm, pos, uv = P["id"], P["normal"], P["pos"], P["uv"]
    hit = idp[..., 3] > 0.5
    obj = np.rint(idp[..., 0]).astype(int)
    n = nrm[..., :3] * 2 - 1
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    p = (pos[..., :3] - 0.5) / 0.05 / S
    Lb, Vb, Fb = light(d)
    th, tw = mat.shape[:2]
    tx = np.clip((uv[..., 0] % 1.0 * tw).astype(int), 0, tw - 1)
    ty = np.clip(((1 - uv[..., 1] % 1.0) * th).astype(int), 0, th - 1)
    m = mat[ty, tx]

    ramp = np.full((CAN, CAN), "", dtype=object)
    shade = np.zeros((CAN, CAN), int)
    fixed = -np.ones((CAN, CAN), int)
    part = np.where(hit, obj, -1)
    tt = np.where(hit, hr.RAY_NEAR + p @ Fb, np.inf)       # та же мера, что t в hero_render.render
    lam = np.clip(n @ Lb, 0, 1)
    val = (0.12 + 0.88 * lam) * (0.82 + 0.18 * np.clip(p[..., 2] / 45.0, 0, 1))
    for y, x in zip(*np.nonzero(hit)):
        cls, off, fx = m[y, x]
        if fx:
            fixed[y, x] = fx - 1
            ramp[y, x] = "core"
            continue
        r = mt.RAMP_IDS[cls]
        lo, hi = hr.SHADE[r]
        s = min(lo + int(math.floor(val[y, x] ** GAMMA.get(r, 1.0) * (hi - lo + 1))), hi)
        if r in EDGE and lam[y, x] > EDGE[r][0]:
            s = EDGE[r][1]
        ramp[y, x], shade[y, x] = r, int(np.clip(s + int(off) - 8, 0, len(hr.RAMPS[r]) - 1))

    # пилот тем же рендером, что враги; сводим по глубине
    near = np.zeros((CAN, CAN), bool)
    if pilot:
        bones = pilot_layers(dz if body_matrix is None else 0, death or 0.0, outcome)
        if body_matrix is not None:
            M = np.array(body_matrix)
            bones = er.rotate_bones(bones, M[:3, :3], (0, 0, 0), M[:3, 3])
        pr, ps, pf, pp, pt = hr.render(hr.DIRS[d], bones)
        near = (pp >= 0) & (pt < tt)
        ramp[near], shade[near], fixed[near], part[near], tt[near] = pr[near], ps[near], pf[near], pp[near] + 1000, pt[near]

    hr.W, hr.H = CAN, CAN
    img = hr.compose(ramp, shade, fixed, part, tt)
    img.save(os.path.join(RD, f"mech_scout_{anim}_{d}_{i}.png"))
    return int(near.sum())


def pilot_head():
    global CAN, PIVOT
    CAN, PIVOT = 64, (32, 32)
    b = pilot_layers(outcome="head_piece")
    R, jp, jr = b["chest"]
    center = R@(np.array([0., .8, 93.])-jr)+jp
    hr.W, hr.H, hr.PIVOT = CAN, CAN, PIVOT
    for i in range(8):
        t = i*math.tau/8
        M = hr.rz(t*2) @ hr.rx(t)
        bones = er.rotate_bones(b, M, center, -center)
        hr.compose(*hr.render(0, bones)).save(os.path.join(RD, f"mech_pilot_head_s_{i}.png"))
    json.dump({"frames":8, "canvas":[64,64], "pivot":[32,32], "durations_ms":[70]*8,
               "source_center_px":center.tolist()}, open(os.path.join(RD,"mech_pilot_head.json"),"w"), indent=2)


# точки на корпусе (px, оси меха, поза покоя): верх двух выхлопных труб (U-труба за кабиной), грудь пилота, центр кабины
ANCHORS = {"steam_r": (31.3, -61.3, 177.0), "steam_l": (-23.8, -53.5, 172.0),
           "pilot": tuple(PILOT_AT + np.array([0.0, 0.3, 31.0])), "body": (5.0, -15.0, 120.0),
           "pilot_hit": tuple(PILOT_AT + np.array([0., 10., 51.])),
           "muzzle": (-30.55, 66.3, 149.7), "eject": (-36.5, 7.0, 145.0), "foot_r": (44.0, -5.0, 0.5)}


def project(p, d):
    """Точка (px, оси меха) -> пиксель кадра (x, y), та же камера, что hero_render.render."""
    a = math.radians(hr.DIRS[d])
    ca, sa = math.cos(a), math.sin(a)
    rot = np.array([[ca, sa, 0], [-sa, ca, 0], [0, 0, 1]])
    Rb = np.array([-1.0, 0, 0]) @ rot.T
    Ub = np.array([0, -math.sin(hr.PITCH), math.cos(hr.PITCH)]) @ rot.T
    p = np.array(p, float)
    return [round(PIVOT[0] - 0.5 + float(p @ Rb), 1), round(PIVOT[1] - 0.5 - float(p @ Ub), 1)]


if __name__ == "__main__":
    # python tools/mech_render.py <anim> [dir ...]
    anim = sys.argv[1] if len(sys.argv) > 1 else "idle"
    if anim == "pilot_head":
        pilot_head()
        raise SystemExit(0)
    mp = os.path.join(RD, f"mech_{anim}.json")
    source_meta = os.path.join(RD,"mech_die.json") if anim=="die_decap" else mp
    meta = json.load(open(source_meta, encoding="utf-8"))
    if anim=="die_decap":
        meta.update(pilot_outcome="decap", geometry_animation="die")
        meta["events"]["head_detached"]=[0]
        meta.pop("visible_pilot_pixels",None)
    CAN, _ = meta["canvas"]
    PIVOT = tuple(meta["pivot"])
    dirs = sys.argv[2:] or list(hr.DIRS)
    for d in dirs:
        seen = [compose(anim, d, i, dz, meta.get("body_matrix_px", [None] * meta["frames"])[i],
                        meta.get("pilot", True) and meta.get("pilot_death", [0]*meta["frames"])[i] is not None,
                        meta.get("pilot_death", [0]*meta["frames"])[i], meta.get("pilot_outcome","live"), meta.get("geometry_animation"))
                for i, dz in enumerate(meta["body_dz_px"])]
        meta.setdefault("visible_pilot_pixels", {})[d] = seen
        print(anim, d, "кадров", len(seen), "пилот px", seen)
    # якоря по кадрам: {точка: {направление: [[x, y] на кадр]}}; корпус качается на body_dz_px
    if meta.get("pilot", True):
        body_mats = meta.get("body_matrix_px", [np.eye(4)] * meta["frames"])
        points = {}
        for k, v in ANCHORS.items():
            track = "gun_matrix_px" if k in ("muzzle", "eject") else "foot_r_matrix_px" if k == "foot_r" else "body_matrix_px"
            if k == "foot_r" and track not in meta:
                continue  # В старых проходах положение стопы не сохранялось.
            mats = meta.get(track, body_mats)
            points[k] = [np.array(M)[:3, :3] @ v + np.array(M)[:3, 3] if "body_matrix_px" in meta
                         else np.array(v) + [0, 0, dz] for M, dz in zip(mats, meta["body_dz_px"])]
        meta["anchors"] = {k: {d: [project(p, d) for p in ps] for d in hr.DIRS} for k, ps in points.items()}
        meta["anchors_m"] = {k: [round(c / 56, 3) for c in ANCHORS[k]] for k in points}
        meta["anchors_frames_m"] = {k: [[round(c / 56, 4) for c in p] for p in ps] for k, ps in points.items()}
    json.dump(meta, open(mp, "w", encoding="utf-8"), ensure_ascii=False)
