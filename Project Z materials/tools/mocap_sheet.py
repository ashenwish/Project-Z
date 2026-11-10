"""Раскадровка записи на герое: каждый k-й кадр в одном ракурсе, с номером кадра и скоростью кистей.
Нужна, чтобы выбрать ключевые кадры (замах, удар, возврат) для спрайтовой анимации.

python tools/mocap_sheet.py refs/mixamo/club_combo.dae out.png [step] [dir] [mirror]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_render as hr  # noqa: E402
import mocap  # noqa: E402


def main(path, out, step=3, d="se", mirror=False):
    b = mocap.load(path, mirror=mirror)
    rt = mocap.Retarget(b, 0, b.n - 1, yaw=0.0 if path.lower().endswith(".dae") else None)
    frames = list(range(0, b.n, step))
    hand = lambda f, s: mocap.to_hero(b.pose(f)[s + "Hand"])
    cols = 10
    rows = (len(frames) + cols - 1) // cols
    cw, ch = 64 * 2, 96 * 2 + 24
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (21, 19, 29, 255))
    dr = ImageDraw.Draw(sheet)
    for i, f in enumerate(frames):
        im = hr.compose(*hr.render(hr.DIRS[d], rt.pose(f))).resize((128, 192), Image.NEAREST)
        x, y = (i % cols) * cw, (i // cols) * ch
        sheet.alpha_composite(im, (x, y))
        vr = np.linalg.norm(hand(min(f + 1, b.n - 1), "Right") - hand(f, "Right")) / b.frame_time
        vl = np.linalg.norm(hand(min(f + 1, b.n - 1), "Left") - hand(f, "Left")) / b.frame_time
        rm = rt.root_motion(f)
        dr.text((x + 3, y + 193), f"#{f} R{vr:.0f} L{vl:.0f} y{rm[1]:+.2f}", fill=(200, 190, 210, 255))
    sheet.save(out)
    print(f"{os.path.basename(path)}: {b.n} кадров, {b.n * b.frame_time:.2f} с, лист {sheet.size}")


if __name__ == "__main__":
    a = sys.argv
    main(a[1], a[2], int(a[3]) if len(a) > 3 else 3, a[4] if len(a) > 4 else "se",
         len(a) > 5 and a[5] == "mirror")
