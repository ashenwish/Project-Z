"""Звуки Project Z (раунд 13): поиск на Freesound (только CC0), скачивание оригиналов, обработка в OGG.

Стиль: стилизованный паровой — удары и выстрелы с паровой подложкой (шипение, клапаны, лязг).
Музыку и голос героя не ищем.

  python tools/sfx_fetch.py search            # refs/sfx/candidates.json (публичный поиск, без входа)
  python tools/sfx_fetch.py download STATE    # оригиналы в refs/sfx/raw по cookies сессии Edge (state-save)
  python tools/sfx_fetch.py process           # assets/audio/*.ogg + CREDITS.md + sfx.json

Сессию сохраняет playwright-cli -s=freesound state-save <файл>; cookies не выводятся и файл удаляется после загрузки.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
REFS = os.path.join(ROOT, "refs", "sfx")
RAW = os.path.join(REFS, "raw")
GAME = r"C:\project Z\z\assets\audio"
UA = {"User-Agent": "Mozilla/5.0 (ProjectZ sfx fetch)"}

# имя: (запросы, сколько вариантов, длительность мин..макс с)
WANT = {
    # движение
    # раунд 15: шаги героя — сапоги по камню, чётко (земля звучала как песок)
    "step": (["footsteps stone", "boots stone floor", "footsteps cobblestone", "footsteps stone steps"], 4, 2.0, 60.0, "slice"),
    # раунд 15: шаги NPC — другая обувь и покрытие, глуше героя
    "npc_step": (["footsteps leather shoes", "footsteps walking shoes", "footsteps wooden floor walking", "footsteps hallway"], 4, 2.0, 60.0, "slice"),
    "land": (["jump landing", "landing on ground thud", "body land thud"], 2, 0.1, 20.0, "slice"),
    # раунд 15: рывок — низкий глухой свист, без пара
    "whoosh": (["low whoosh", "deep whoosh", "heavy whoosh", "body movement whoosh"], 4, 0.15, 1.0),
    # пар и протез
    # раунд 15: пар мягче — новые записи тихого шипения, верх срезан (FILTER)
    "steam_short": (["soft steam hiss", "gentle air release", "air hiss short", "soft hiss"], 3, 0.15, 30.0, "slice"),
    "steam_long": (["soft hiss", "gentle steam", "air leak hiss", "steam hiss soft"], 3, 0.8, 8.0),
    # раунд 14: готовность ульты — мягкий звон вместо гудка
    "gears": (["mechanical gear click", "ratchet mechanism", "metal mechanism clank"], 4, 0.1, 1.5),
    "chime": (["small bell ding", "soft metal ding", "brass bell tap"], 2, 0.2, 3.0),
    # клинок и серп
    "swing_light": (["sword swing whoosh", "blade swish"], 5, 0.1, 0.8),
    "swing_heavy": (["heavy weapon swing", "big sword swing whoosh", "axe swing"], 4, 0.15, 1.3),
    "swing_heavy_sickle": (["scythe swing", "long whoosh", "whip swish"], 4, 0.2, 1.5),
    "jump_push": (["jump stone", "human jumping", "jump foley"], 3, 0.08, 1.0),
    "cloth": (["cloth rustle"], 1, 0.1, 1.0),
    # раунд 15: второй лёгкий удар — резкий короткий взмах (пик в начале, без «всасывания»)
    "swing_snap": (["sword swish", "blade swish", "knife swish", "katana swing"], 8, 0.08, 0.6),
    "slash_flesh": (["flesh slash", "sword stab flesh", "knife stab"], 5, 0.08, 1.2),
    "gore": (["gore squish", "flesh splatter wet", "gore splat"], 5, 0.1, 1.8),
    "bone": (["bone break crack", "bone crunch"], 3, 0.08, 1.2),
    "clang": (["sword clang metal", "metal hit clang"], 3, 0.1, 1.5),
    "chain": (["chain rattle", "metal chain shake"], 3, 0.2, 2.0),
    # раунд 15: ульта серпа насыщеннее — бросок с наложенным низким свистом и звон цепи на всё время ульты
    "chain_throw": (["heavy chain swing", "chain whoosh", "chain throw", "chain rattle swing"], 3, 0.3, 2.5),
    "chain_loop": (["chain rattle", "chains rattling", "chain shaking metal", "chain dragging"], 3, 1.0, 15.0),
    # обрез
    "shotgun": (["shotgun shot", "shotgun blast"], 4, 0.25, 3.0),
    "shotgun_double": (["double barrel shotgun", "shotgun double shot"], 2, 0.3, 3.5),
    "shotgun_open": (["break action shotgun open", "shotgun reload", "shotgun shell load"], 4, 0.1, 2.5),
    "shell": (["shell casing drop", "shotgun shell drop", "brass casing drop", "bullet casings falling"], 2, 0.05, 20.0, "slice"),
    "fire_burst": (["fire whoosh", "flame burst ignite"], 2, 0.3, 3.0),
    "fire_loop": (["fire burning crackle", "fire crackling loop"], 1, 2.0, 12.0),
    # револьвер
    "revolver": (["revolver gunshot", "pistol gunshot"], 1, 0.2, 2.5),     # раунд 14: один звук выстрела
    "revolver_cock": (["revolver hammer cock", "gun cock"], 2, 0.05, 1.0),
    "revolver_reload": (["revolver reload cylinder", "revolver cylinder spin"], 2, 0.3, 3.5),
    "dry_fire": (["gun dry fire click", "empty gun click"], 1, 0.03, 0.8),
    # враги
    "hit": (["punch flesh impact", "body hit impact"], 4, 0.05, 0.8),
    "body_fall": (["body fall thud", "body drop floor"], 3, 0.2, 1.8),
    "splat": (["blood splat", "liquid splat"], 3, 0.05, 1.0),
    # стоны и крики врагов убраны (раунд 14)
    # удар о землю и интерфейс
    "slam": (["heavy ground impact", "earth impact boom"], 2, 0.3, 3.0),
    "switch": (["soft click", "small mechanical click", "light click"], 3, 0.02, 0.5),   # раунд 14: тише и мягче
    "heartbeat": (["heartbeat single", "heart beat"], 1, 0.3, 2.0),
}
SKIP = re.compile(r"music|loop(?!.*fire)|ambien|song|voice over|speech|melody|chord|reverse|toy|robot|diarrh|wilhelm|kamen|munch|candy|"
                  r"cartoon|electronic|synth|bamboo|jeans|fart|funny|comic|8.?bit|retro|game sound|laser|sci.?fi|"
                  r"animal|horse|dog|cat\b|tram|bus\b|train|car\b|vehicle|station|traffic|UI\b|button", re.I)
# раунд 14: эти записи пользователю не понравились — не брать снова
EXCLUDE = {"steam_long": {365071, 234782, 398077, 367125, 211096, 581083},
           "steam_short": {457294, 234782, 398077, 365071, 367125, 211096, 581083},
           "step": {459964, 521590, 353799, 352870, 521587, 264469},
           "npc_step": {459964, 521590, 353799, 352870, 521587, 264469},
           "switch": {423957, 690300},
           "whoosh": {389590, 60004, 264591, 372899},
           "swing_snap": {367182, 60024, 614089, 485279, 876166},
           "chain_throw": {57643, 830322}}
EVENTS = {"step": 12, "npc_step": 10, "land": 3, "steam_short": 5, "shell": 4}    # сколько событий нарезать из записей


class _Redirect(urllib.request.HTTPRedirectHandler):
    """Перенаправление на адрес с не-ASCII символами (имена файлов авторов): экранируем путь."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        newurl = urllib.parse.quote(newurl, safe=":/?&=%#+@,;~")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_Redirect)


