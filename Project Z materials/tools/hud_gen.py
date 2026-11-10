"""HUD героя (раунд 13): круглый паровой датчик по референсу пользователя, пиксельная графика в палитре PZ-28.

Кольца: внешнее — здоровье (28 сегментов), внутреннее — ульта (20 сегментов, вся латунь — раунд 14). Центр — патроны обреза и револьвера (рисует движок цифрами hud_digits).
Под кругом два переключателя рывка.

Выход (art/ui и assets/ui проекта):
  hud_full.png   всё горит            hud_empty.png  кольца пустые
  hud_glow.png   кольца ярче (готовность ульты, мало здоровья)
  hud_mask.png   R — полоса здоровья, G — полоса ульты (шейдер выбирает, какой пиксель гореть)
  hud_digits.png цифры 0-9 и «/» 4x7, две строки: обычные и тусклые (перезарядка)
  hud_icons.png  значки 5x7: гильза обреза, патрон револьвера
  hud_switch.png переключатель рывка 10x14: 3 кадра (вверх — готов, середина, вниз — занят)
  hud_plate.png  планка под переключатели

python tools/hud_gen.py
Сегменты считаются так же, как в шейдере: угол от верха по часовой, доля оборота.
"""
import json
import math
import os
import shutil

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "art", "ui")
GAME = r"C:\project Z\z\assets\ui"


def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


K0, K1, K2, K3 = c("0b0a10"), c("15131d"), c("211e2c"), c("322e40")
V1, V2, V3, V4, V5 = c("4a4558"), c("6b6578"), c("948ea0"), c("c4bfcc"), c("ece8ee")
R0, R1, R2, R3, R4, R5 = c("2a0509"), c("4f0a12"), c("7d0f1c"), c("b3162a"), c("e02a3c"), c("f0505a")
F0, F1, F2, F3, F4 = c("3b1f28"), c("6e3440"), c("a35a5a"), c("d49a86"), c("f0cdb4")
B0, B1, B2 = c("4a3a1c"), c("9a7a2e"), c("e0b84a")
CLEAR = (0, 0, 0, 0)

W, H = 104, 104              # раунд 16: без внешнего обода и щитков
CX, CY = 52.0, 52.0
HP_SEGS, ULT_SEGS = 12, 6     # раунд 16: меньше делений (было 28 и 20)
HP_R = (37.0, 50.0)           # раунд 16: кольца толще — здоровье 13 px (было 9), ульта 11 px (было 8)
ULT_R = (24.0, 35.0)
CENTER_R = 22.0

yy, xx = np.mgrid[0:H, 0:W]
PX = xx + 0.5 - CX
PY = yy + 0.5 - CY
RR = np.hypot(PX, PY)
ANG = np.mod(np.arctan2(PX, -PY) / (2 * np.pi), 1.0)          # 0 сверху, по часовой
LIGHT = (-PX - PY) / np.maximum(RR, 1e-6)                        # свет сверху-слева: >0 освещено


def blank():
    return np.zeros((H, W, 4), np.uint8)


def put(img, m, col):
    img[m] = col


def seg_line(n, width=0.55):
    """Пиксели на границах сегментов (тёмные разделители)."""
    k = np.round(ANG * n)
    d = np.abs(ANG * n - k) / n * 2 * np.pi * RR
    return d < width


MB, ML, MD, MH = B0, B1, F0, B2      # бронза: основа, свет, тень, блик кромки


def brass(img, m, outer=None):
    """Бронза с объёмом: свет сверху-слева, тень снизу-справа."""
    put(img, m, MB)
    put(img, m & (LIGHT > 0.45), ML)
    put(img, m & (LIGHT < -0.45), MD)


