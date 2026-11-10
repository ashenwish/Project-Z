extends Node
class_name Sfx
## Звуки (раунд 13): стилизованный паровой набор из Freesound (CC0), обработка tools/sfx_fetch.py.
## Каждое имя — группа вариантов (AudioStreamRandomizer: случайный вариант, высота ±5 %).
## Шины: Master → SFX и Steam (пар отдельно, чтобы потом можно было приглушить).

const POOL := 20
const STEAM := ["steam", "steam_long", "steam_puff", "switch_module", "mech_steam"]
const FIXED := ["revolver", "mech_maxim"]     # один и тот же звук на каждый выстрел: без разброса высоты и громкости (раунд 14)
const STEADY := ["step", "mech_step"]        # шаги ровно: варианты по очереди, разброс высоты ±2 %, громкости 1 дБ (раунд 16)

var streams := {}               # имя -> AudioStreamRandomizer
var players: Array[AudioStreamPlayer] = []
var next_i := 0
var delayed: Array = []         # [[время, имя, громкость]]
var played: Array = []          # журнал для тестов: имена по порядку
var muted := false
var holds := {}                 # длительные звуки: имя -> {p, gain, on}
var files_of := {}              # имя -> файлы группы


func _ready() -> void:
	for bus in ["SFX", "Steam"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx.json"))
	for name in meta:
		var files: Array = meta[name]
		if files.is_empty():
			continue
		files_of[name] = files
		var r := AudioStreamRandomizer.new()
		r.random_pitch = 1.0 if name in FIXED else (1.02 if name in STEADY else 1.05)
		r.random_volume_offset_db = 0.0 if name in FIXED else (1.0 if name in STEADY else 1.5)
		r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS if files.size() > 2 else AudioStreamRandomizer.PLAYBACK_RANDOM
		if name in STEADY:
			r.playback_mode = AudioStreamRandomizer.PLAYBACK_SEQUENTIAL
		for f in files:
			r.add_stream(-1, load("res://assets/audio/" + f))
		streams[name] = r
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


func has(name: String) -> bool:
	return streams.has(name)


## Длительный звук по состоянию (раунд 15): пока on — играет по кругу, после — плавно затихает за fade_out.
## Вызывать каждый кадр. Файл берётся первый из группы, зациклен при обработке (tools/sfx_fetch.py, LOOPS).
func hold(name: String, on: bool, vol_db := 0.0, fade_in := 0.05, fade_out := 0.5) -> void:
	if not streams.has(name):
		return
	var h: Dictionary = holds.get(name, {})
	if h.is_empty():
		var p := AudioStreamPlayer.new()
		var st: AudioStream = load("res://assets/audio/" + files_of[name][0])
		if st is AudioStreamOggVorbis:
			st.loop = true
		p.stream = st
		p.bus = "SFX"
		add_child(p)
		h = {"p": p, "gain": 0.0, "on": false}
		holds[name] = h
	var p: AudioStreamPlayer = h.p
	if on and not h.on:
		played.append(name)
		if not p.playing and not muted:
			p.play()
	h.on = on
	var dt := get_process_delta_time()
	var target := 1.0 if on else 0.0
	var step := dt / maxf(fade_in if on else fade_out, 0.001)
	h.gain = move_toward(float(h.gain), target, step)
	# кривая затухания: громкость по квадрату, без ступеньки в конце
	p.volume_db = vol_db + linear_to_db(maxf(float(h.gain) * float(h.gain), 0.0001))
	if h.gain <= 0.0 and p.playing:
		p.stop()


## Насколько громко сейчас длительный звук (0..1) — для проверок.
func hold_gain(name: String) -> float:
	return float(holds.get(name, {}).get("gain", 0.0))


## Звук сейчас; delay > 0 — позже (гильзы долетают до пола, тело падает).
func play(name: String, vol_db := 0.0, delay := 0.0) -> void:
	if not streams.has(name):
		return
	if delay > 0.0:
		delayed.append([delay, name, vol_db])
		return
	played.append(name)
	if played.size() > 200:
		played.pop_front()
	if muted:
		return
	var p := players[next_i]
	next_i = (next_i + 1) % POOL
	p.stream = streams[name]
	p.volume_db = vol_db
	p.bus = "Steam" if name in STEAM else "SFX"
	p.play()


func _process(delta: float) -> void:
	for i in range(delayed.size() - 1, -1, -1):
		delayed[i][0] -= delta
		if delayed[i][0] <= 0.0:
			var d: Array = delayed[i]
			delayed.remove_at(i)
			play(d[1], d[2])