def get(url, headers=None, binary=False):
    req = urllib.request.Request(url, headers={**UA, **(headers or {})})
    with _OPENER.open(req, timeout=60) as r:
        data = r.read()
        return (data, r.geturl(), r.headers) if binary else data.decode("utf8", "replace")


def search_page(q, page=1):
    url = "https://freesound.org/search/?" + urllib.parse.urlencode(
        {"q": q, "f": 'license:"Creative Commons 0"', "s": "Automatic by relevance", "page": page})
    html = get(url)
    out = []
    for blk in re.findall(r'<div\s+class="bw-player"(.*?)tabindex', html, re.S):
        a = dict(re.findall(r'data-([a-z-]+)="([^"]*)"', blk))
        if "sound-id" not in a:
            continue
        out.append({"id": int(a["sound-id"]), "user": a["username"], "title": a.get("title", ""),
                    "dur": float(a.get("duration", 0) or 0), "downloads": int(a.get("num-downloads", 0) or 0),
                    "sr": float(a.get("samplerate", 0) or 0)})
    return out


def search(only=None):
    """only — список групп: пересобрать только их, остальные кандидаты оставить (раунд 14)."""
    os.makedirs(REFS, exist_ok=True)
    path = os.path.join(REFS, "candidates.json")
    cands = json.load(open(path, encoding="utf-8")) if only and os.path.exists(path) else {}
    for k in [k for k in cands if k not in WANT]:
        del cands[k]
    for name, (queries, n, lo, hi, *_) in WANT.items():
        if only and name not in only:
            if name in cands:
                cands[name] = cands[name][:n]
            continue
        seen, pool = set(), []
        for q in queries:
            for s in search_page(q) + search_page(q, 2):
                if name == "npc_step" and any(s["id"] == t["id"] for t in cands.get("step", [])):
                    continue                                  # NPC не должны звучать как герой
                if s["id"] in seen or s["id"] in EXCLUDE.get(name, ()) or SKIP.search(s["title"]) or not (lo <= s["dur"] <= hi):
                    continue
                seen.add(s["id"])
                pool.append(s)
            time.sleep(1.0)
        pool.sort(key=lambda s: -s["downloads"])
        cands[name] = pool[:n]
        print(f"{name}: {len(pool)} подходят, взяты {[ (s['id'], s['title'][:28]) for s in cands[name]]}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cands, f, ensure_ascii=False, indent=1)


def cookie_header(state_path):
    st = json.load(open(state_path, encoding="utf-8"))
    parts = [f"{c['name']}={c['value']}" for c in st.get("cookies", []) if "freesound.org" in c.get("domain", "")]
    return "; ".join(parts)


def download(state_path):
    os.makedirs(RAW, exist_ok=True)
    cands = json.load(open(os.path.join(REFS, "candidates.json"), encoding="utf-8"))
    ck = cookie_header(state_path)
    if "sessionid" not in ck:
        print("нет входа: сессия без sessionid")
        return
    for name, lst in cands.items():
        for s in lst:
            if any(fn.startswith(f"{s['id']}.") for fn in os.listdir(RAW)):
                continue
            user = urllib.parse.quote(s["user"])
            url = f"https://freesound.org/people/{user}/sounds/{s['id']}/download/"
            try:
                data, final, hdr = get(url, {"Cookie": ck, "Referer": f"https://freesound.org/people/{user}/sounds/{s['id']}/"}, binary=True)
            except Exception as e:  # noqa: BLE001
                print(f"{s['id']}: ошибка {e}")
                continue
            if data[:15].lower().startswith(b"<!doctype") or b"<html" in data[:200].lower():
                print(f"{s['id']}: вместо файла страница (вход не прошёл?)")
                return
            ext = os.path.splitext(urllib.parse.urlparse(final).path)[1].lower() or ".wav"
            cd = hdr.get("Content-Disposition", "")
            m = re.search(r'filename="?([^";]+)', cd)
            if m:
                ext = os.path.splitext(m.group(1))[1].lower() or ext
            with open(os.path.join(RAW, f"{s['id']}{ext}"), "wb") as f:
                f.write(data)
            print(f"{name}: {s['id']}{ext} {len(data) // 1024} КБ")
            time.sleep(1.5)


# ---------- обработка ----------
SR = 44100


def load(path):
    import soundfile as sf
    from scipy.signal import resample_poly
    x, sr = sf.read(path, always_2d=True, dtype="float32")
    x = x.mean(1)
    if sr != SR:
        g = np.gcd(int(sr), SR)
        x = resample_poly(x, SR // g, int(sr) // g).astype(np.float32)
    return x


def trim(x, max_len, thr_db=-42.0, head=0.004):
    """Отрезать тишину спереди и сзади, ограничить длину, короткие затухания на краях."""
    env = np.abs(x)
    thr = env.max() * 10 ** (thr_db / 20)
    idx = np.nonzero(env > thr)[0]
    if len(idx) == 0:
        return x[:1]
    a = max(idx[0] - int(head * SR), 0)
    b = idx[-1] + 1
    y = x[a:b][: int(max_len * SR)].copy()
    fi, fo = min(int(0.003 * SR), len(y) // 4), min(int(0.04 * SR), len(y) // 3)
    if fi:
        y[:fi] *= np.linspace(0, 1, fi)
    if fo:
        y[-fo:] *= np.linspace(1, 0, fo)
    return y


def norm(x, peak_db=-1.0, rms_db=None):
    p = np.abs(x).max() or 1.0
    y = x / p * 10 ** (peak_db / 20)
    if rms_db is not None:
        r = np.sqrt(np.mean(y ** 2)) or 1e-9
        g = 10 ** (rms_db / 20) / r
        y = y * min(g, 10 ** (peak_db / 20) / (np.abs(y).max() or 1))
    return y


def mix(base, layer, delay, gain):
    d = int(delay * SR)
    n = max(len(base), d + len(layer))
    out = np.zeros(n, np.float32)
    out[:len(base)] += base
    out[d:d + len(layer)] += layer * gain
    return out


# итоговые звуки: имя -> (исходная группа, макс. длина с, громкость RMS дБ, паровая подложка (задержка, усиление) или None)
OUT = {
    "step": ("step", 0.3, -22, None), "npc_step": ("npc_step", 0.3, -26, None), "land": ("land", 0.7, -18, (0.02, 0.25)),
    "dash": ("whoosh", 0.45, -24, None), "jump": ("jump_push", 0.4, -24, None),   # раунд 16: прыжок без пара
    "steam": ("steam_short", 1.2, -30, None), "steam_long": ("steam_long", 1.6, -32, None),
    "switch_module": ("gears", 0.8, -20, (0.12, 0.3)), "ult_ready": ("chime", 1.0, -28, None),
    "swing_light": ("swing_light", 0.5, -20, None), "swing_snap": ("swing_snap", 0.3, -20, None),
    # раунд 16: тяжёлые взмахи без вшитого пара (пар — отдельно на каждый 4–5-й удар), у серпа свой
    "swing_heavy": ("swing_heavy", 0.9, -18, None), "swing_heavy_sickle": ("swing_heavy_sickle", 0.9, -18, None),
    "steam_puff": ("steam_short", 0.25, -30, None),
    "slash": ("slash_flesh", 0.8, -16, None), "gore": ("gore", 1.2, -17, None), "bone": ("bone", 0.8, -18, None),
    "clang": ("clang", 1.0, -20, None), "chain": ("chain", 1.4, -20, None), "chain_throw": ("chain_throw", 1.2, -18, None),
    "chain_loop": ("chain_loop", 1.6, -21, None),
    "shotgun": ("shotgun", 1.8, -13, (0.05, 0.45)), "shotgun_double": ("shotgun_double", 2.2, -12, (0.06, 0.5)),
    "shotgun_reload": ("shotgun_open", 1.6, -20, None), "shell": ("shell", 0.7, -24, None),
    "fire_burst": ("fire_burst", 2.0, -15, (0.0, 0.35)), "fire_loop": ("fire_loop", 6.0, -24, None),
    "revolver": ("revolver", 1.5, -15, (0.04, 0.2)), "revolver_cock": ("revolver_cock", 0.5, -22, None),
    "revolver_reload": ("revolver_reload", 2.5, -21, None), "dry_fire": ("dry_fire", 0.4, -24, None),
    "hit": ("hit", 0.6, -17, None), "body_fall": ("body_fall", 1.2, -18, None), "splat": ("splat", 0.8, -20, None),
    "slam": ("slam", 2.2, -13, (0.03, 0.55)), "switch": ("switch", 0.25, -30, None), "heartbeat": ("heartbeat", 1.2, -18, None),
}


SOFT = {"steam_long": (0.15, 0.6), "ult_ready": (0.01, 0.5), "step": (0.004, 0.12),   # вход, затухание, с
        "steam": (0.04, 0.35), "jump": (0.003, 0.12), "npc_step": (0.004, 0.12), "dash": (0.02, 0.15),
        "steam_puff": (0.02, 0.12)}
# раунд 15: срез верха (Гц) — пар мягче, шаги NPC глуше, рывок глуше
LOWPASS = {"steam": 5000, "steam_puff": 5000, "steam_long": 5000, "npc_step": 2500, "dash": 3500}
# раунд 15: пик громкости не дальше этой доли длины, иначе звук «всасывается» (нарастает к концу) — вариант выбрасывается
EARLY = {"swing_light": 0.36, "swing_snap": 0.3, "dash": 0.5, "swing_heavy": 0.5, "swing_heavy_sickle": 0.55,
         "step": 0.2, "npc_step": 0.3}      # шаги: удар каблука в начале — чётко, без шарканья
MAX_N = {"swing_snap": 4}
LOOPS = {"chain_loop": 0.25}          # склейка конца с началом, с: звук играет по кругу без щелчка
LOUDER = {"revolver": 3.0}            # громче на N дБ при том же пике (мягкое ограничение пиков)


OVERLAY = {"chain_throw": ("whoosh", 0.0, 0.6, 3000), "jump": ("cloth", 0.0, 0.35, None)}
# раунд 16: шаги звучат ровно — из нарезки оставить N самых похожих по тембру и громкости
SIMILAR = {"step": 4}


def features(x):
    """Тембр (спектральный центроид, лог) и длительность — для подбора похожих вариантов."""
    sp = np.abs(np.fft.rfft(x, 8192))
    fr = np.fft.rfftfreq(8192, 1 / SR)
    cen = float((sp * fr).sum() / (sp.sum() or 1.0))
    return np.array([np.log(max(cen, 1.0)), len(x) / SR * 4.0])


def most_similar(src, n):
    f = np.array([features(x) for x, _ in src])
    med = np.median(f, axis=0)
    order = np.argsort(((f - med) ** 2).sum(1))
    return [src[i] for i in sorted(order[:n])]


def lowpass(x, hz):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(4, hz, "low", fs=SR, output="sos"), x).astype(np.float32)


def peak_pos(x):
    w = int(0.01 * SR)
    e = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, "same"))
    return float(np.argmax(e)) / max(len(x), 1)


