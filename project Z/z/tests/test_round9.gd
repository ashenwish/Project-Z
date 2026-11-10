extends SceneTree
## Проверка правок раунда 9 без окна: godot --headless --path . -s res://tests/test_round9.gd
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
	arena.combo_free = false
	arena.gun = ""
	arena.gun_queued = ""
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
	arena.dash_cd = 0.0
	arena.dash_used = 0
	arena.dash_queued = false
	arena.slam = ""
	arena.slam_cd = 0.0
	arena.hook = ""
	arena.hook_cd = 0.0
	arena.run_start_t = -1.0
	arena.run_stop_t = -1.0
	arena.land_t = -1.0
	arena.takeoff_t = -1.0
	arena.switch_t = -1.0
	arena.aim_free = 0.0
	arena._hide_chain()
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


func tex_is(sprite: Sprite3D, name: String) -> bool:
	return sprite.texture == arena.tex.get(arena._layer(name))


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var fwd: Vector3 = arena._world_dir(Vector2(1, 0))
	var side: Vector3 = fwd.cross(Vector3.UP)

	# п.1 корпус не дальше 80° от ног
	await fresh()
	arena.inp_override = Vector2(1, 0)
	var worst := 0.0
	for i in 40:
		arena.mouse_override = arena.cam.unproject_position(arena.hero_pos - fwd * 3.0)
		await process_frame
		if i > 15:
			worst = maxf(worst, absf(wrapf(arena.upper_ang - arena._screen_ang(fwd), -180.0, 180.0)))
	check("курсор позади: корпус не разворачивается назад", worst <= 47.0, worst)
	check("ноги по ходу", arena.legs_dir == arena._dir_index(fwd), arena.legs_dir)
	for i in 30:
		arena.mouse_override = arena.cam.unproject_position(arena.hero_pos + side * 3.0)
		await process_frame
	check("курсор вбок (90°): корпус на пределе 45° (раунд 10)", absf(absf(wrapf(arena.upper_ang - arena._screen_ang(fwd), -180.0, 180.0)) - 45.0) < 3.0, arena.upper_ang)
	# удар поворачивает полностью и возвращается
	for i in 3:
		arena.mouse_override = arena.cam.unproject_position(arena.hero_pos - fwd * 3.0)
		await process_frame
	arena._request("light")
	check("на бегу удар назад уходит на 90° от хода (раунд 12)", absf(absf(wrapf(arena.act_dir * 45.0 - arena._screen_ang(fwd), -180.0, 180.0)) - 90.0) < 1.0, arena.act_dir)
	arena.action = ""
	arena.aim_free = 0.0
	await wait(0.4)
	check("после удара корпус вернулся к пределу", absf(wrapf(arena.upper_ang - arena._screen_ang(fwd), -180.0, 180.0)) <= 47.0, arena.upper_ang)
	await fresh()
	await aim_at(arena.hero_pos - fwd * 3.0)
	await wait(0.4)
	check("стоя корпус за курсором полностью", absf(wrapf(arena.upper_ang - arena._screen_ang(-fwd), -180.0, 180.0)) < 25.0, arena.upper_ang)
	await aim_at(arena.hero_pos + fwd * 3.0)
	var seen_dirs := {}
	for i in 30:
		await process_frame
		seen_dirs[arena.upper_dir] = true
	check("поворот корпуса через промежуточные кадры", seen_dirs.size() >= 2, seen_dirs.keys())

	# качка бега
	var u: Dictionary = arena.meta.legs.run
	var xs := []
	for o in u.offsets_px["s"]:
		xs.append(int(o[0]))
	check("боковой сдвиг корпуса меньше прежних ±2 px", xs.max() - xs.min() <= 2, xs)

	# помощь прицеливания
	await fresh()
	await aim_at(fwd * 3.0)
	var angled: Vector3 = (fwd + side * 0.4).normalized()     # около 22° от курсора
	var e := enemy_at(angled * 1.5, 100)
	arena._request("light")
	check("удар навёлся на врага в 30°", arena.act_fwd.distance_to(angled) < 0.05, arena.act_fwd)
	arena.action = ""
	await fresh()
	await aim_at(fwd * 3.0)
	var off: Vector3 = (fwd + side * 1.0).normalized()        # 45°
	e = enemy_at(off * 1.5, 100)
	arena._request("light")
	check("враг дальше 30° не притягивает", arena.act_fwd.distance_to(arena._dir_vector(arena.aim_dir)) < 0.01)
	arena.action = ""
	await fresh()
	await aim_at(fwd * 3.0)
	e = enemy_at(fwd * 6.0, 100)
	arena._request("light")
	check("дальний враг не притягивает", arena.act_fwd.distance_to(arena._dir_vector(arena.aim_dir)) < 0.01)
	arena.action = ""

	# п.2 обрез, удар о землю
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	var a := enemy_at(fwd * 1.5, 100)
	var b := enemy_at(fwd * 3.0, 100)
	var c := enemy_at(fwd * 4.2, 100)
	arena._slam_hits()
	check("вплотную 20", a.hp == 80, a.hp)
	check("средне 12", b.hp == 88, b.hp)
	check("край 8", c.hp == 92, c.hp)
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	c = enemy_at(fwd * 4.2)
	arena._slam_hits()
	Engine.time_scale = 1.0
	check("здоровье 8: убивает даже на краю", not arena.enemies.has(c))

	# п.3 крюк
	await fresh("sickle")
	e = enemy_at(fwd * 6.0, 100)
	await aim_at(fwd * 6.0)
	arena._ult_press()
	await wait(0.03)
	check("прицел: занесённая рука", tex_is(arena.upper, "U_hook_aim"))
	var t0 := Time.get_ticks_msec()
	arena._ult_release()
	check("бросок сразу при отпускании", arena.hook == "fly")
	while arena.hook == "fly":
		await process_frame
	var ms := Time.get_ticks_msec() - t0
	check("долетает быстрее: 6 м меньше 0,3 с", ms < 300, ms)
	check("притягивает", arena.hook == "pull", arena.hook)
	await process_frame
	await process_frame
	check("враг в позе волочения", e.state == "hooked", e.state)
	var d0: float = (e.p - arena.hero_pos).length()
	await wait(0.05)
	var d1: float = (e.p - arena.hero_pos).length()
	await wait(0.05)
	var d2: float = (e.p - arena.hero_pos).length()
	check("притяжение с ускорением", d1 - d2 > d0 - d1, [d0, d1, d2])
	while arena.hook == "pull":
		await process_frame
	check("в конце стан", e.state == "flinch" and e.t < -0.5, [e.state, e.t])
	var ul: Dictionary = arena.meta.upper.sickle_heavy
	arena._request("heavy")
	check("первый удар без замаха", arena.act_frame > 0, arena.act_frame)
	check("и подбросить может", arena.act_launch)
	arena.action = ""
	await fresh("sickle")
	await aim_at(fwd * 7.0)
	arena._ult_press()
	await wait(0.03)
	arena._ult_release()
	var frames := {}
	for i in 6:
		await wait(0.02)
		if arena.hook != "":
			frames[arena.hook_tip.frame] = true
	check("лезвие в полёте вращается", frames.size() >= 3 or arena.hook == "", frames.keys())
	await wait(0.4)
	check("вернулось", arena.hook == "", arena.hook)

	# О1 смена оружия
	await fresh()
	arena._next_module()
	check("модуль сменился сразу", arena.module == "sickle")
	await wait(0.04)
	check("первая половина: прежний модуль", tex_is(arena.upper, "U_switch_blade"))
	await wait(0.14)
	check("вторая половина: новый модуль", tex_is(arena.upper, "U_switch_sickle"))
	await wait(0.15)
	check("анимация кончилась", arena.switch_t < 0.0 and tex_is(arena.upper, "U_idle_sickle"))
	await fresh()
	arena._next_module()
	arena._request("light")
	await wait(0.03)
	check("удар отменяет смену сразу", arena.action != "" and arena.switch_t < 0.0, arena.switch_t)
	arena.action = ""

	# О2 старт и остановка
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await wait(0.05)
	check("разгон: свои кадры", tex_is(arena.legs, "L_run_start"))
	await wait(0.15)
	check("дальше бег", tex_is(arena.legs, "L_run"))
	await wait(0.2)
	var p0: Vector3 = arena.hero_pos
	arena.inp_override = Vector2.ZERO
	await wait(0.05)
	check("остановка: свои кадры", tex_is(arena.legs, "L_run_stop"))
	await wait(0.25)
	var slide: float = arena.hero_pos.distance_to(p0)
	check("проскальзывает и встаёт", slide > 0.15 and slide < 0.7, slide)
	check("потом покой", tex_is(arena.legs, "L_idle"))
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await wait(0.25)
	arena.inp_override = Vector2.ZERO
	await wait(0.03)
	arena.inp_override = Vector2(0, 1)
	await wait(0.05)
	check("ввод прерывает остановку", arena.run_stop_t < 0.0)

	# О3 покой
	await fresh()
	check("покой 6 кадров", int(arena.meta.legs.idle.frames) == 6)
	var seen := {}
	for i in 60:
		await process_frame
		seen[arena.upper.frame] = true
	check("кадры покоя сменяются", seen.size() >= 3, seen.size())

	# О4 прыжок
	await fresh()
	arena._start_jump()
	await wait(0.03)
	check("присед на взлёте", tex_is(arena.legs, "L_land"))
	check("высота растёт без задержки", arena.hero_h > 0.0, arena.hero_h)
	await wait(0.1)
	check("дальше прыжок", tex_is(arena.legs, "L_jump"))
	while arena.airborne:
		await process_frame
	await wait(0.03)
	check("приземление: присед", tex_is(arena.legs, "L_land") and tex_is(arena.upper, "U_land_blade"))
	await wait(0.2)
	check("встал", tex_is(arena.legs, "L_idle"))

	# О9 силуэты
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(0.12)
	check("при рывке есть силуэты", arena.ghosts.size() >= 1, arena.ghosts.size())
	await wait(0.4)
	check("силуэты исчезли", arena.ghosts.is_empty(), arena.ghosts.size())
	var bad := []
	for m in ["blade", "sickle", "shotgun"]:
		if not ResourceLoader.exists(arena._layer("G_dash_" + m)):
			bad.append(m)
	check("листы силуэтов есть", bad.is_empty(), bad)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