def frame(img):
    # внешний латунный обод убран (раунд 16): снаружи только тёмный контур
    # промежуточное кольцо между здоровьем и ультой
    mid = (RR >= ULT_R[1]) & (RR < HP_R[0])
    brass(img, mid)
    put(img, mid & ((RR < ULT_R[1] + 1) | (RR >= HP_R[0] - 1)), K1)
    # внутренний обод
    inner = (RR >= CENTER_R) & (RR < ULT_R[0])
    brass(img, inner)
    put(img, inner & ((RR < CENTER_R + 1) | (RR >= ULT_R[0] - 1)), K1)
    # центр: тёмное стекло с нижним бликом
    ctr = RR < CENTER_R
    put(img, ctr, K1)
    put(img, ctr & (RR > CENTER_R - 2) & (PY > 0), K2)
    put(img, ctr & (RR > CENTER_R - 1.2) & (LIGHT > 0.6), K3)
    # линия между строками патронов с ромбом
    line = (yy == int(CY)) & (np.abs(PX) < 13)
    put(img, line, F1)
    put(img, (np.abs(PX) + np.abs(PY) < 2.0), F2)


def rings(img, state):
    """state: 'full' | 'empty' | 'glow'."""
    hp = (RR >= HP_R[0]) & (RR < HP_R[1])
    # раунд 17: мрачнее — бордовое здоровье; яркий красный только в пульсации при малом здоровье
    if state == "empty":
        put(img, hp, R0)
        put(img, hp & (RR >= HP_R[1] - 2), K1)
    else:
        put(img, hp, R2 if state == "full" else R3)
        put(img, hp & (RR >= HP_R[1] - 2), R1 if state == "full" else R2)
        put(img, hp & (RR < HP_R[0] + 1.5) & (LIGHT > -0.2), R3 if state == "full" else R4)
    put(img, hp & seg_line(HP_SEGS), K0)
    ult = (RR >= ULT_R[0]) & (RR < ULT_R[1])
    if state == "empty":
        put(img, ult, K3)
        put(img, ult & (RR >= ULT_R[1] - 2), K2)
    else:
        # раунд 14: всё кольцо одним цветом — латунь (раньше снизу был серо-фиолетовый)
        # раунд 17: тусклая латунь; яркая e0b84a — только вспышка готовности
        glow = state == "glow"
        put(img, ult, B2 if glow else B1)
        put(img, ult & (RR >= ULT_R[1] - 2), B1 if glow else B0)
        put(img, ult & (RR < ULT_R[0] + (3.0 if glow else 1.0)) & (LIGHT > -0.2), F4 if glow else B2)
    put(img, ult & seg_line(ULT_SEGS), K0)


def rect(img, x0, y0, x1, y1, col):
    img[int(y0):int(y1), int(x0):int(x1)] = col


def draw_bitmap(img, x0, y0, rows, cmap):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in cmap:
                img[y0 + j, x0 + i] = cmap[ch]


CROSS = ["..#..", "..#..", "#####", "..#..", "..#.."]
BOLT = ["...##", "..##.", ".####", "..##.", ".##..", ".#..."]
BLAST = ["#.#.#", ".###.", "##.##", ".###.", "#.#.#"]


def details(img):
    """Накладки поверх колец: значки ульты и скобы (обод, заклёпки, щитки и труба убраны в раундах 15–16)."""
    cx, cy = int(CX), int(CY)
    ur = int(round((ULT_R[0] + ULT_R[1]) / 2))          # середина кольца ульты
    # зазоры в кольце ульты сверху и снизу со значками
    for sy, bmp, col in ((-1, BOLT, B2), (1, BLAST, F3)):
        gy = cy + sy * ur
        rect(img, cx - 4, gy - 4, cx + 4, gy + 4, K1)
        rect(img, cx - 4, gy - 4, cx + 4, gy - 3, MD)
        draw_bitmap(img, cx - 3 + (1 if bmp is BLAST else 0), gy - 3, bmp, {"#": col})
    # скобы на кольце ульты справа и слева
    for sx in (-1, 1):
        x = cx + sx * ur
        rect(img, x - 3, cy - 2, x + 3, cy + 3, MB)
        rect(img, x - 3, cy - 2, x + 3, cy - 1, ML)
        rect(img, x - 3, cy + 2, x + 3, cy + 3, MD)
        img[cy, x] = K1


def outline(img):
    a = img[..., 3] > 0
    grow = a.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        grow |= np.roll(np.roll(a, dy, 0), dx, 1)
    img[grow & ~a] = K0


