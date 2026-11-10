"""Эскизы силуэта Чернова (32x48, SE), три варианта протеза. Только цвета PZ-28.

python tools/sketch_hero_v2.py art/hero/silhouettes_v2.png
"""
import sys
from PIL import Image, ImageDraw

def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)

# PZ-28
SH = [c(h) for h in ("0b0a10", "15131d", "211e2c", "322e40", "4a4558", "6b6578", "948ea0")]
FL = [c(h) for h in ("3b1f28", "6e3440", "a35a5a", "d49a86")]
ST = [c(h) for h in ("1d2a33", "34505c", "5d8591", "9fc5c9")]
LA = [c(h) for h in ("4a3a1c", "9a7a2e", "e0b84a")]
BG = SH[1]

# sel-out: контур цветом самого тёмного тона материала соседа
DARK = {}
for fam, d in ((SH, SH[0]), (FL, FL[0]), (ST, ST[0]), (LA, LA[0])):
    for col in fam:
        DARK[col] = d


def body(d):
    """Общая фигура: пальто, ноги, голова, котёл-ранец, левая (живая) рука."""
    P = d.polygon
    # котёл за спиной, торчит над левым плечом, труба
    P([(8, 11), (12, 11), (12, 24), (8, 24)], LA[1])
    P([(8, 11), (9, 11), (9, 24), (8, 24)], LA[2])
    d.rectangle((9, 6, 10, 10), fill=ST[1])
    d.rectangle((8, 15, 12, 15), fill=LA[0])
    # ноги, сапоги
    P([(12, 38), (15, 38), (15, 45), (12, 45)], SH[2])
    P([(17, 38), (20, 38), (20, 45), (17, 45)], SH[2])
    d.rectangle((11, 44, 15, 45), fill=SH[1])
    d.rectangle((17, 44, 21, 45), fill=SH[1])
    # пальто: плечи, расширение к подолу, разрез сзади
    P([(10, 16), (21, 16), (22, 26), (23, 40), (17, 39), (16, 36), (15, 39), (9, 41), (10, 26)], SH[3])
    P([(10, 16), (13, 16), (11, 30), (9, 41), (10, 26)], SH[4])  # свет слева
    P([(14, 17), (17, 17), (16, 23), (15, 23)], SH[5])            # ворот/рубашка
    # левая рука вдоль тела
    P([(9, 18), (11, 18), (11, 30), (9, 30)], SH[4])
    d.rectangle((9, 31, 10, 32), fill=FL[3])
    # голова: волосы, лицо, гогглы на лбу, борода
    P([(13, 7), (18, 7), (19, 10), (12, 10)], FL[0])
    P([(13, 10), (18, 10), (18, 13), (13, 13)], FL[3])
    d.rectangle((13, 9, 18, 9), fill=LA[1])
    d.point((14, 9), fill=LA[2]); d.point((17, 9), fill=LA[2])
    P([(13, 13), (18, 13), (17, 16), (14, 16)], FL[1])
    d.point((15, 11), fill=FL[0]); d.point((17, 11), fill=FL[0])


def arm_blade(d):
    """А: «Богомол» — предплечье раскрывается в длинный изогнутый клинок."""
    P = d.polygon
    P([(20, 16), (23, 16), (24, 20), (21, 21)], LA[1])     # латунный плечевой узел
    P([(21, 20), (24, 20), (25, 29), (22, 29)], ST[1])     # предплечье
    d.line((23, 21, 24, 28), fill=ST[2])
    d.rectangle((21, 24, 24, 24), fill=LA[0])               # хомут
    P([(23, 28), (26, 28), (30, 40), (31, 46), (29, 46), (26, 38)], ST[2])  # клинок
    d.line((26, 29, 30, 44), fill=ST[3])


def arm_claw(d):
    """Б: «Клешня» — массивная перчатка с тремя когтями до земли."""
    P = d.polygon
    P([(20, 15), (24, 15), (25, 20), (21, 21)], LA[1])
    P([(21, 20), (25, 20), (26, 26), (22, 26)], ST[1])
    P([(21, 26), (28, 25), (29, 34), (21, 35)], LA[1])      # кожух кисти
    P([(21, 26), (23, 26), (23, 35), (21, 35)], LA[2])
    d.rectangle((24, 28, 27, 29), fill=LA[0])               # заклёпки/шов
    for x0 in (21, 24, 27):                                 # когти
        P([(x0, 35), (x0 + 2, 35), (x0 + 2, 41), (x0 + 1, 43)], ST[2])
        d.line((x0, 35, x0, 39), fill=ST[3])


def arm_piston(d):
    """В: «Поршень» — огромное предплечье-таран с поршнем и паровым клапаном."""
    P = d.polygon
    P([(20, 15), (24, 15), (25, 21), (21, 21)], LA[1])
    d.rectangle((22, 12, 23, 15), fill=ST[1])                # паровой клапан над плечом
    P([(20, 21), (28, 20), (30, 33), (21, 34)], LA[1])       # кожух
    P([(20, 21), (23, 21), (23, 34), (21, 34)], LA[2])
    d.rectangle((24, 22, 26, 31), fill=LA[0])                # цилиндр
    d.rectangle((25, 23, 25, 30), fill=ST[3])                # шток
    P([(21, 34), (29, 33), (29, 39), (22, 39)], ST[1])       # ударная плита
    d.line((22, 35, 28, 34), fill=ST[3])


def outline(im):
    src = im.load()
    out = im.copy()
    o = out.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3]:
                    o[x, y] = DARK.get(src[nx, ny], SH[0])
                    break
    return out


def make(arm):
    im = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    body(d)
    arm(d)
    return outline(im)


def main(path):
    sprites = [make(a) for a in (arm_blade, arm_claw, arm_piston)]
    s, pad = 10, 20
    W = Image.new("RGBA", (3 * 32 * s + 4 * pad, 48 * s + 2 * pad + 48 * 2 + pad), BG)
    for i, sp in enumerate(sprites):
        x = pad + i * (32 * s + pad)
        W.alpha_composite(sp.resize((32 * s, 48 * s), Image.NEAREST), (x, pad))
        y = 48 * s + 2 * pad
        W.alpha_composite(sp, (x + 32 * s // 2 - 60, y))                                  # x1
        W.alpha_composite(sp.resize((64, 96), Image.NEAREST), (x + 32 * s // 2 - 10, y))  # x2
    W.save(path)


if __name__ == "__main__":
    main(sys.argv[1])
