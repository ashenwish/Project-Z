extends SceneTree
## Проверка правок раунда 16 без окна: godot --headless --path . -s res://tests/test_round16.gd
## Код выхода 1 — есть ошибки.

var arena
var fails := 0


func check(name: String, ok: bool, info: Variant = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if str(info) == "" else "  [%s]" % str(info)))
	if not ok:
		fails += 1


func wait(t: float) -> void:
	await create_timer(t).timeout


func fresh(mod := "blade") -> void:
	arena.action = ""
	arena.act_queued = ""
	arena.combo_t = 0.0
	arena.gun = ""
	arena.inp_override = Vector2.ZERO
	arena.mouse_override = Vector2(480, 500)
	arena.module = mod
	arena.loco = "idle"
	arena.hero_pos = Vector3.ZERO
	arena.airborne = false
	arena.hero_h = 0.0
	arena.hero_vy = 0.0
	arena.jumps_used = 0
	arena.dash_t = -1.0
	arena.hook = ""
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
		if e.flame != null:
			e.flame.queue_free()
	arena.respawn.clear()
	await wait(0.2)
	arena.sfx.played.clear()


func heard(name: String) -> bool:
	return arena.sfx.played.has(name)


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


## Бег вниз в течение t секунд; flick — каждые 0,1 с менять клавишу влево/вправо, S зажата
## (на кадр смены нажаты обе: только вниз); gap — вместо этого ввод на кадр пропадает целиком.
## Возвращает времена шагов.
func run_steps(t: float, flick: bool, gap := false) -> Array:
	var times := []
	var el := 0.0
	var k := 0
	var before: int = arena.sfx.played.count("step")
	while el < t:
		if flick:
			var ph := int(el / 0.1)
			if ph != k:
				k = ph
				arena.inp_override = Vector2.ZERO if gap else Vector2(0, 1)
				await process_frame
				el += arena.get_process_delta_time()
			arena.inp_override = Vector2(-1 if k % 2 == 0 else 1, 1)
		else:
			arena.inp_override = Vector2(0, 1)
		await process_frame
		el += arena.get_process_delta_time()
		var now: int = arena.sfx.played.count("step")
		if now > before:
			times.append(el)
			before = now
	arena.inp_override = Vector2.ZERO
	return times


func run() -> void:
	await wait(0.2)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx.json"))
	var hud = arena.hud_g

	# п.2, п.5 HUD
	var hm: Dictionary = hud.meta
	check("делений: здоровье 12, ульта 6", int(hm.hp_segs) == 12 and int(hm.ult_segs) == 6, [hm.hp_segs, hm.ult_segs])
	var img: Image = hud.gauge.texture.get_image()
	var cx := float(hm.center[0])
	var cy := float(hm.center[1])
	var plus := 0
	var rim := 0
	var red := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var r := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if y < 14 and absf(x - cx) < 9 and c.r > 0.9 and c.g > 0.75:
				plus += 1                             # светлый плюс f0cdb4
			if r > 50.6 and c.r > 0.5 and c.g > 0.4:
				rim += 1                              # латунь снаружи кольца здоровья
			if r > 38.0 and r < 49.0 and c.r > 0.4 and c.g < 0.2:     # с раунда 17 кольцо бордовое (7d0f1c)
				red += 1
	check("жёлтого плюсика сверху нет", plus == 0, plus)
	check("внешней латунной окантовки нет", rim == 0, rim)
	check("кольцо здоровья толще (13 px)", float(hm.get("size", [0])[0]) == 104.0 and red > 1500, [hm.size, red])
	var sw: Image = hud.switch_tex.get_image()
	var top_up := 99
	var top_down := 99
	for y in 14:
		if sw.get_pixel(5, y).a > 0.0 and top_up == 99:
			top_up = y
		if sw.get_pixel(25, y).a > 0.0 and top_down == 99:
			top_down = y
	var cu := sw.get_pixel(5, top_up + 2)
	var cd := sw.get_pixel(25, top_down + 2)
	check("кнопка рывка нажимается: ниже и темнее", top_down >= top_up + 3 and cd.v < cu.v, [top_up, top_down])
	check("кнопка тёмно-серая", absf(cu.r - cu.b) < 0.1 and cu.v < 0.5, cu)

	# п.1 тяжёлые удары: пар раз в 4–5
	await fresh()
	var hv: String = arena.HEAVY.blade
	var steams := 0
	var looks := 0
	for i in 18:
		arena.sfx.played.clear()
		arena._start_action(hv, 0)
		if arena.act_steam:
			looks += 1
		arena.action = ""
		await wait(0.08)
		if heard("steam"):
			steams += 1
	check("пар на 18 тяжёлых ударов: 3–5 раз (каждый 4–5-й)", steams >= 3 and steams <= 5, steams)
	check("облако пара на тех же ударах", looks == steams, [looks, steams])
	check("вшитого пара в тяжёлом взмахе нет, вариантов клинка ≥3", meta.swing_heavy.size() >= 3)
	await fresh("sickle")
	arena._start_action(arena.HEAVY.sickle, 0)
	arena.action = ""
	check("у серпа свой тяжёлый взмах", heard("swing_heavy_sickle") and not heard("swing_heavy"), arena.sfx.played)

	# п.3 прыжок
	await fresh()
	arena._start_jump()
	await wait(0.1)
	check("прыжок — обычный звук, без пара", heard("jump") and not heard("steam") and not heard("steam_puff"), arena.sfx.played)
	arena._start_jump()
	await wait(0.1)
	check("двойной прыжок — с лёгким паром", heard("steam_puff"), arena.sfx.played)
	while arena.airborne:
		await process_frame

	# п.4 шаги
	check("шагов 4 похожих варианта, по очереди, разброс ±2 %", meta.step.size() == 4
		and arena.sfx.streams["step"].random_pitch <= 1.021
		and arena.sfx.streams["step"].playback_mode == AudioStreamRandomizer.PLAYBACK_SEQUENTIAL)
	await fresh()
	var even := await run_steps(2.0, false)
	await fresh()
	var flick := await run_steps(2.0, true)
	var spread := 0.0
	for i in range(3, flick.size()):             # первый промежуток длиннее — разгон с места
		spread = maxf(spread, absf((flick[i] - flick[i - 1]) - (flick[2] - flick[1])))
	check("бег прямо: шаги ровно", even.size() >= 6 and even.size() <= 10, even.size())
	check("бег вниз с перебором влево-вправо: столько же шагов", absi(flick.size() - even.size()) <= 1, [even.size(), flick.size()])
	check("и такт ровный (разброс промежутков ≤ 0,05 с)", spread <= 0.05, spread)
	await fresh()
	var holes := await run_steps(2.0, true, true)
	var gap := 9.0
	for i in range(1, holes.size()):
		gap = minf(gap, holes[i] - holes[i - 1])
	check("даже если ввод на кадр пропадает — шаги не чаще 0,17 с", gap >= 0.165 and holes.size() >= 4, [gap, holes.size()])

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