def gauge(state):
    img = blank()
    frame(img)
    rings(img, state)
    details(img)
    outline(img)
    return img


def mask():
    """Полосы колец без накладок: R — здоровье, G — ульта."""
    ref = blank()
    rings(ref, "full")
    over = blank()
    details(over)
    free = over[..., 3] == 0
    m = np.zeros((H, W, 4), np.uint8)
    m[..., 3] = 255
    m[..., 0] = np.where((RR >= HP_R[0]) & (RR < HP_R[1]) & free, 255, 0)
    m[..., 1] = np.where((RR >= ULT_R[0]) & (RR < ULT_R[1]) & free, 255, 0)
    return m


# ---------- цифры, значки, переключатель ----------
DIGITS = {
    "0": [".##.", "#..#", "#.##", "##.#", "#..#", "#..#", ".##."],
    "1": [".#..", "##..", ".#..", ".#..", ".#..", ".#..", "###."],
    "2": [".##.", "#..#", "...#", "..#.", ".#..", "#...", "####"],
    "3": ["###.", "...#", "...#", ".##.", "...#", "...#", "###."],
    "4": ["#..#", "#..#", "#..#", "####", "...#", "...#", "...#"],
    "5": ["####", "#...", "###.", "...#", "...#", "#..#", ".##."],
    "6": [".##.", "#...", "#...", "###.", "#..#", "#..#", ".##."],
    "7": ["####", "...#", "..#.", "..#.", ".#..", ".#..", ".#.."],
    "8": [".##.", "#..#", "#..#", ".##.", "#..#", "#..#", ".##."],
    "9": [".##.", "#..#", "#..#", ".###", "...#", "...#", ".##."],
    "/": ["...#", "...#", "..#.", ".##.", ".#..", "#...", "#..."],
}
DIGIT_ORDER = "0123456789/"
SHELL = [".###.", ".#R#.", ".#R#.", ".#R#.", ".#R#.", "#BBB#", "#####"]
BULLET = ["..#..", ".#B#.", ".#B#.", "#bbb#", "#bbb#", "#bbb#", "#####"]
LEVER_UP = ["...##.....", "...##.....", "...##.....", "...##.....", "..####....", "..#..#....", "..#..#...."]
SWITCH_FRAMES = ["up", "mid", "down"]


def digits_sheet():
    n = len(DIGIT_ORDER)
    im = np.zeros((14, 4 * n, 4), np.uint8)
    for row, col in enumerate((F4, F2)):
        for k, ch in enumerate(DIGIT_ORDER):
            for j, line in enumerate(DIGITS[ch]):
                for i, px in enumerate(line):
                    if px == "#":
                        im[row * 7 + j, k * 4 + i] = col
    return im


def icons_sheet():
    im = np.zeros((7, 10, 4), np.uint8)
    for k, (bmp, cmap) in enumerate(((SHELL, {"#": K0, "R": R3, "B": B2}), (BULLET, {"#": K0, "B": B2, "b": B1}))):
        for j, line in enumerate(bmp):
            for i, px in enumerate(line):
                if px in cmap:
                    im[j, k * 5 + i] = cmap[px]
        # заливка корпуса значка
    shell = im[:, 0:5]
    shell[1:5, 1:4][shell[1:5, 1:4, 3] == 0] = R2
    shell[5, 1:4] = B1
    bullet = im[:, 5:10]
    bullet[0, 2] = B2
    return im


