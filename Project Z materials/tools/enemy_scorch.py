"""Обгоревшие листы противника (раунд 7): те же кадры, цвета перекрашены таблицей внутри палитры PZ-28.

Кожа становится бурой, одежда тёмно-серой, детали читаются; кровь остаётся кровью; по телу тлеют редкие угли.
Лист <имя>.png -> <имя>_s.png: живой E_*, трупы C_*, тела T_*, куски P_*.

python tools/enemy_scorch.py
"""
import glob
import os
import random
import shutil

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "art", "enemy")
GAME = r"C:\project Z\z\assets\enemy"


def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# исходный цвет -> подпалённый; всё, чего нет в таблице (кровь, мясо, контур), остаётся
MAP = {c(a): c(b) for a, b in {
    "f0cdb4": "a35a5a", "d49a86": "6e3440", "a35a5a": "6e3440", "6e3440": "3b1f28", "3b1f28": "211e2c",   # кожа, жилет
    "c4bfcc": "6b6578", "948ea0": "4a4558", "6b6578": "322e40", "4a4558": "211e2c", "322e40": "15131d",   # рубашка
    "211e2c": "15131d",
    "e0b84a": "9a7a2e", "9a7a2e": "4a3a1c", "4a3a1c": "322e40",                                           # латунь, штаны
    "ece8ee": "948ea0"}.items()}
EMBER = [(c("7d0f1c"), 0.02), (c("b3162a"), 0.008), (c("e0b84a"), 0.003)]
KEEP = {c(h) for h in ("2a0509", "4f0a12", "7d0f1c", "b3162a", "e02a3c", "f0505a")}    # кровь


def scorch(im, seed):
    im = im.convert("RGBA")
    rnd = random.Random(seed)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a or (r, g, b) in KEEP:
                continue
            col = MAP.get((r, g, b), (r, g, b))
            t = rnd.random()
            for ember, p in EMBER:
                if t < p:
                    col = ember
                    break
                t -= p
            px[x, y] = col + (255,)
    return im


def main():
    n = 0
    for pat in ("E_*.png", "C_*.png", "T_*.png", "P_*.png"):
        for f in sorted(glob.glob(os.path.join(SRC, pat))):
            name = os.path.basename(f)[:-4]
            if name.endswith("_s") or name.startswith(("E_burn", "C_burn", "T_burn")):
                continue
            if name[:2] == "C_" and name.count("_") < 2:   # старые листы без падения
                continue
            out = os.path.join(SRC, name + "_s.png")
            scorch(Image.open(f), sum(map(ord, name))).save(out)
            shutil.copy2(out, os.path.join(GAME, name + "_s.png"))
            n += 1
    print("обгоревших листов:", n)


if __name__ == "__main__":
    main()