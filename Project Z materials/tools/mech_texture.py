"""Текстура меха (атлас Tripo) -> палитра PZ-28.

python tools/mech_texture.py
Вход:  art/mech/textures/steampunk_walker_3d_model_basecolor.JPEG
Выход: art/mech/textures/mech_scout_pz.png   — атлас в цветах палитры (для Blender и любых рендеров)
       art/mech/textures/mech_scout_mat.png  — карта для спрайта: R = номер рампы, G = сдвиг тона + 8,
                                               B = номер фикс. цвета в PAL + 1 (0 — нет)
Надписи на пластинах затираются (бриф: без текста), орлы остаются тёмной краской.
Запечённый в атласе свет снимается: тон берётся относительно размытой окрестности, крупные перепады уходят,
мелкие детали (швы, заклёпки, доски) остаются сдвигом тона.
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hero_render as hr  # noqa: E402

TEX = os.path.join(HERE, "..", "art", "mech", "textures")
SRC = os.path.join(TEX, "steampunk_walker_3d_model_basecolor.JPEG")

# рампы материалов меха (те же имена использует mech_render.py)
RAMPS = {
    "mbrass": ["15131d", "3e2c1c", "4a3a1c", "74582a", "9a7a2e", "e0b84a"],
    "wood": ["15131d", "3b1f28", "3e2c1c", "6e3440"],
    "hose": ["2a0509", "3b1f28", "6e3440", "a35a5a", "d49a86"],
    "gun": ["0b0a10", "211e2c", "4a4558", "6b6578", "948ea0", "c4bfcc"],
    "core": ["0b0a10", "15131d", "211e2c", "322e40"],
}
RAMP_IDS = list(RAMPS)
MID = {"mbrass": 3, "wood": 2, "hose": 2, "gun": 3, "core": 2}   # средний тон для альбедо-превью
TEXT = [(258, 220, 342, 240), (258, 282, 342, 298), (4, 598, 26, 700)]   # строки надписей в атласе
EAGLES = [(262, 236, 340, 284), (135, 375, 238, 465), (866, 405, 918, 468), (856, 822, 910, 888),
          (572, 432, 645, 482), (568, 935, 640, 990)]                     # пластины с орлами в атласе


def main():
    bgr = cv2.imread(SRC)
    # надписи: тёмные пиксели в полосах -> inpaint по окружению (цвет пластины)
    mask = np.zeros(bgr.shape[:2], np.uint8)
    lum0 = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    for x0, y0, x1, y1 in TEXT:
        reg = lum0[y0:y1, x0:x1]
        mask[y0:y1, x0:x1] = (reg < np.percentile(reg, 60)).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8))
    clean = cv2.inpaint(bgr, mask, 4, cv2.INPAINT_TELEA)
    clean = cv2.medianBlur(clean, 3)                     # шум JPEG

    hsv = cv2.cvtColor(clean, cv2.COLOR_BGR2HSV).astype(float)
    h, s, v = hsv[..., 0] * 2, hsv[..., 1] / 255, hsv[..., 2] / 255
    lum = cv2.cvtColor(clean, cv2.COLOR_BGR2GRAY).astype(float)

    cls = np.full(lum.shape, RAMP_IDS.index("core"))
    fixed = np.zeros(lum.shape, int)
    # оттенок в атласе идёт плавно 0..40° вместе с яркостью: тёмное красноватое — дерево, остальное тёплое — латунь
    warm = (h < 50) & (s > 0.25) & (v > 0.10)
    copper = (h >= 8) & (h < 24) & (s > 0.6) & (v > 0.45)
    wood = warm & (h < 14) & (s > 0.32) & (v > 0.12) & (v < 0.27) & ~copper   # только явно красноватые доски
    brass = warm & ~wood & ~copper
    steel = (s < 0.25) & (v > 0.24)
    cls[steel] = RAMP_IDS.index("gun")
    cls[wood] = RAMP_IDS.index("wood")
    cls[copper] = RAMP_IDS.index("hose")
    cls[brass] = RAMP_IDS.index("mbrass")
    white = (s < 0.18) & (v > 0.68)
    red = ((h < 10) | (h > 340)) & (s > 0.5) & (v > 0.32)
    fixed[white] = hr.PAL.index("c4bfcc") + 1
    fixed[red] = hr.PAL.index("b3162a") + 1
    # эмблемы: тёмное внутри латунной пластины -> тёмная краска
    plates = np.zeros(lum.shape, bool)
    for x0, y0, x1, y1 in EAGLES:
        plates[y0:y1, x0:x1] = True
    fixed[(v < 0.3) & plates & ~brass] = hr.PAL.index("15131d") + 1

    # мелкая деталь относительно окрестности (снимает запечённый свет)
    d = lum - cv2.GaussianBlur(lum, (0, 0), 6)
    off = np.zeros(lum.shape, int)
    off[d < -22] = -1                                    # пороги выше: остаются явные швы и детали, не зерно
    off[d < -45] = -2
    off[d > 26] = 1
    off[brass & (v < 0.28)] -= 1                         # состаренная тёмная латунь
    off = cv2.medianBlur((off + 8).astype(np.uint8), 5).astype(int) - 8   # без одиночных крапинок
    cls = cv2.medianBlur(cls.astype(np.uint8), 5).astype(int)

    mat = np.stack([cls, off + 8, fixed], -1).astype(np.uint8)
    Image.fromarray(mat).save(os.path.join(TEX, "mech_scout_mat.png"))

    # альбедо в палитре: средний тон рампы + сдвиг; фикс. цвета как есть
    rgb = np.zeros(lum.shape + (3,), np.uint8)
    for i, r in enumerate(RAMP_IDS):
        cols = np.array([[int(x[k:k + 2], 16) for k in (0, 2, 4)] for x in RAMPS[r]], np.uint8)
        m = cls == i
        rgb[m] = cols[np.clip(MID[r] + off[m], 0, len(cols) - 1)]
    for k in np.unique(fixed[fixed > 0]):
        hx = hr.PAL[k - 1]
        rgb[fixed == k] = [int(hx[j:j + 2], 16) for j in (0, 2, 4)]
    Image.fromarray(rgb).save(os.path.join(TEX, "mech_scout_pz.png"))
    used = {tuple(c) for c in rgb.reshape(-1, 3)}
    pal = {tuple(int(x[k:k + 2], 16) for k in (0, 2, 4)) for x in hr.PAL}
    assert used <= pal, "цвета вне палитры"
    print("классы:", {r: int((cls == i).sum()) for i, r in enumerate(RAMP_IDS)}, "фикс:", int((fixed > 0).sum()))


if __name__ == "__main__":
    main()
