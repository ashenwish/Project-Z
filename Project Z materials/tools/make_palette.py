"""Собирает палитру Project Z (PZ-28; с 2026-11-10 в ней 30 цветов, имя файлов прежнее): .gpl для Aseprite/GIMP, .hex, превью .png.

Запуск: python tools/make_palette.py  (из C:\\Project Z materials)
Единственный источник правды по цветам — список PALETTE ниже.
"""
from pathlib import Path
from PIL import Image, ImageDraw

# (группа, имя, hex). Порядок внутри группы: от тёмного к светлому.
PALETTE = [
    ("shadow", "void",        "#0b0a10"),
    ("shadow", "night",       "#15131d"),
    ("shadow", "dusk",        "#211e2c"),
    ("shadow", "slate-dark",  "#322e40"),
    ("shadow", "slate",       "#4a4558"),
    ("shadow", "slate-mid",   "#6b6578"),
    ("shadow", "ash",         "#948ea0"),
    ("shadow", "fog",         "#c4bfcc"),
    ("shadow", "bone",        "#ece8ee"),

    ("blood", "blood-1",      "#2a0509"),
    ("blood", "blood-2",      "#4f0a12"),
    ("blood", "blood-3",      "#7d0f1c"),
    ("blood", "blood-4",      "#b3162a"),
    ("blood", "blood-5",      "#e02a3c"),
    ("blood", "blood-wet",    "#f0505a"),

    ("flesh", "flesh-1",      "#3b1f28"),
    ("flesh", "flesh-2",      "#6e3440"),
    ("flesh", "flesh-3",      "#a35a5a"),
    ("flesh", "flesh-4",      "#d49a86"),
    ("flesh", "flesh-5",      "#f0cdb4"),

    ("steel", "steel-1",      "#1d2a33"),
    ("steel", "steel-2",      "#34505c"),
    ("steel", "steel-3",      "#5d8591"),
    ("steel", "steel-4",      "#9fc5c9"),

    ("lamp", "lamp-1",        "#4a3a1c"),
    ("lamp", "lamp-2",        "#9a7a2e"),
    ("lamp", "lamp-3",        "#e0b84a"),

    ("sick", "sick-green",    "#7fa05a"),

    # 2026-11-10, мех-разведчик: у латуни был провал между lamp-1 и lamp-2. В конце списка, чтобы не сдвигать индексы
    ("lamp", "brass-dark",    "#3e2c1c"),
    ("lamp", "brass-mid",     "#74582a"),
]


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def main():
    root = Path(__file__).resolve().parent.parent
    out = root / "art" / "palette"
    out.mkdir(parents=True, exist_ok=True)

    with open(out / "pz-28.gpl", "w", encoding="utf-8", newline="\n") as f:
        f.write("GIMP Palette\nName: PZ-28\nColumns: 7\n#\n")
        for group, name, h in PALETTE:
            r, g, b = rgb(h)
            f.write(f"{r:3d} {g:3d} {b:3d}\t{group}/{name} {h}\n")

    with open(out / "pz-28.hex", "w", encoding="utf-8", newline="\n") as f:
        for _, _, h in PALETTE:
            f.write(h[1:] + "\n")

    cell, cols = 24, 7
    rows = -(-len(PALETTE) // cols)
    img = Image.new("RGB", (cols * cell, rows * cell), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, (_, _, h) in enumerate(PALETTE):
        x, y = (i % cols) * cell, (i // cols) * cell
        d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=rgb(h))
    img.save(out / "pz-28-preview.png")

    # 1xN полоса для Aseprite (Palette -> Load Palette принимает и png)
    strip = Image.new("RGB", (len(PALETTE), 1))
    strip.putdata([rgb(h) for _, _, h in PALETTE])
    strip.save(out / "pz-28.png")
    print(len(PALETTE), "colors ->", out)


if __name__ == "__main__":
    main()
