"""Остаточные силуэты рывка (раунд 9): кадры рывка героя, залитые одним цветом палитры через шахматку.

Прозрачности нет: «полупрозрачность» даёт дизер. G_dash_<модуль>.png: 8 строк x кадры рывка, холст как у слоёв.

python tools/hero_ghost.py
"""
import json
import os
import shutil

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "art", "hero", "layers")
GAME = r"C:\project Z\z\assets\hero\layers"
GHOST = (0x4a, 0x45, 0x58, 255)


def cell(sheet, col, row, w, h):
    return sheet.crop((col * w, row * h, (col + 1) * w, (row + 1) * h))


def main():
    meta = json.load(open(os.path.join(SRC, "layers.json"), encoding="utf-8"))
    w, h = meta["canvas"]
    frames = meta["legs"]["dash"]["frames"]
    dirs = meta["dirs"]
    legs = Image.open(os.path.join(SRC, "L_dash.png")).convert("RGBA")
    arm = Image.open(os.path.join(SRC, "A_dash.png")).convert("RGBA")
    for m in ("blade", "sickle", "shotgun"):
        up = Image.open(os.path.join(SRC, f"U_dash_{m}.png")).convert("RGBA")
        out = Image.new("RGBA", (w * frames, h * 8), (0, 0, 0, 0))
        for r, d in enumerate(dirs):
            for f in range(frames):
                ox, oy = meta["legs"]["dash"]["offsets_px"][d][f]
                c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                c.alpha_composite(cell(legs, f, r, w, h))
                c.alpha_composite(cell(up, f, r, w, h), (max(ox, 0), max(-oy, 0)), (max(-ox, 0), max(oy, 0)))
                c.alpha_composite(cell(arm, f * 4, r, w, h), (max(ox, 0), max(-oy, 0)), (max(-ox, 0), max(oy, 0)))
                px = c.load()
                for y in range(h):
                    for x in range(w):
                        px[x, y] = GHOST if px[x, y][3] and (x + y) % 2 == 0 else (0, 0, 0, 0)
                out.paste(c, (f * w, r * h))
        p = os.path.join(SRC, f"G_dash_{m}.png")
        out.save(p)
        shutil.copy2(p, os.path.join(GAME, f"G_dash_{m}.png"))
    print("силуэты рывка готовы")


if __name__ == "__main__":
    main()