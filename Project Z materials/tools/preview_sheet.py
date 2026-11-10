"""Превью анимации: строки — направления, столбцы — кадры (xN), справа кадры x1.

python tools/preview_sheet.py art/hero/render walk out.png [scale]
"""
import glob
import os
import sys

from PIL import Image

ORDER = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]


def main(src, anim, out, scale=3, dirs=ORDER):
    frames = len(glob.glob(os.path.join(src, f"hero_{anim}_s_*.png")))
    ims = [[Image.open(os.path.join(src, f"hero_{anim}_{d}_{i}.png")) for i in range(frames)] for d in dirs]
    w, h = ims[0][0].size
    pad = 6
    big_w = frames * (w * scale + pad)
    sheet = Image.new("RGBA", (pad + big_w + frames * (w + 2) + pad, pad + len(dirs) * (h * scale + pad)),
                      (21, 19, 29, 255))
    for r, row in enumerate(ims):
        y = pad + r * (h * scale + pad)
        for i, im in enumerate(row):
            sheet.alpha_composite(im.resize((w * scale, h * scale), Image.NEAREST), (pad + i * (w * scale + pad), y))
            sheet.alpha_composite(im, (pad + big_w + i * (w + 2), y))
    sheet.save(out)


if __name__ == "__main__":
    a = sys.argv
    main(a[1], a[2], a[3], int(a[4]) if len(a) > 4 else 3, a[5].split(",") if len(a) > 5 else ORDER)
