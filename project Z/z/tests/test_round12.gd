extends SceneTree
## Проверка правок раунда 12 без окна: godot --headless --path . -s res://tests/test_round12.gd
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
	arena.act_turn = false
	arena.combo_t = 0.0
	arena.gun = ""
	arena.gun_queued = ""
	arena.pistol = 0
	arena.pistol_aim_t = 0.0
	arena.pr_i = -1
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
	arena.dash_used = 0
	arena.hook = ""
	arena.ult_t = -1.0
	arena.invuln = false
	arena.aim_free = 0.0
	arena.switch_t = -1.0
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


func enemy_at(p: Vector3, hp := 100) -> Dictionary:
	arena._spawn_enemy(p)
	var e: Dictionary = arena.enemies[-1]
	e.hp = hp
	return e


func aim_at(p: Vector3) -> void:
	arena.mouse_override = arena.cam.unproject_position(arena._snap(p))
	await wait(0.03)


func hold_mouse(p_rel: Vector3, frames: int) -> void:
	for i in frames:
		arena.mouse_override = arena.cam.unproject_position(arena._snap(arena.hero_pos + p_rel))
		await process_frame


func upper_name() -> String:
	return arena.upper.texture.resource_path.get_file().get_basename()


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var fwd: Vector3 = arena._world_dir(Vector2(1, 0))
	var side: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(90.0))

	# п.1 стоя: шаг-разворот, удар после него
	await fresh()
	await aim_at(fwd * 3.0)
	await wait(0.3)
	var back := enemy_at(-fwd * 1.3)
	await aim_at(-fwd * 3.0)
	var t0 := Time.get_ticks_msec()
	arena._request("light")
	check("стоя удар назад: сначала разворот", arena.act_turn)
	var legs0: int = arena.legs_dir
	await wait(0.05)
	check("в развороте удара ещё нет", back.hp == 100, back.hp)
	var legs_seen := {legs0: true}
	while arena.act_turn and Time.get_ticks_msec() - t0 < 500:
		await process_frame
		legs_seen[arena.legs_dir] = true
	legs_seen[arena.legs_dir] = true
	check("ноги поворачиваются вместе с корпусом", legs_seen.size() >= 2, legs_seen.keys())
	var turn_ms := Time.get_ticks_msec() - t0
	check("разворот 180° около 0,12 с", turn_ms >= 90 and turn_ms <= 200, turn_ms)
	await wait(0.4)
	check("после разворота удар попал", back.hp < 100 or not arena.enemies.has(back), back.hp)
	await fresh()
	await aim_at(fwd * 3.0)
	await wait(0.3)
	arena._request("light")
	check("удар вперёд без разворота", not arena.act_turn)
	arena.action = ""

	# п.1 на бегу: удар не дальше 90° от хода
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await hold_mouse(-fwd * 3.0, 10)
	await wait(0.3)
	await hold_mouse(-fwd * 3.0, 2)
	var s_en := enemy_at(arena.hero_pos + side * 1.2)
	var s_en2 := enemy_at(arena.hero_pos - side * 1.2)
	arena._request("light")
	check("на бегу удар назад — в сторону, без задержки", not arena.act_turn and absf(absf(wrapf(arena.act_dir * 45.0 - arena._screen_ang(fwd), -180.0, 180.0)) - 90.0) < 1.0, arena.act_dir)
	await hold_mouse(-fwd * 3.0, 20)
	check("задет враг сбоку", s_en.hp < 100 or s_en2.hp < 100 or not arena.enemies.has(s_en) or not arena.enemies.has(s_en2), [s_en.hp, s_en2.hp])
	check("ноги по ходу", arena.legs_dir == arena._dir_index(fwd), arena.legs_dir)

	# п.2 голова к наведённой руке
	await fresh("shotgun")
	arena._fire_shotgun()
	await wait(0.3)
	await aim_at(fwd * 3.0)
	await wait(0.2)
	check("рука прямо — голова прямо", not upper_name().contains("_h"), upper_name())
	arena.inp_override = Vector2(1, 0)
	await hold_mouse(-fwd * 3.0, 40)
	check("обрез назад на бегу — голова повёрнута сильнее (12°)", upper_name().ends_with("2"), upper_name())
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await hold_mouse(side * 3.0, 30)
	arena._fire_pistol()
	await hold_mouse(side * 3.0, 3)
	check("пистолет вбок на бегу — голова повёрнута", upper_name().contains("_h"), upper_name())
	var missing := []
	for n in ["U_idle_blade_hr1", "U_run_sickle_hl2", "U_gun_aim_run_noarm_hr2", "U_gun_shoot2_noarm_hl1"]:
		if not ResourceLoader.exists(arena._layer(n)):
			missing.append(n)
	check("листы с повёрнутой головой на месте", missing.is_empty(), missing)

	# п.3 гильзы у ног, дым вместо дроби
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	var shells0: int = 0
	for d in arena.gore.debris:
		if d.kind == "shell":
			shells0 += 1
	var shots0: int = arena.gore.oneshots.size()
	arena._fire_shotgun()
	await wait(0.25)
	var smoke := 0
	for o in arena.gore.oneshots:
		if o.node.texture.resource_path.ends_with("smoke.png"):
			smoke += 1
	check("перед дулом пороховой дым", smoke >= 3, smoke)
	check("дроби нет", arena.gore.pellets.is_empty())
	await wait(1.0)
	var far := 0.0
	var n_sh := 0
	for d in arena.gore.debris:
		if d.kind == "shell":
			n_sh += 1
			far = maxf(far, Vector2(d.p.x - arena.hero_pos.x, d.p.z - arena.hero_pos.z).length())
	check("гильза вылетела", n_sh > shells0, n_sh)
	check("гильзы лежат у ног (до 0,8 м)", far <= 0.8, far)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
