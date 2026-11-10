extends SceneTree
## Проверка правок раунда 8 без окна: godot --headless --path . -s res://tests/test_round8.gd
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
	arena.act_finisher = false
	arena.combo_t = 0.0
	arena.gun = ""
	arena.gun_queued = ""
	arena.inp_override = Vector2.ZERO
	arena.mouse_override = Vector2(480, 500)
	arena.module = mod
	arena.hero_pos = Vector3.ZERO
	arena.airborne = false
	arena.hero_h = 0.0
	arena.hero_vy = 0.0
	arena.jumps_used = 0
	arena.dash_t = -1.0
	arena.dash_cd = 0.0
	arena.dash_used = 0
	arena.dash_queued = false
	arena.ult_t = -1.0
	arena.spin_cd = 0.0
	arena.invuln = false
	arena.ammo = {"shotgun": 8, "pistol": 12}
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
		if e.flame != null:
			e.flame.queue_free()
	arena.respawn.clear()
	Engine.time_scale = 1.0
	await wait(0.03)


func enemy_at(p: Vector3, hp := -1) -> Dictionary:
	arena._spawn_enemy(p)
	var e: Dictionary = arena.enemies[-1]
	if hp > 0:
		e.hp = hp
	return e


func aim_at(p: Vector3) -> void:
	arena.mouse_override = arena.cam.unproject_position(arena._snap(p))
	await wait(0.03)