def louder(x, db):
    """Поднять громкость на db, мягко срезая пики (tanh), пик остаётся прежним."""
    p = np.abs(x).max() or 1.0
    y = x / p * 10 ** (db / 20)
    k = np.tanh(10 ** (db / 20))
    return (np.tanh(y) / k * p).astype(np.float32)


def make_loop(srcs, length, xf):
    """Насыщенный круговой звук: записи друг на друга, конец плавно переходит в начало."""
    n, f = int(length * SR), int(xf * SR)
    out = np.zeros(n + f, np.float32)
    for k, x in enumerate(srcs):
        x = x[: n + f]
        g = (1.0, 0.75, 0.6, 0.6)[k % 4] / (np.sqrt(np.mean(x ** 2)) or 1.0)
        out[: len(x)] += x * g * 0.1
    head, tail = out[:f].copy(), out[n:n + f]
    ramp = np.linspace(0, 1, f, dtype=np.float32)
    out = out[:n]
    out[:f] = head * ramp + tail * (1 - ramp)
    return out


def slice_events(x, max_len, thr_db=-26.0, gap=0.05, min_len=0.04):
    """Отдельные события (шаги, пшики, гильзы) из длинной записи: огибающая 5 мс, порог от пика, склейка пауз < gap."""
    w = int(0.005 * SR)
    env = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, mode="same"))
    on = env > env.max() * 10 ** (thr_db / 20)
    idx = np.nonzero(np.diff(on.astype(np.int8)))[0]
    if on[0]:
        idx = np.r_[0, idx]
    if on[-1]:
        idx = np.r_[idx, len(on) - 1]
    segs = []
    for a, b in zip(idx[::2], idx[1::2]):
        if segs and a - segs[-1][1] < gap * SR:
            segs[-1][1] = b
        else:
            segs.append([a, b])
    out = []
    for a, b in segs:
        a2 = max(a - int(0.006 * SR), 0)
        b2 = min(b + int(0.08 * SR), len(x))
        if (b - a) >= min_len * SR and (b2 - a2) <= max_len * SR * 1.5:
            out.append(x[a2:b2].copy())
    return out


