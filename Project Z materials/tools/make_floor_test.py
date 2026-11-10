"""Тестовая текстура пола: каменные плиты 2x2 м, 56 px/м -> 112x112, только PZ-28.

python tools/make_floor_test.py "C:/project Z/z/assets/env/floor_test.png"
"""
import random
import sys

from PIL import Image

S = 112
BASE = ["211e2c", "322e40"]       # тела плит
GAP = "15131d"                    # шов
CHIP = "4a4558"                   # светлые сколы


def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def main(path):
    rnd = random.Random(7)
    im = Image.new("RGBA", (S, S), c(BASE[0]))
    px = im.load()
    # 4 плиты 1x1 м (56 px), каждая своего тона
    for ty in range(2):
        for tx in range(2):
            col = c(BASE[(tx + ty) % 2])
            for y in range(56):
                for x in range(56):
                    px[tx * 56 + x, ty * 56 + y] = col
    # швы
    for i in range(S):
        for k in (0, 56):
            px[i, k] = c(GAP)
            px[k, i] = c(GAP)
    # редкие кластеры сколов и трещины (кластеры 2-3 px, без одиночного шума)
    for _ in range(14):
        x, y = rnd.randrange(3, S - 4), rnd.randrange(3, S - 4)
        if x % 56 < 3 or y % 56 < 3:
            continue
        for dx, dy in ((0, 0), (1, 0), (0, 1))[: rnd.choice((2, 3))]:
            px[x + dx, y + dy] = c(CHIP)
    for _ in range(4):
        x, y = rnd.randrange(6, S - 12), rnd.randrange(6, S - 12)
        for k in range(rnd.randrange(5, 10)):
            px[x + k, y + (k // 3)] = c(GAP)
    im.save(path)


if __name__ == "__main__":
    main(sys.argv[1])