## Два рывка с паузой gap между концом первого и началом второго.
func two_dashes(gap: float) -> float:
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(arena.DASH_TIME + 0.02 + gap)
	arena._start_dash()
	while arena.dash_t >= 0.0:
		await process_frame
	return arena.dash_cd


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)

	# п.2 тяжёлые клинка
	var u: Dictionary = arena.meta.upper.blade_heavy
	var total := 0.0
	for d in u.durations_ms:
		total += float(d)
	check("серия клинка на 10 %% длиннее: около 1473 мс", absf(total - 1473.0) < 5.0, total)

	# п.6 обрез
	await fresh("shotgun")
	var ang: Vector3 = arena._world_dir(Vector2(1, 0))
	await aim_at(ang * 3.0)
	var near := enemy_at(ang * 2.0)
	var corp: int = arena.gore.corpses.size()
	var pieces0: int = arena.gore.debris.size()
	arena._shotgun_hits()
	Engine.time_scale = 1.0
	check("вплотную убивает с одного выстрела", not arena.enemies.has(near))
	check("и расчленяет: лежит труп и летят куски", arena.gore.corpses.size() == corp + 1 and arena.gore.debris.size() > pieces0)
	check("исход blast", arena.gore.corpses[-1].node.texture.resource_path.contains("blast"), arena.gore.corpses[-1].node.texture.resource_path)
	await fresh("shotgun")
	await aim_at(ang * 3.0)
	var a := enemy_at(ang * 1.5)
	var b := enemy_at(ang * 2.2)
	arena._shotgun_hits()
	Engine.time_scale = 1.0
	check("все вплотную в конусе убиты", not arena.enemies.has(a) and not arena.enemies.has(b))
	await fresh("shotgun")
	await aim_at(ang * 3.0)
	var mid := enemy_at(ang * 3.5, 100)
	var far := enemy_at(ang * 6.0, 100)
	arena._shotgun_hits()
	check("средне 8 (раунд 10)", mid.hp == 92, mid.hp)
	check("дальше 4 (раунд 10)", far.hp == 96, far.hp)

	# п.4 рывки
	var cd := await two_dashes(0.0)
	check("подряд: откат 2 с", cd > 1.9, cd)
	cd = await two_dashes(0.2)
	check("пауза до 0,35 с: откат полный", cd > 1.8, cd)
	cd = await two_dashes(0.55)
	check("пауза 0,55 с: откат короче", cd > 0.8 and cd < 1.7, cd)
	cd = await two_dashes(0.75)
	check("пауза 0,75 с: почти минимум", cd < 1.0, cd)
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(arena.DASH_TIME + 0.05)
	check("после первого отката нет", arena.dash_cd <= 0.0)
	await wait(0.85)
	check("второго не было: откат минимальный", arena.dash_cd > 0.0 and arena.dash_cd <= 0.6, arena.dash_cd)
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(0.1)
	arena._start_dash()
	while arena.dash_used > 0:
		await process_frame
	check("нажатие во время первого: подряд, откат полный", arena.dash_cd > 1.8, arena.dash_cd)

	# п.3 ноги и корпус
	await fresh()
	var run_dir: Vector3 = arena._world_dir(Vector2(1, 0))
	arena.inp_override = Vector2(1, 0)
	await aim_at(arena.hero_pos - run_dir * 3.0)     # курсор за спиной
	for i in 30:
		arena.mouse_override = arena.cam.unproject_position(arena.hero_pos - run_dir * 3.0)
		await process_frame
	var legs_ok: bool = arena.legs_dir == arena._dir_index(run_dir)
	check("курсор за спиной: ноги по ходу", legs_ok, arena.legs_dir)
	check("корпус не дальше 45° от ног (раунд 10)", absf(wrapf(arena.upper_ang - arena._screen_ang(run_dir), -180.0, 180.0)) <= 47.0, arena.upper_ang)
	var a0: float = arena.leg_phase
	await wait(0.05)
	var dp: float = fposmod(arena.leg_phase - a0, 1.0)
	check("цикл бега идёт вперёд", dp > 0.0 and dp < 0.5, dp)
	var side: Vector3 = run_dir.cross(Vector3.UP)
	for i in 30:
		arena.mouse_override = arena.cam.unproject_position(arena.hero_pos + side * 3.0)
		await process_frame
	check("курсор вбок: ноги по ходу", arena.legs_dir == arena._dir_index(run_dir), arena.legs_dir)
	check("корпус вбок: предел 45° (раунд 10)", absf(absf(wrapf(arena.upper_ang - arena._screen_ang(run_dir), -180.0, 180.0)) - 45.0) < 3.0, arena.upper_ang)
	await fresh()
	arena.inp_override = Vector2.ZERO
	await aim_at(arena.hero_pos + run_dir * 3.0)
	await wait(0.4)
	check("стоя ноги к курсору", absf(wrapf(arena.legs_ang - arena._screen_ang(run_dir), -180.0, 180.0)) < 25.0, arena.legs_ang)

	# п.1 левая рука качается
	var arm_tex: Texture2D = load("res://assets/hero/layers/A_run.png")
	var img: Image = arm_tex.get_image()
	var fw: int = img.get_width() / (8 * 4)
	var col0 := img.get_region(Rect2i(0, 128, fw, 128))
	var col4 := img.get_region(Rect2i(fw * 4 * 4, 128, fw, 128))
	check("кадры левой руки разные: рука качается", col0.get_data() != col4.get_data())

	# п.5 ульта
	await fresh()
	check("след вращения есть", ResourceLoader.exists("res://assets/hero/layers/X_ult_spin.png"))
	var e := enemy_at(Vector3(1.5, 0, 0), 100)
	var r0: float = Vector2(e.p.x, e.p.z).length()
	arena._ult_press()
	var dirs := []
	var frames := {}
	var trail_on := false
	while arena.ult_t >= 0.0:
		if dirs.is_empty() or dirs[-1] != arena.upper_dir:
			dirs.append(arena.upper_dir)
		frames[arena._spin_frame()] = true
		trail_on = trail_on or arena.trail.visible
		await process_frame
	check("около 4 оборотов: 32+ смен направления (раунд 10)", dirs.size() >= 33 and dirs.size() <= 38, dirs.size())
	check("все кадры вращения", frames.size() >= 5, frames.keys())
	check("виден след клинка", trail_on)
	check("враг отброшен", Vector2(e.p.x, e.p.z).length() > r0, Vector2(e.p.x, e.p.z).length())
	check("урон прошёл", e.hp < 100, e.hp)
	await fresh()
	var p0: Vector3 = arena.hero_pos
	arena._ult_press()
	await wait(1.0)
	check("без ввода герой понемногу идёт к прицелу", arena.hero_pos.distance_to(p0) > 0.2 and arena.hero_pos.distance_to(p0) < 1.0, arena.hero_pos.distance_to(p0))

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
