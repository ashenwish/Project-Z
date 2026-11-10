"""Перенос мокапа (BVH, CMU) на скелет героя из hero_render.py.

Позы переносятся по направлениям костей: берём из BVH положения суставов (прямая кинематика),
масштабируем под рост героя и подставляем в IK ног и направления рук. Корень записи
сводится к месту (анимация на месте), лицо первого кадра разворачивается на +y.

python tools/mocap.py info   <file.bvh>
python tools/mocap.py render <file.bvh> <start> <end> <frames> <out_dir> [name] [dirs]
"""
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_render as hr  # noqa: E402


# ---------- BVH ----------
class Bvh:
    def __init__(self, path):
        self.names, self.parent, self.offset, self.chan = [], [], [], []
        self.frame_time, data = 1 / 120, []
        stack, cur, mode = [], -1, "hier"
        with open(path, encoding="ascii", errors="ignore") as f:
            for raw in f:
                t = raw.split()
                if not t:
                    continue
                if mode == "hier":
                    if t[0] in ("ROOT", "JOINT"):
                        self.names.append(t[1])
                        self.parent.append(cur)
                        self.offset.append(np.zeros(3))
                        self.chan.append([])
                        cur = len(self.names) - 1
                    elif t[0] == "End":
                        stack.append(cur)
                        cur = -2  # End Site, пропускаем его блок
                    elif t[0] == "OFFSET" and cur >= 0:
                        self.offset[cur] = np.array(t[1:4], float)
                    elif t[0] == "CHANNELS" and cur >= 0:
                        self.chan[cur] = t[2:]
                    elif t[0] == "{":
                        if cur != -2:
                            stack.append(cur)
                    elif t[0] == "}":
                        if cur == -2:
                            cur = stack.pop()
                        else:
                            stack.pop()
                            cur = self.parent[cur]
                    elif t[0] == "MOTION":
                        mode = "motion"
                else:
                    if t[0] == "Frames:":
                        continue
                    if t[0] == "Frame" and t[1] == "Time:":
                        self.frame_time = float(t[2])
                        continue
                    data.append(np.array(t, float))
        self.data = np.array(data)
        self.n = len(self.data)
        self.idx = {n: i for i, n in enumerate(self.names)}

    @staticmethod
    def _rot(axis, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        if axis == "X":
            return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
        if axis == "Y":
            return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

    def pose(self, fr):
        """Мировые положения суставов кадра fr: {имя: вектор (x, y, z) BVH}."""
        row, k = self.data[fr], 0
        pos, rot = {}, {}
        for i, name in enumerate(self.names):
            tr, R = np.zeros(3), np.eye(3)
            for ch in self.chan[i]:
                v = row[k]
                k += 1
                if ch.endswith("position"):
                    tr["XYZ".index(ch[0])] = v
                else:
                    R = R @ self._rot(ch[0], v)
            p = self.parent[i]
            if p < 0:
                pos[name], rot[name] = self.offset[i] + tr, R
            else:
                pn = self.names[p]
                pos[name] = pos[pn] + rot[pn] @ (self.offset[i] + tr)
                rot[name] = rot[pn] @ R
        return pos


def to_hero(v):
    """BVH (Y вверх, Z вперёд, правая рука -X) -> модель героя (Z вверх, +Y вперёд, правая +X)."""
    return np.array([-v[0], v[2], v[1]])


# ---------- перенос ----------
SRC = {"hip_l": "LeftUpLeg", "knee_l": "LeftLeg", "ankle_l": "LeftFoot", "toe_l": "LeftToeBase",
       "hip_r": "RightUpLeg", "knee_r": "RightLeg", "ankle_r": "RightFoot", "toe_r": "RightToeBase",
       "sh_l": "LeftArm", "el_l": "LeftForeArm", "wr_l": "LeftHand",
       "sh_r": "RightArm", "el_r": "RightForeArm", "wr_r": "RightHand",
       "neck": "Neck", "hips": "Hips"}


def load(path, mirror=False):
    """BVH (CMU) или Collada (Mixamo, Without Skin)."""
    if path.lower().endswith(".dae"):
        import mixamo_dae
        return mixamo_dae.Dae(path, mirror=mirror)
    return Bvh(path)


class Retarget:
    def __init__(self, bvh, start, end, yaw=None, pin=False):
        """yaw=None — лицо по линии бёдер первого кадра (CMU); число (рад) — фиксированный разворот,
        для Mixamo 0: персонаж смотрит в +Z записи, а бёдра в боевой стойке развёрнуты."""
        self.b = bvh
        self.pin = pin      # таз на постоянной высоте: подъём прыжка задаёт движок
        p0 = {k: to_hero(v) for k, v in bvh.pose(start).items()}
        leg = (np.linalg.norm(p0["LeftUpLeg"] - p0["LeftLeg"]) + np.linalg.norm(p0["LeftLeg"] - p0["LeftFoot"]))
        self.scale = (hr.L_THIGH + hr.L_SHIN) / leg
        if yaw is None:
            hl = p0["RightUpLeg"] - p0["LeftUpLeg"]
            yaw = math.atan2(hl[1], hl[0])
        elif isinstance(yaw, tuple) and yaw[0] == "shoulders":
            # лицом туда, куда смотрит грудь в кадре удара: удар уходит вперёд, а не вбок
            q = {k: to_hero(v) for k, v in bvh.pose(yaw[1]).items()}
            sl = q["RightArm"] - q["LeftArm"]
            yaw = math.atan2(sl[1], sl[0])
        self.yaw = yaw
        self.hips0 = p0["Hips"]
        # уровень пола: самая низкая стопа за весь диапазон
        lo = 1e9
        for fr in range(start, end + 1):
            q = bvh.pose(fr)
            for n in ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"):
                lo = min(lo, to_hero(q[n])[2])
        self.floor = lo

    def joints(self, fr):
        q = self.b.pose(fr)
        c, s = math.cos(-self.yaw), math.sin(-self.yaw)
        Ry = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        out = {k: Ry @ (to_hero(q[n]) - np.array([self.hips0[0], self.hips0[1], 0])) * self.scale
               for k, n in SRC.items()}
        # анимация на месте: горизонталь таза снимаем (она уходит в root_motion), высоту оставляем
        shift = np.array([out["hips"][0], out["hips"][1], self.floor * self.scale])
        res = {k: v - shift for k, v in out.items()}
        if self.pin:
            dz = np.array([0, 0, res["hips"][2] - hr.J["pelvis"][2]])
            res = {k: v - dz for k, v in res.items()}
        return res

    def root_motion(self, fr):
        """Смещение корпуса от начала, в метрах (x — вправо героя, y — вперёд)."""
        q = self.b.pose(fr)
        c, s = math.cos(-self.yaw), math.sin(-self.yaw)
        d = to_hero(q["Hips"]) - self.hips0
        v = np.array([c * d[0] - s * d[1], s * d[0] + c * d[1]]) * self.scale
        return v * hr.UNIT_M

    def pose(self, fr):
        """Позы костей героя для кадра fr (формат make_pose)."""
        j = self.joints(fr)
        J = hr.J
        # таз: положение по бёдрам, ось вращения — линия бёдер и вертикаль таза
        hip_mid = (j["hip_l"] + j["hip_r"]) / 2
        spine_up = j["neck"] - j["hips"]
        Rp = frame_rot(J["hip_r"] - J["hip_l"], np.array([0, 0, 1.0]),
                       j["hip_r"] - j["hip_l"], spine_up)
        # грудь: линия плеч и позвоночник
        Rc = frame_rot(J["sh_r"] - J["sh_l"], np.array([0, 0, 1.0]),
                       j["sh_r"] - j["sh_l"], spine_up)
        rest_hip_mid = (J["hip_l"] + J["hip_r"]) / 2
        # смещение таза: высота берётся из записи, горизонталь тоже (раскачка корпуса)
        t_pelvis = np.array([hip_mid[0], hip_mid[1], hip_mid[2] - rest_hip_mid[2]])

        def P(v):
            return Rp @ (v - J["pelvis"]) + J["pelvis"] + t_pelvis

        def C(v):
            return Rc @ (v - J["chest"]) + P(J["chest"])

        bones = {"chest": (Rc, P(J["chest"]), J["chest"])}
        for s in ("l", "r"):
            hip = P(J["hip_" + s])
            target = j["ankle_" + s].copy()
            knee, ank = hr.leg_ik(hip, target)
            bones["thigh_" + s] = (hr.rot_between(J["knee_" + s] - J["hip_" + s], knee - hip), hip, J["hip_" + s])
            bones["shin_" + s] = (hr.rot_between(J["ankle_" + s] - J["knee_" + s], ank - knee), knee, J["knee_" + s])
            sh = C(J["sh_" + s])
            d_up = j["el_" + s] - j["sh_" + s]
            d_lo = j["wr_" + s] - j["el_" + s]
            l_up = np.linalg.norm(J["el_" + s] - J["sh_" + s])
            el = sh + d_up / np.linalg.norm(d_up) * l_up
            bones["uarm_" + s] = (hr.rot_between(J["el_" + s] - J["sh_" + s], d_up), sh, J["sh_" + s])
            bones["farm_" + s] = (hr.rot_between(J["wr_" + s] - J["el_" + s], d_lo), el, J["el_" + s])
        return bones


def frame_rot(a_rest, up_rest, a_pose, up_pose):
    """Вращение, переводящее систему (a_rest, up_rest) в (a_pose, up_pose)."""
    def basis(a, u):
        x = a / np.linalg.norm(a)
        z = u - (u @ x) * x
        z /= np.linalg.norm(z)
        y = np.cross(z, x)
        return np.stack([x, y, z], 1)
    return basis(a_pose, up_pose) @ basis(a_rest, up_rest).T


# ---------- CLI ----------
def info(path):
    b = load(path)
    print(f"{os.path.basename(path)}: {b.n} кадров, {1 / b.frame_time:.0f} Гц, {b.n * b.frame_time:.1f} с, суставов {len(b.names)}")
    step = max(1, int(0.1 / b.frame_time))
    prev, rows = None, []
    for fr in range(0, b.n, step):
        q = b.pose(fr)
        w = to_hero(q["RightHand"])
        if prev is not None:
            rows.append((fr, float(np.linalg.norm(w - prev)) / (step * b.frame_time)))
        prev = w
    print("скорость правой кисти (ед/с) по 0.1 с, кадр:значение (каждые 5):")
    print(" ".join(f"{fr}:{v:.0f}" for fr, v in rows[::5]))


def render(path, start, end, nframes, outdir, name="attack", dirs=None):
    b = load(path)
    rt = Retarget(b, start, end, yaw=0.0 if path.lower().endswith(".dae") else None)
    os.makedirs(outdir, exist_ok=True)
    picks = [int(round(start + (end - start) * i / max(nframes - 1, 1))) for i in range(nframes)]
    poses = [rt.pose(f) for f in picks]
    ds = {k: v for k, v in hr.DIRS.items() if not dirs or k in dirs}
    for dname, a in ds.items():
        for i, bones in enumerate(poses):
            hr.compose(*hr.render(a, bones)).save(os.path.join(outdir, f"hero_{name}_{dname}_{i}.png"))
    print(f"{name}: кадры BVH {picks}")


if __name__ == "__main__":
    a = sys.argv
    if a[1] == "info":
        info(a[2])
    else:
        render(a[2], int(a[3]), int(a[4]), int(a[5]), a[6], a[7] if len(a) > 7 else "attack",
               a[8].split(",") if len(a) > 8 else None)
