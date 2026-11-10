"""Эффекты (раунд 2, правки 1 и 5) в палитре PZ-28, жёсткие пиксели, без полупрозрачности.

  flash_shotgun.png  8 строк (угол экрана k*45°, 0 — вправо, по часовой) x 3 кадра, 32x32, дуло в центре
  flash_pistol.png   8 строк x 2 кадра, 16x16
  shell.png          гильза обреза, 8 углов поворота, 8x8
  steam.png          клуб пара, 6 кадров, 20x20 (рассыпается дизером, а не прозрачностью)
  chunks.png         куски мяса: 4 вида (строки) x 8 углов, 10x10
  splat_<размер>_<fresh|dried>_<n>.png  пятна крови для пола; по высоте каждая строка экрана — две строки текстуры,
                     чтобы на полу под углом 30° пиксели ложились 1:1 (декаль повёрнута на 45° по камере)
  shock_<модуль>.png удар о землю (раунд 5): кольцо пыли, 5 кадров, радиус как у сплэша (1 м = 56 px, глубина вдвое меньше)
  blast_gun.png      направленный залп обреза: 8 строк (направления героя) x 4 кадра, веер 60° на 4,5 м, вершина в центре
  crack_<l|m>_<n>.png трещины на полу, как пятна крови: две строки текстуры на строку экрана
  fire_gun.png       ульта обреза: огненный веер 80 градусов на 5,5 м, 8 строк x 4 кадра
  flame.png          пламя на горящем враге: 6 кадров 48x96, низ спрайта у стоп
  hook_tip.png       лезвие серпа на цепи: 8 углов, 20x20

python tools/fx_gen.py art/fx
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw


def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


WHITE, PALE, GREY, DARKG, SHADOW = c("ece8ee"), c("c4bfcc"), c("948ea0"), c("6b6578"), c("4a4558")
LAMP_HI, LAMP, LAMP_LO = c("e0b84a"), c("9a7a2e"), c("4a3a1c")
WET, RED, BLOOD, BLOOD_D, BLOOD_DD, BLOOD_K = c("f0505a"), c("e02a3c"), c("b3162a"), c("7d0f1c"), c("4f0a12"), c("2a0509")
FLESH_HI, FLESH, FLESH_D = c("d49a86"), c("a35a5a"), c("6e3440")


def flash(size, length, width, layers, angles=None):
    """Конус вспышки вдоль угла; layers — [(доля длины, доля ширины, цвет)] от внешнего к сердцевине."""
    out = []
    for deg in angles if angles is not None else range(0, 360, 45):
        a = math.radians(deg)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        cx = cy = size / 2
        for fl, fw, col in layers:
            L, w = length * fl, width * fw
            tip = (cx + dx * L, cy + dy * L)
            s1 = (cx + px * w - dx * 1, cy + py * w - dy * 1)
            s2 = (cx - px * w - dx * 1, cy - py * w - dy * 1)
            spur1 = (cx + dx * L * 0.55 + px * w * 1.3, cy + dy * L * 0.55 + py * w * 1.3)
            spur2 = (cx + dx * L * 0.55 - px * w * 1.3, cy + dy * L * 0.55 - py * w * 1.3)
            dr.polygon([s1, spur1, tip, spur2, s2], fill=col)
        out.append(im)
    return out


def sheet(frames_by_row, w, h):
    rows, cols = len(frames_by_row), max(len(r) for r in frames_by_row)
    s = Image.new("RGBA", (cols * w, rows * h), (0, 0, 0, 0))
    for r, row in enumerate(frames_by_row):
        for i, im in enumerate(row):
            s.alpha_composite(im, (i * w, r * h))
    return s


def dither_drop(im, keep, seed):
    """Рассыпание без прозрачности: убираем пиксели по шахматке и случайно."""
    rnd = random.Random(seed)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3] and ((x + y) % 2 == 0 and rnd.random() > keep or rnd.random() > keep + 0.25):
                px[x, y] = (0, 0, 0, 0)
    return im


def steam_frames():
    out = []
    rnd = random.Random(5)
    blobs = [(rnd.uniform(-3, 3), rnd.uniform(-3, 3), rnd.uniform(0.6, 1.0)) for _ in range(5)]
    for f in range(6):
        im = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        r0 = 3 + f * 1.2
        for bx, by, s in blobs:
            r = r0 * s
            x, y = 10 + bx * (1 + f * 0.3), 11 + by * (1 + f * 0.3) - f * 0.8
            dr.ellipse([x - r, y - r, x + r, y + r], fill=GREY)
            dr.ellipse([x - r * 0.75 - 0.5, y - r * 0.75 - 0.8, x + r * 0.55, y + r * 0.45], fill=PALE)
            dr.ellipse([x - r * 0.45 - 0.8, y - r * 0.5 - 1.0, x + r * 0.05, y - r * 0.1], fill=WHITE)
        out.append(dither_drop(im, 1.0 - f * 0.17, f))
    return out


def smoke_frames():
    """Пороховой дым обреза (раунд 12): клуб темнее пара, расползается и рассыпается дизером, 24x24."""
    out = []
    rnd = random.Random(12)
    blobs = [(rnd.uniform(-4, 4), rnd.uniform(-3, 3), rnd.uniform(0.6, 1.0)) for _ in range(6)]
    for f in range(6):
        im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        r0 = 3 + f * 1.3
        for bx, by, s in blobs:
            r = r0 * s
            x, y = 12 + bx * (1 + f * 0.35), 13 + by * (1 + f * 0.3) - f * 0.6
            dr.ellipse([x - r, y - r, x + r, y + r], fill=SHADOW)
            dr.ellipse([x - r * 0.75 - 0.5, y - r * 0.75 - 0.8, x + r * 0.55, y + r * 0.45], fill=DARKG)
            dr.ellipse([x - r * 0.4 - 0.8, y - r * 0.45 - 1.0, x + r * 0.05, y - r * 0.1], fill=GREY)
        out.append(dither_drop(im, 1.0 - f * 0.16, 40 + f))
    return out


def shell_frames():
    out = []
    for k in range(8):
        a = math.radians(k * 45)
        im = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        dx, dy = math.cos(a), math.sin(a)
        c0 = (3.5 - dx * 2.0, 3.5 - dy * 2.0)
        c1 = (3.5 + dx * 1.2, 3.5 + dy * 1.2)
        c2 = (3.5 + dx * 2.4, 3.5 + dy * 2.4)
        dr.line([c0, c1], fill=BLOOD_D, width=2)
        dr.line([c0, c1], fill=BLOOD, width=1)
        dr.line([c1, c2], fill=LAMP_HI, width=2)
        out.append(im)
    return out


def blob(rnd, w, h, n, spread):
    """Случайные слитые круги в прямоугольнике w x h (экранные пиксели)."""
    return [(w / 2 + rnd.uniform(-spread, spread) * w / 2, h / 2 + rnd.uniform(-spread, spread) * h / 2,
             rnd.uniform(0.25, 0.45) * min(w, 2 * h) / 2) for _ in range(n)]


def splat(w, h, seed, fresh):
    """Пятно крови в экранных пикселях w x h (h = w/2 — круг на полу), 3 слоя, свежее с влажным бликом."""
    rnd = random.Random(seed)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    main = blob(rnd, w, h, 5, 0.35)
    drops = [(rnd.uniform(1, w - 2), rnd.uniform(1, h - 2), rnd.uniform(0.6, 1.4)) for _ in range(max(2, w // 6))]
    edge, body, inner, hi = (BLOOD_DD, BLOOD_D, BLOOD, WET) if fresh else (BLOOD_K, BLOOD_DD, BLOOD_D, None)
    for col, k in ((edge, 1.0), (body, 0.78), (inner, 0.45)):
        for x, y, r in main:
            dr.ellipse([x - r * k, y - r * k * 0.5, x + r * k, y + r * k * 0.5], fill=col)
    for x, y, r in drops:
        dr.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=edge)
    if hi:
        for x, y, r in main[:2]:
            dr.rectangle([x - r * 0.3, y - r * 0.15, x - r * 0.3 + 1, y - r * 0.15], fill=hi)
    # каждая строка экрана -> две строки текстуры (декаль на полу сжимается камерой вдвое)
    tex = Image.new("RGBA", (w, h * 2), (0, 0, 0, 0))
    for y in range(h):
        row = im.crop((0, y, w, y + 1))
        tex.paste(row, (0, 2 * y))
        tex.paste(row, (0, 2 * y + 1))
    return tex


M = 56


def floor_tex(im):
    """Каждая строка экрана -> две строки текстуры: плоский спрайт на полу сжимается камерой вдвое."""
    tex = Image.new("RGBA", (im.width, im.height * 2), (0, 0, 0, 0))
    for y in range(im.height):
        row = im.crop((0, y, im.width, y + 1))
        tex.paste(row, (0, 2 * y))
        tex.paste(row, (0, 2 * y + 1))
    return tex


def shock_frames(radius_m):
    """Кольцо пыли расширяется от центра и рассыпается дизером."""
    R = radius_m * M
    w, h = int(2 * R) + 8, int(R) + 8
    out = []
    for f, (k, keep) in enumerate(((0.3, 1.0), (0.55, 0.95), (0.78, 0.8), (0.92, 0.6), (1.0, 0.35))):
        rnd = random.Random(100 + f)
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        cx, cy = w / 2, h / 2
        rx, ry = R * k, R * k * 0.5
        band = max(5.0, R * 0.12)
        for col, b in ((SHADOW, band), (DARKG, band * 0.65), (GREY, band * 0.35)):
            dr.ellipse([cx - rx - b, cy - ry - b * 0.5, cx + rx + b, cy + ry + b * 0.5], fill=col)
        dr.ellipse([cx - rx + band, cy - ry + band * 0.5, cx + rx - band, cy + ry - band * 0.5], fill=(0, 0, 0, 0))
        for _ in range(int(R * 0.5)):                      # комья по кольцу
            a = rnd.uniform(0, 2 * math.pi)
            q = rnd.uniform(0.8, 1.05)
            x, y = cx + math.cos(a) * rx * q, cy + math.sin(a) * ry * q - rnd.uniform(0, 6)
            s = rnd.uniform(0.8, 2.2)
            dr.ellipse([x - s, y - s * 0.6, x + s, y + s * 0.6], fill=PALE if rnd.random() < 0.3 else DARKG)
        out.append(floor_tex(dither_drop(im, keep, 200 + f)))
    return out, w, h * 2


def blast_row(k):
    """Веер залпа по направлению k: 0 — на зрителя (s), шаг 45 градусов; глубина экрана вдвое меньше."""
    frames = []
    W, H, L = 520, 270, 4.5 * M
    a0 = math.radians(k * 45)
    for f, (reach, keep, cols) in enumerate(((0.55, 1.0, (BLOOD, LAMP_HI, WHITE)), (0.85, 0.9, (LAMP, LAMP_HI, PALE)),
                                             (1.0, 0.7, (SHADOW, DARKG, LAMP)), (1.0, 0.4, (SHADOW, SHADOW, DARKG)))):
        rnd = random.Random(300 + k * 10 + f)
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        cx, cy = W / 2, H / 2
        for col, fr, spread in ((cols[0], 1.0, 30), (cols[1], 0.75, 22), (cols[2], 0.45, 12)):
            pts = [(cx, cy)]
            for t in range(-6, 7):
                a = a0 + math.radians(spread * t / 6)
                r = L * reach * fr * rnd.uniform(0.9, 1.05)
                pts.append((cx + math.sin(a) * r, cy + math.cos(a) * r * 0.5))
            dr.polygon(pts, fill=col)
        frames.append(floor_tex(dither_drop(im, keep, 400 + k * 10 + f)))
    return frames


def crack(w, h, seed):
    """Трещины от центра: ломаные тёмного тона, с мелкими ответвлениями."""
    rnd = random.Random(seed)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    cx, cy = w / 2, h / 2
    for i in range(9):
        a = i * 2 * math.pi / 9 + rnd.uniform(-0.25, 0.25)
        x, y = cx, cy
        n = rnd.randint(4, 6)
        for j in range(n):
            a += rnd.uniform(-0.5, 0.5)
            st = w / 2 / n * rnd.uniform(0.7, 1.05)
            nx, ny = x + math.cos(a) * st, y + math.sin(a) * st * 0.5
            dr.line([(x, y), (nx, ny)], fill=c("0b0a10"), width=2 if j < 2 else 1)
            if rnd.random() < 0.35:
                b = a + rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.0)
                dr.line([(nx, ny), (nx + math.cos(b) * st * 0.5, ny + math.sin(b) * st * 0.25)], fill=c("15131d"), width=1)
            x, y = nx, ny
    return floor_tex(im)


def fire_row(k):
    """Огненный веер по направлению k, рассыпается дизером."""
    frames = []
    W, H, L = 640, 330, 5.5 * M
    a0 = math.radians(k * 45)
    for f, (reach, keep, cols) in enumerate(((0.5, 1.0, (BLOOD, LAMP_HI, WHITE)), (0.8, 0.95, (BLOOD, LAMP_HI, PALE)),
                                             (1.0, 0.75, (BLOOD_D, LAMP, LAMP_HI)), (1.0, 0.4, (BLOOD_DD, BLOOD_D, LAMP)))):
        rnd = random.Random(900 + k * 10 + f)
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        cx, cy = W / 2, H / 2
        for col, fr, spread in ((cols[0], 1.0, 40), (cols[1], 0.75, 30), (cols[2], 0.42, 16)):
            pts = [(cx, cy)]
            for t in range(-9, 10):
                a = a0 + math.radians(spread * t / 9)
                r = L * reach * fr * rnd.uniform(0.82, 1.05)
                pts.append((cx + math.sin(a) * r, cy + math.cos(a) * r * 0.5))
            dr.polygon(pts, fill=col)
        frames.append(floor_tex(dither_drop(im, keep, 950 + k * 10 + f)))
    return frames


def flame_frames():
    """Пламя охватывает всё тело: языки от стоп до головы, в палитре огня, без прозрачности. Низ спрайта у стоп."""
    out = []
    for f in range(6):
        rnd = random.Random(1200 + f)
        im = Image.new("RGBA", (48, 96), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        for col, wmul, hmul, count in ((BLOOD, 1.0, 1.0, 9), (LAMP, 0.7, 0.75, 7), (LAMP_HI, 0.42, 0.5, 5)):
            for _ in range(count):
                x = 24 + rnd.uniform(-14, 14) * wmul
                base = rnd.uniform(22, 94)
                hgt = rnd.uniform(10, 22) * hmul
                wd = rnd.uniform(2, 4.5) * (wmul * 0.5 + 0.5)
                dr.polygon([(x - wd, base), (x + wd, base), (x + rnd.uniform(-3, 3), base - hgt)], fill=col)
        out.append(dither_drop(im, 0.55, 1300 + f))   # редко: сквозь огонь виден подпалённый враг
    return out

def hook_frames():
    out = []
    for k in range(8):
        im = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        dr.arc([8, 8, 32, 32], -70, 130, fill=SHADOW, width=5)
        dr.arc([9, 9, 31, 31], -65, 125, fill=PALE, width=3)
        dr.arc([11, 11, 29, 29], -55, 115, fill=WHITE, width=1)
        out.append(im.rotate(-k * 45, resample=Image.NEAREST).resize((20, 20), Image.NEAREST))
    return out


def chunk_frames():
    rows = []
    for v in range(4):
        rnd = random.Random(40 + v)
        base = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
        dr = ImageDraw.Draw(base)
        pts = [(5 + math.cos(t) * rnd.uniform(2.0, 3.6), 5 + math.sin(t) * rnd.uniform(1.6, 3.0))
               for t in [i * 2 * math.pi / 7 for i in range(7)]]
        dr.polygon(pts, fill=BLOOD_D)
        dr.polygon([(x * 0.7 + 1.2, y * 0.7 + 1.0) for x, y in pts], fill=BLOOD if v % 2 else FLESH)
        dr.point([(4, 4)], fill=FLESH_HI if v % 2 == 0 else RED)
        if v == 3:
            dr.point([(5, 5), (6, 5)], fill=PALE)          # осколок кости
        row = []
        for k in range(8):
            r = base.rotate(-k * 45, resample=Image.NEAREST)
            px = r.load()
            out = r.copy()
            op = out.load()
            for y in range(10):                             # тёмный контур, как sel-out
                for x in range(10):
                    if px[x, y][3] == 0 and any(0 <= x + dx < 10 and 0 <= y + dy < 10 and px[x + dx, y + dy][3]
                                                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                        op[x, y] = BLOOD_K
            row.append(out)
        rows.append(row)
    return rows


def spark_frames(variant=0):
    """Короткий веер горячих металлических искр, 6 кадров 48x48; центр — точка удара."""
    rng = random.Random(180 + variant)
    jets = [(rng.uniform(0, math.tau), rng.uniform(14, 23), rng.uniform(0.7, 1.15)) for _ in range(11)]
    out = []
    for frame in range(6):
        im = Image.new("RGBA", (48, 48))
        dr = ImageDraw.Draw(im)
        if frame == 0:
            dr.line((20, 24, 28, 24), fill=LAMP_HI)
            dr.line((24, 21, 24, 27), fill=WHITE)
        for j, (a, speed, life) in enumerate(jets):
            t = (frame + 0.3) / 6
            if t > life or (frame >= 4 and j % 3 == 0):
                continue
            r = speed * t
            x, y = 24 + math.cos(a) * r, 24 + math.sin(a) * r + 5 * t * t
            tail = max(1, 4 - frame * 0.5)
            color = WHITE if frame == 0 else LAMP_HI if frame < 3 else LAMP
            dr.line((round(x - math.cos(a) * tail), round(y - math.sin(a) * tail), round(x), round(y)), fill=color)
        out.append(im)
    return out


def maxim_effects():
    """Направления мира проецируются с наклоном камеры 30°, без округления к 45° на экране."""
    angles = [math.degrees(math.atan2(0.5*math.cos(k*math.pi/4), math.sin(k*math.pi/4))) for k in range(8)]
    flashes = [flash(32, 13, 3.5, [(1, 1, LAMP), (0.8, 0.6, LAMP_HI), (0.45, 0.3, WHITE)], angles),
               flash(32, 8, 2, [(1, 1, LAMP_HI), (0.5, 0.4, WHITE)], angles)]
    tracers = []
    for a in angles:
        a = math.radians(a)
        dx, dy = math.cos(a), math.sin(a)
        im = Image.new("RGBA", (32, 32))
        dr = ImageDraw.Draw(im)
        dr.line((round(16-9*dx), round(16-9*dy), round(16+4*dx), round(16+4*dy)), fill=LAMP)
        dr.line((16, 16, round(16+4*dx), round(16+4*dy)), fill=LAMP_HI)
        dr.point((round(16+4*dx), round(16+4*dy)), fill=WHITE)
        tracers.append([im])
    base = Image.new("RGBA", (12, 12))
    dr = ImageDraw.Draw(base)
    dr.rectangle((3, 5, 9, 8), fill=LAMP_LO)
    dr.rectangle((3, 5, 8, 6), fill=LAMP)
    dr.line((3, 5, 8, 5), fill=LAMP_HI)
    dr.line((9, 5, 9, 8), fill=LAMP_HI)
    shells = [base.rotate(-k*45, resample=Image.NEAREST) for k in range(8)]
    dust = []
    for f in range(6):
        im = Image.new("RGBA", (64, 32))
        dr = ImageDraw.Draw(im)
        for j in range(7):
            a = j*math.tau/7
            x, y = 32+math.cos(a)*(5+f*3), 22+math.sin(a)*(2+f)-f*.8
            r = 2+f*.55
            dr.ellipse((round(x-r), round(y-r*.6), round(x+r), round(y+r*.6)), fill=SHADOW)
            if f < 4:
                dr.line((round(x-r*.5), round(y-r*.5), round(x+r*.4), round(y-r*.5)), fill=DARKG)
        dust.append(dither_drop(im, 1-f*.15, 1830+f))
    return {"flash_maxim": ([[flashes[f][d] for f in range(2)] for d in range(8)], (32, 32), [25, 35]),
            "tracer_maxim": (tracers, (32, 32), [80]), "shell_maxim": ([shells], (12, 12), [50]*8),
            "stomp_dust": ([dust], (64, 32), [40, 45, 50, 55, 60, 70])}


def mech_death_effects():
    """Дым котла, взрыв, пламя и кровь пилота; жёсткая альфа и палитра PZ-28."""
    smoke=[]
    for f in range(8):
        im=Image.new('RGBA',(64,96));dr=ImageDraw.Draw(im);u=f/7
        for j in range(3):
            x,y=32+math.sin(j*2+u*2)*6,82-u*42-j*(5+u*4)
            r=6+u*10-j*2
            dr.ellipse((round(x-r),round(y-r),round(x+r),round(y+r)),fill=SHADOW)
            dr.ellipse((round(x-r*.65),round(y-r*.75),round(x+r*.55),round(y+r*.25)),fill=DARKG)
        smoke.append(dither_drop(im,1-f*.1,1840+f))
    blast=[]
    for f in range(8):
        im=Image.new('RGBA',(128,128));dr=ImageDraw.Draw(im)
        r=[9,20,32,42,42,38,34,30][f]
        clouds=[]
        for j in range(9):
            a=j*math.tau/9
            x,y=64+math.cos(a)*r*.64,68+math.sin(a)*r*.5-f*1.5
            clouds.append((x,y,8+r*(.3+.05*math.sin(j*1.9))))
        clouds.append((64,68-f*1.5,8+r*.7))
        layers=[(1,SHADOW if f>=4 else LAMP_LO),(.78,DARKG if f>=5 else LAMP if f>=3 else LAMP_HI)]
        if f<3:layers.append((.43,WHITE))
        for scale,color in layers:
            for x,y,br in clouds:
                rr=br*scale
                dr.ellipse((round(x-rr),round(y-rr),round(x+rr),round(y+rr)),fill=color)
        blast.append(dither_drop(im,1 if f<4 else 1-(f-3)*.17,1860+f))
    flame=[]
    for f in range(8):
        im=Image.new('RGBA',(64,96));dr=ImageDraw.Draw(im)
        for scale,color in [(1,BLOOD_D),(.8,LAMP),(.45,LAMP_HI)]:
            for j in range(5):
                x=13+j*9;phase=f*math.tau/8+j*1.7
                h=([25,38,50,34,27][j]+10*math.sin(phase))*scale;w=(7+2*math.sin(phase+1))*scale
                bend=6*math.sin(phase+j)
                pts=[(x-w,85),(x-w*.8,85-h*.45),(x+bend-w*.35,85-h*.75),(x+bend*1.3,85-h),
                     (x+bend+w*.25,85-h*.65),(x+w*.8,85-h*.3),(x+w,85)]
                dr.polygon([(round(px),round(py)) for px,py in pts],fill=color)
        flame.append(dither_drop(im,.85,1880+f))
    blood=[]
    rng=random.Random(1890)
    drops=[(rng.uniform(-18,18),rng.uniform(-22,8),rng.uniform(1,2.3)) for _ in range(18)]
    for f in range(6):
        im=Image.new('RGBA',(64,64));dr=ImageDraw.Draw(im);t=(f+1)/6
        for j,(vx,vy,r) in enumerate(drops):
            x,y=32+vx*t,32+vy*t+10*t*t
            rr=max(1,r-f*.2)
            dr.ellipse((round(x-rr),round(y-rr),round(x+rr),round(y+rr)),fill=BLOOD_D if j%3==0 else BLOOD)
            if f<3:dr.point((round(x),round(y)),fill=WET)
        blood.append(dither_drop(im,1-f*.11,1898+f))
    return {'smoke_mech':([smoke],(64,96),[80]*8),
            'blast_mech':([blast],(128,128),[40,50,60,70,80,100,120,150]),
            'flame_mech':([flame],(64,96),[80]*8),
            'pilot_blood':([blood],(64,64),[45,50,55,60,70,80])}


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    big = [flash(32, 14, 5, [(1.0, 1.0, BLOOD), (0.85, 0.8, LAMP_HI), (0.5, 0.45, WHITE)]),
           flash(32, 10, 3.5, [(1.0, 1.0, LAMP), (0.75, 0.7, LAMP_HI), (0.35, 0.4, WHITE)]),
           flash(32, 6, 3, [(1.0, 1.0, SHADOW), (0.6, 0.6, DARKG)])]
    sheet([[big[f][k] for f in range(3)] for k in range(8)], 32, 32).save(os.path.join(outdir, "flash_shotgun.png"))
    small = [flash(16, 7, 2.2, [(1.0, 1.0, LAMP_HI), (0.5, 0.5, WHITE)]),
             flash(16, 4, 1.6, [(1.0, 1.0, LAMP), (0.5, 0.5, LAMP_HI)])]
    sheet([[small[f][k] for f in range(2)] for k in range(8)], 16, 16).save(os.path.join(outdir, "flash_pistol.png"))
    sheet([shell_frames()], 8, 8).save(os.path.join(outdir, "shell.png"))
    sheet([steam_frames()], 20, 20).save(os.path.join(outdir, "steam.png"))
    sheet([spark_frames(v) for v in range(3)], 48, 48).save(os.path.join(outdir, "sparks_metal.png"))
    for name, (rows, size, _) in maxim_effects().items():
        sheet(rows, *size).save(os.path.join(outdir, name+".png"))
    for name, (rows, size, _) in mech_death_effects().items():
        sheet(rows, *size).save(os.path.join(outdir, name+".png"))
    sheet([smoke_frames()], 24, 24).save(os.path.join(outdir, "smoke.png"))
    sheet(chunk_frames(), 10, 10).save(os.path.join(outdir, "chunks.png"))
    sizes = {"s": (8, 4), "m": (20, 10), "l": (36, 18), "pool1": (24, 12), "pool2": (40, 20), "pool3": (58, 29)}
    n = 0
    for name, (w, h) in sizes.items():
        for v in range(3):
            for fresh in (True, False):
                splat(w, h, sum(map(ord, name)) * 31 + v, fresh).save(
                    os.path.join(outdir, f"splat_{name}_{'fresh' if fresh else 'dried'}_{v}.png"))
                n += 1
    for name, r in (("blade", 3.0), ("sickle", 2.3)):
        fr, w, h = shock_frames(r)
        sheet([fr], w, h).save(os.path.join(outdir, f"shock_{name}.png"))
    sheet([blast_row(k) for k in range(8)], 520, 540).save(os.path.join(outdir, "blast_gun.png"))
    for name, (w, h) in {"l": (150, 75), "m": (110, 55)}.items():
        for v in range(3):
            crack(w, h, 700 + v * 7 + w).save(os.path.join(outdir, f"crack_{name}_{v}.png"))
    sheet([fire_row(k) for k in range(8)], 640, 660).save(os.path.join(outdir, "fire_gun.png"))
    sheet([flame_frames()], 48, 96).save(os.path.join(outdir, "flame.png"))
    sheet([[f] for f in hook_frames()], 20, 20).save(os.path.join(outdir, "hook_tip.png"))
    print("эффекты готовы, пятен:", n)


if __name__ == "__main__":
    main(sys.argv[1])