def switch_sheet():
    """Раунд 16: кнопка рывка, тёмно-серая. Кадры: поднята (готова), на полпути, нажата (рывок на откате).
    Нажатая ниже на 4 px и темнее, боковина не видна."""
    w, h = 10, 14
    im = np.zeros((h, w * 3, 4), np.uint8)
    for f, pos in enumerate(SWITCH_FRAMES):
        x0 = f * w
        # гнездо: тёмное кольцо, в которое уходит кнопка
        im[10:13, x0 + 1:x0 + 9] = K2
        im[10, x0 + 1:x0 + 9] = K3
        im[12, x0 + 2:x0 + 8] = K1
        top = {"up": 3, "mid": 5, "down": 7}[pos]
        face, hi = (V2, V3) if pos == "up" else ((V1, V2) if pos == "mid" else (K3, V1))
        # боковина шляпки от лица до гнезда
        if top + 3 < 11:
            im[top + 2:11, x0 + 2:x0 + 8] = V1 if pos == "up" else K3
            im[top + 2:11, x0 + 2] = K3
        # лицо шляпки: скруглённый овал
        im[top, x0 + 3:x0 + 7] = face
        im[top + 1:top + 3, x0 + 2:x0 + 8] = face
        im[top + 3, x0 + 3:x0 + 7] = face
        im[top, x0 + 3:x0 + 5] = hi                  # блик сверху-слева
        im[top + 1, x0 + 2:x0 + 4] = hi
    out = im.copy()
    a = im[..., 3] > 0
    grow = a.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        grow |= np.roll(np.roll(a, dy, 0), dx, 1)
    out[grow & ~a] = K0
    return out


def plate_sheet():
    """Планка под два тумблера, крепится к нижнему щитку датчика."""
    w, h = 34, 18
    im = np.zeros((h, w, 4), np.uint8)
    im[1:h - 1, 1:w - 1] = B1
    im[1, 1:w - 1] = B2
    im[h - 2, 1:w - 1] = B0
    im[3:h - 3, 3:w - 3] = K2
    for x in (2, w - 3):
        im[h // 2, x] = B2
    a = im[..., 3] > 0
    grow = a.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        grow |= np.roll(np.roll(a, dy, 0), dx, 1)
    im[grow & ~a] = K0
    return im


CROSSHAIR_V = ["#...#", ".#.#.", "..#.."]


def crosshair():
    """Прицел вместо курсора (раунд 15): латунное кольцо 13 px, в центре V; остриё V — в центре холста."""
    n = 15
    im = np.zeros((n, n, 4), np.uint8)
    c = (n - 1) / 2.0
    y, x = np.mgrid[0:n, 0:n]
    r = np.hypot(x - c, y - c)
    ring = (r >= 4.6) & (r < 6.0)
    im[ring] = B2
    im[ring & ((x - c) + (y - c) > 2.5)] = B1          # тень снизу-справа
    draw_bitmap(im, int(c) - 2, int(c) - 2, CROSSHAIR_V, {"#": B2})
    a = im[..., 3] > 0
    grow = a.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        grow |= np.roll(np.roll(a, dy, 0), dx, 1)
    im[grow & ~a] = K0
    return im


def save(arr, name):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(GAME, exist_ok=True)
    p = os.path.join(OUT, name)
    Image.fromarray(arr, "RGBA").save(p)
    shutil.copy2(p, os.path.join(GAME, name))


def check_palette(arr, name):
    pal = {tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in open(os.path.join(ROOT, "art", "palette", "pz-28.hex")).read().split()}
    cols = {tuple(px[:3]) for px in arr.reshape(-1, 4) if px[3]}
    bad = cols - pal
    if bad:
        print(f"{name}: вне палитры {bad}")


def main():
    for state in ("full", "empty", "glow"):
        g = gauge(state)
        check_palette(g, state)
        save(g, f"hud_{state}.png")
    save(mask(), "hud_mask.png")
    for arr, name in ((digits_sheet(), "hud_digits.png"), (icons_sheet(), "hud_icons.png"),
                      (switch_sheet(), "hud_switch.png"), (plate_sheet(), "hud_plate.png"),
                      (crosshair(), "crosshair.png")):
        check_palette(arr, name)
        save(arr, name)
    meta = {"size": [W, H], "center": [CX, CY], "hp_segs": HP_SEGS, "ult_segs": ULT_SEGS,
            "digit": [4, 7], "digit_order": DIGIT_ORDER, "icon": [5, 7], "switch": [10, 14], "plate": [34, 18]}
    with open(os.path.join(GAME, "hud.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    print("HUD готов")


if __name__ == "__main__":
    main()
