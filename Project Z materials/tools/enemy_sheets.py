"""Сборка листов противника в Aseprite и копирование в проект Godot.

python tools/enemy_sheets.py          # всё
python tools/enemy_sheets.py corpse   # только трупы
python tools/enemy_sheets.py hooked   # только враг на цепи
"""
import json
import os
import shutil
import sys

from PIL import Image

from hero_sheets import ROOT, check, ase

SRC = os.path.join(ROOT, "art", "enemy")
GAME = r"C:\project Z\z\assets\enemy"


def build(pre, anim, frames, durs, w, h):
    a = ["--script-param", f"root={ROOT.replace(os.sep, '/')}", "--script-param", f"anim={anim}",
         "--script-param", f"frames={frames}", "--script-param", "src=art/enemy/render",
         "--script-param", f"prefix={pre}", "--script-param", "out=art/enemy",
         "--script-param", f"w={w}", "--script-param", f"h={h}"]
    if durs:
        a += ["--script-param", "durations=" + ",".join(str(d) for d in durs)]
    ase(a + ["--script", "tools/aseprite_build_hero.lua"])
    png = os.path.join(SRC, f"{pre}{anim}.png")
    ase([os.path.join(SRC, f"{pre}{anim}.aseprite"), "--sheet", png, "--sheet-type", "rows", "--sheet-columns", str(frames)])
    return png


def main(only_corpse=False, only_hooked=False):
    meta = json.load(open(os.path.join(SRC, "enemy.json"), encoding="utf-8"))
    sheets = [("E_", n, d["frames"], d["durations_ms"], 128, 128) for n, d in meta["air"].items()]
    sheets += [("T_", n, d["frames"], [], 128, 128) for n, d in meta["tumble"].items()]
    if only_corpse:
        sheets = []
    if only_hooked:
        h = meta["live"]["hooked"]
        png = build("E_", "hooked", h["frames"], h["durations_ms"], 64, 96)
        shutil.copy2(png, os.path.join(GAME, "E_hooked.png"))
        shutil.copy2(os.path.join(SRC, "enemy.json"), os.path.join(GAME, "enemy.json"))
        print("E_hooked собран")
        return
    for o, d in meta["corpse"].items():
        for fall in d["falls"]:
            sheets.append(("C_", f"{o}_{fall}", d["frames"], d["durations_ms"], *d["canvas"]))
    for pre, n, fr, durs, w, h in sheets:
        png = build(pre, n, fr, durs, w, h)
        for note in check(png, (pre, n, fr, durs, w, h)):
            print(f"{pre}{n}: {note}")
        shutil.copy2(png, os.path.join(GAME, f"{pre}{n}.png"))
    for n in meta["pieces"]:                 # куски: одна строка, без Aseprite, как раньше
        s = Image.new("RGBA", (48 * 8, 48), (0, 0, 0, 0))
        for k in range(8):
            s.alpha_composite(Image.open(os.path.join(SRC, "render", f"P_{n}_s_{k}.png")), (48 * k, 0))
        p = os.path.join(SRC, f"P_{n}.png")
        s.save(p)
        shutil.copy2(p, os.path.join(GAME, f"P_{n}.png"))
    shutil.copy2(os.path.join(SRC, "enemy.json"), os.path.join(GAME, "enemy.json"))
    print("листов собрано:", len(sheets))


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    main(arg == "corpse", arg == "hooked")
