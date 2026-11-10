"""Собрать этап 2: PNG/.aseprite, контракт метаданных, контрольный лист и GIF.

python tools/mech_damage_sheets.py [папка-вывода]
Исходные кадры: PZ_MECH_RENDER_DIR или art/mech/render. Godot не изменяется.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(os.environ.get("PZ_MATERIALS_ROOT", Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import fx_gen

RD = Path(os.environ.get("PZ_MECH_RENDER_DIR", ROOT / "art/mech/render"))
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "art/mech"
ASE = Path("D:/Aseprite/Aseprite/Aseprite.exe")
DIRS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
PALETTE = {tuple(bytes.fromhex(h)) for h in (ROOT / "art/palette/pz-28.hex").read_text().split()}


def checked(path, size):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    assert im.size == size, (path, im.size, size)
    assert set(np.unique(a[..., 3])) <= {0, 255}, (path, "alpha")
    assert {tuple(c[:3]) for c in a.reshape(-1, 4) if c[3]} <= PALETTE, (path, "palette")
    assert im.getbbox() is not None, (path, "empty")
    assert not np.any(a[[0, -1], :, 3]) and not np.any(a[:, [0, -1], 3]), (path, "clipping")
    return im


def build(name, rows, durs, size, folder=None):
    """Те же исходники идут в Aseprite и PNG: прозрачные пустые края сохраняются."""
    w, h = size
    folder = folder or OUT
    folder.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (w * len(durs), h * len(rows)))
    for y, row in enumerate(rows):
        assert len(row["files"]) == len(durs)
        for x, path in enumerate(row["files"]):
            sheet.paste(checked(path, size), (x * w, y * h))
    sheet.save(folder / (name + ".png"))
    job = {"width": w, "height": h, "palette": str(ROOT / "art/palette/pz-28.gpl"),
           "layer": name, "rows": rows, "durations_ms": durs, "output": str(folder / (name + ".aseprite"))}
    jobpath = folder / (name + ".job.json")
    jobpath.write_text(json.dumps(job), encoding="utf-8")
    subprocess.run([str(ASE), "-b", "--script-param", "job=" + str(jobpath), "--script",
                    str(Path(__file__).with_name("aseprite_build_mech.lua"))], check=True)
    jobpath.unlink()
    export, data = folder / (name + ".check.png"), folder / (name + ".check.json")
    subprocess.run([str(ASE), "-b", "--list-tags", str(folder / (name + ".aseprite")), "--sheet", str(export),
                    "--sheet-type", "rows", "--sheet-columns", str(len(durs)),
                    "--data", str(data), "--format", "json-array"], check=True)
    assert np.array_equal(np.array(sheet), np.array(Image.open(export).convert("RGBA"))), (name, "Aseprite roundtrip")
    info = json.loads(data.read_text())
    assert [f["duration"] for f in info["frames"]] == durs * len(rows), (name, "frame timing")
    assert [(t["name"], t["from"], t["to"]) for t in info["meta"]["frameTags"]] == [
        (r["tag"], i*len(durs), (i+1)*len(durs)-1) for i, r in enumerate(rows)], (name, "tags")
    export.unlink()
    data.unlink()
    return sheet


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = json.loads((RD / "mech_hit.json").read_text(encoding="utf-8"))
    rows = [{"tag": "hit_" + d, "files": [str(RD / f"mech_scout_hit_{d}_{i}.png") for i in range(3)]} for d in DIRS]
    hit = build("mech_scout_hit", rows, meta["durations_ms"], (256, 256))
    for d in DIRS:
        idle = np.array(Image.open(ROOT / f"art/mech/render/mech_scout_idle_{d}_0.png"))
        rest = np.array(Image.open(RD / f"mech_scout_hit_{d}_2.png"))
        assert np.array_equal(idle, rest), (d, "return to idle")
        assert not np.array_equal(idle, np.array(Image.open(RD / f"mech_scout_hit_{d}_0.png"))), (d, "no recoil")
    (OUT / "mech_hit.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    pieces = {}
    for name in ["cover", "shield", "cap"]:
        m = json.loads((RD / f"mech_piece_{name}.json").read_text(encoding="utf-8"))
        assert m["pilot"] is False
        build("mech_piece_" + name, [{"tag": "tumble", "files": [str(RD / f"mech_scout_piece_{name}_s_{i}.png") for i in range(8)]}], m["durations_ms"], (64, 64))
        pieces[name] = {k: m[k] for k in ["frames", "durations_ms", "canvas", "pivot", "source_objects", "source_ids", "source_center_px"]}
    spark_rows = []
    for v in range(3):
        paths = []
        for i, im in enumerate(fx_gen.spark_frames(v)):
            path = RD / f"sparks_metal_{v}_{i}.png"
            im.save(path)
            paths.append(str(path))
        spark_rows.append({"tag": f"impact_{v}", "files": paths})
    build("sparks_metal", spark_rows, [35, 40, 45, 50, 55, 60], (48, 48), OUT.parent / "fx")
    contract = {"schema_version": 1, "directions": DIRS, "hit": {"sheet": "mech_scout_hit.png", "metadata": "mech_hit.json", "frames": 3,
                "durations_ms": meta["durations_ms"], "canvas": [256, 256], "pivot": [128, 218], "root_motion": False},
                "pieces": pieces, "sparks": {"sheet": "../fx/sparks_metal.png", "frames": 6, "variants": 3, "canvas": [48, 48], "pivot": [24, 24],
                "durations_ms": [35, 40, 45, 50, 55, 60]},
                "integration": "Asset stage only. Godot integration, collision-triggered emission and permanent damage states are stage 5."}
    (OUT / "mech_damage.json").write_text(json.dumps(contract, ensure_ascii=False, indent=2), encoding="utf-8")
    # Все направления и кадры на одном листе, в родном масштабе.
    contact = Image.new("RGB", (256 * 4, 280 * 8), "#211e2c")
    draw = ImageDraw.Draw(contact)
    for y, d in enumerate(DIRS):
        for x in range(4):
            im = Image.open(ROOT / f"art/mech/render/mech_scout_idle_{d}_0.png") if x == 0 else hit.crop(((x-1)*256, y*256, x*256, (y+1)*256))
            contact.paste(im, (x*256, y*280+24), im)
            draw.text((x*256+8, y*280+6), d + " / " + ["idle", "impact", "rebound", "rest"][x], fill="white")
    contact.save(OUT / "mech_damage_contact.png")
    preview_frames = []
    for f in range(24):
        preview = Image.new("RGB", (256*4, 280), "#211e2c")
        draw = ImageDraw.Draw(preview)
        for col, d in enumerate(["se", "s", "e", "nw"]):
            ms = (f * 50) % 1200
            idx = 0 if ms < 70 else 1 if ms < 170 else 2
            im = Image.open(RD / f"mech_scout_hit_{d}_{idx}.png")
            preview.paste(im, (col*256, 24), im)
            if ms < 285:
                sf = next(i for i, end in enumerate([35, 75, 120, 170, 225, 285]) if ms < end)
                spark = Image.open(RD / f"sparks_metal_{col%3}_{sf}.png")
                ax, ay = meta["anchors"]["body"][d][idx]
                preview.paste(spark, (round(col*256+ax-24), round(24+ay-24)), spark)
            draw.text((col*256+8, 5), d + " / HIT", fill="white")
        preview_frames.append(preview)
    preview_frames[0].save(OUT / "mech_hit_preview.gif", save_all=True, append_images=preview_frames[1:], duration=50, loop=0, optimize=False)
    # Отдельный контактный лист и кувырок обломков.
    contact = Image.new("RGB", (64*8, 90*3), "#211e2c")
    draw = ImageDraw.Draw(contact)
    for row, name in enumerate(pieces):
        for i in range(8):
            im = Image.open(RD / f"mech_scout_piece_{name}_s_{i}.png")
            contact.paste(im, (i*64, row*90+22), im)
        draw.text((5, row*90+5), name, fill="white")
    contact.save(OUT / "mech_pieces_contact.png")
    flight_frames = []
    for f in range(24):
        flight = Image.new("RGB", (256*3, 256), "#211e2c")
        draw = ImageDraw.Draw(flight)
        for col, name in enumerate(pieces):
            t = min(f * 0.05, 0.92)
            px, py = round(95 + 55*t), min(196, round(100 - 80*t + 200*t*t))
            k = (f // 2) % 8 if f*0.05 < 0.92 else 0
            draw.line((col*256, 228, (col+1)*256-1, 228), fill="#322e40")
            im = Image.open(RD / f"mech_scout_piece_{name}_s_{k}.png")
            flight.paste(im, (col*256+px-32, py), im)
            draw.text((col*256+8, 8), name + " / flight preview", fill="white")
        flight_frames.append(flight)
    flight_frames[0].save(OUT / "mech_pieces_preview.gif", save_all=True, append_images=flight_frames[1:], duration=50, loop=0, optimize=False)
    report = {"result": "PASS", "hit_frames": 24, "piece_frames": 24, "spark_frames": 18,
              "checks": ["palette", "binary alpha", "nonempty", "no canvas clipping", "8 exact returns to idle", "8 visible recoils", "piece metadata", "Aseprite pixels, timing and tags"],
              "not_tested": ["Godot integration", "gameplay", "audio"]}
    (OUT / "mech_damage_qa.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
