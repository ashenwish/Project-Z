"""Сборка листов героя из кадров hero_layers.py в Aseprite и копирование в проект Godot.

Для каждого листа: .aseprite (палитра, кадры, теги, длительности) -> PNG -> assets/hero/layers.
Заодно проверяет палитру, прозрачность и то, не обрезан ли спрайт краем холста.

python tools/hero_sheets.py                 # все листы из layers.json
python tools/hero_sheets.py U_dash_blade R_run ...
"""
import json
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ASE = r"C:\Aseprite\Aseprite\Aseprite.exe"
SRC = os.path.join(ROOT, "art", "hero", "layers")
GAME = r"C:\project Z\z\assets\hero\layers"
PAL = {tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in open(os.path.join(ROOT, "art", "palette", "pz-28.hex")).read().split()}


def sheets(meta):
    """-> {имя листа: (приставка, анимация, кадров, длительности, w, h)}."""
    out = {}
    W, H = meta["canvas"]
    for n, d in meta["legs"].items():
        out["L_" + n] = ("L_", n, d["frames"], d["durations_ms"], W, H)
    for n, d in meta["upper"].items():
        out["U_" + n] = ("U_", n, d["frames"], d["durations_ms"], W, H)
        if d.get("trail"):
            out["X_" + n] = ("X_", n, d["frames"], d["durations_ms"], W, H)
    for n, d in meta["arm"].items():
        out["A_" + n] = ("A_", n, d["frames"] * d["states"], [], W, H)
    r = meta["pistol_reload"]
    for n in r["src"]:
        out["R_" + n] = ("R_", n, meta["arm"][n]["frames"] * r["states"], [], W, H)
    aim = meta.get("aim_arm")
    if aim:                                   # раунд 11: наведённые руки, направления x состояния
        n_off = len(aim["offsets"])
        out["A_aim"] = ("A_", "aim", n_off * aim["pistol"]["states"], [], W, H)
        out["S_aim"] = ("S_", "aim", n_off * aim["shotgun"]["states"], [], W, H)
    return out


def ase(args):
    subprocess.run([ASE, "-b"] + args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)


def build(name, s):
    pre, anim, frames, durs, w, h = s
    a = ["--script-param", f"root={ROOT.replace(os.sep, '/')}", "--script-param", f"anim={anim}",
         "--script-param", f"frames={frames}", "--script-param", "src=art/hero/layers/render",
         "--script-param", f"prefix={pre}", "--script-param", "out=art/hero/layers",
         "--script-param", f"w={w}", "--script-param", f"h={h}"]
    if durs:
        a += ["--script-param", "durations=" + ",".join(str(d) for d in durs)]
    ase(a + ["--script", "tools/aseprite_build_hero.lua"])
    png = os.path.join(SRC, name + ".png")
    ase([os.path.join(SRC, name + ".aseprite"), "--sheet", png, "--sheet-type", "rows", "--sheet-columns", str(frames)])
    return png


def check(png, s):
    """-> список замечаний: цвета вне палитры, полупрозрачность, обрез краем холста (кроме пола)."""
    pre, _, frames, _, w, h = s
    im = Image.open(png).convert("RGBA")
    notes = []
    if im.size != (w * frames, h * 8):
        notes.append(f"размер {im.size}")
    cols = {c for _, c in im.getcolors(1 << 24)}
    if {c[:3] for c in cols if c[3]} - PAL:
        notes.append("цвета вне палитры")
    if {c[3] for c in cols} - {0, 255}:
        notes.append("полупрозрачность")
    a = im.getchannel("A").load()
    cut = 0
    for fy in range(8):
        for fx in range(frames):
            x0, y0 = fx * w, fy * h
            # контур (sel-out) занимает 1 px: заполненный край холста значит, что спрайт обрезан
            edge = any(a[x0, y0 + y] for y in range(h)) or any(a[x0 + w - 1, y0 + y] for y in range(h)) \
                or any(a[x0 + x, y0] for x in range(w))
            cut += edge
    if cut:
        notes.append(f"касается края холста: {cut} кадр(ов) из {frames * 8}")
    return notes


def main(which):
    meta = json.load(open(os.path.join(SRC, "layers.json"), encoding="utf-8"))
    all_sheets = sheets(meta)
    names = which or list(all_sheets)
    for i, name in enumerate(names):
        png = build(name, all_sheets[name])
        for n in check(png, all_sheets[name]):
            print(f"{name}: {n}")
        shutil.copy2(png, os.path.join(GAME, name + ".png"))
    shutil.copy2(os.path.join(SRC, "layers.json"), os.path.join(GAME, "layers.json"))
    print("листов собрано:", len(names))


if __name__ == "__main__":
    main(sys.argv[1:])