def raw_path(sid):
    for fn in os.listdir(RAW):
        if fn.startswith(f"{sid}."):
            return os.path.join(RAW, fn)
    return None


def process():
    import soundfile as sf
    os.makedirs(GAME, exist_ok=True)
    cands = json.load(open(os.path.join(REFS, "candidates.json"), encoding="utf-8"))
    sliced = {}                                          # группа -> [(отрезок, источник)]
    for grp, n in EVENTS.items():
        ev = []
        for s in cands.get(grp, []):
            p = raw_path(s["id"])
            if p:
                ev += [(e, s) for e in slice_events(load(p), 1.2)]
        if grp in EARLY:
            ev = [(e, s) for e, s in ev if peak_pos(trim(e, OUT[grp][1])) <= EARLY[grp]]
        ev.sort(key=lambda t: -float(np.sqrt(np.mean(t[0] ** 2))))
        # разнообразие: по очереди из разных записей, самые громкие
        pick, per = [], {}
        for e, s in ev:
            if per.get(s["id"], 0) < (n + 1) // max(len(cands.get(grp, [])), 1) + 1 and len(pick) < n:
                pick.append((e, s))
                per[s["id"]] = per.get(s["id"], 0) + 1
        sliced[grp] = pick
        print(f"нарезано {grp}: {len(ev)} событий, взято {len(pick)}")
    steam = [e for e, _ in sliced.get("steam_short", [])]
    meta, credits, used = {}, [], {}
    for name, (grp, max_len, rms, layer) in OUT.items():
        files = []
        if grp in sliced:
            src = [(trim(e, max_len), s) for e, s in sliced[grp]]
        else:
            src = []
            for s in cands.get(grp, []):
                p = raw_path(s["id"])
                if not p:
                    continue
                try:
                    src.append((trim(load(p), max_len), s))
                except Exception as e:  # noqa: BLE001
                    print(f"{name}: {s['id']} не читается ({e})")
        if name == "shotgun_double":
            # залп двумя стволами: два выстрела обреза с разносом 35 мс (в CC0 подходящей записи нет)
            shots = [(trim(load(raw_path(s["id"])), max_len), s) for s in cands.get("shotgun", []) if raw_path(s["id"])]
            src = [(mix(a, b, 0.035, 0.85), sa) for (a, sa), (b, _) in zip(shots, shots[1:] + shots[:1])][:3]
        if name in EARLY:
            keep = [(x, s) for x, s in src if peak_pos(x) <= EARLY[name]]
            print(f"{name}: без «всасывания» {len(keep)} из {len(src)}")
            src = keep
        if name in MAX_N:
            src = src[:MAX_N[name]]
        if name in LOOPS:
            have = [s for s in cands.get(grp, []) if raw_path(s["id"])]
            raws = [trim(load(raw_path(s["id"])), max_len + LOOPS[name] + 0.5) for s in have]
            for s in have:
                used[s["id"]] = s
            src = [(make_loop(raws, max_len, LOOPS[name]), have[0])] if raws else []
        if name in OVERLAY and cands.get(OVERLAY[name][0]) and raw_path(cands[OVERLAY[name][0]][0]["id"]):
            # наложение второй записи: цепь + низкий свист (раунд 15), прыжок + шорох одежды (раунд 16)
            og, od, ogain, olp = OVERLAY[name]
            o = cands[og][0]
            w = trim(load(raw_path(o["id"])), max_len)
            if olp:
                w = lowpass(w, olp)
            w = w / (np.abs(w).max() or 1.0)
            src = [(mix(x / (np.abs(x).max() or 1.0), w, od, ogain), s) for x, s in src]
            used[o["id"]] = o
        if name in SIMILAR and len(src) > SIMILAR[name]:
            src = most_similar(src, SIMILAR[name])
        for k, (x, s) in enumerate(src):
            if name in LOWPASS:
                x = lowpass(x, LOWPASS[name])
            if name in SOFT:
                # мягкий вход и долгое затухание: звук не выпрыгивает (раунд 14)
                fi, fo = min(int(SOFT[name][0] * SR), len(x) // 3), min(int(SOFT[name][1] * SR), len(x) // 2)
                x = x.copy()
                if fi:
                    x[:fi] *= np.linspace(0, 1, fi) ** 2
                if fo:
                    x[-fo:] *= np.linspace(1, 0, fo) ** 2
            if layer and steam:
                st = steam[k % len(steam)]
                x = mix(x, norm(st, -6.0), layer[0], layer[1])
            x = norm(x, -1.0, rms)
            if name in LOUDER:
                x = louder(x, LOUDER[name])
            fn = f"{name}_{len(files)}.ogg"
            sf.write(os.path.join(GAME, fn), x, SR, format="OGG", subtype="VORBIS")
            files.append(fn)
            used[s["id"]] = s
        meta[name] = files
        print(f"{name}: {len(files)}")
    with open(os.path.join(GAME, "sfx.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    # убрать звуки, которых больше нет в наборе (стоны, скольжение, лишние варианты)
    keep = {fn for fs in meta.values() for fn in fs}
    for fn in os.listdir(GAME):
        base = fn[:-7] if fn.endswith(".import") else fn
        if base.endswith(".ogg") and base not in keep:
            os.remove(os.path.join(GAME, fn))
            print("удалён", fn)
    lines = ["# Звуки Project Z", "", "Все исходники — Freesound.org, лицензия CC0 (Creative Commons 0, общественное достояние).",
             "Атрибуция не требуется; список ведётся для учёта. Обработка: tools/sfx_fetch.py (обрезка, моно, громкость, паровая подложка).", "",
             "| id | Название | Автор | Ссылка |", "|---|---|---|---|"]
    for sid, s in sorted(used.items()):
        lines.append(f"| {sid} | {s['title']} | {s['user']} | https://freesound.org/people/{s['user']}/sounds/{sid}/ |")
    open(os.path.join(GAME, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "search"
    if cmd == "search":
        search(sys.argv[2].split(",") if len(sys.argv) > 2 else None)
    elif cmd == "download":
        download(sys.argv[2])
    elif cmd == "process":
        process()
