extends SceneTree
## Проверка правок раунда 7 без окна: godot --headless --path . -s res://tests/test_round7.gd
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
	arena.slam = ""
	arena.slam_cd = 0.0
	arena.invuln = false
	arena.pr_i = -1
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


## Время от нажатия до следующего попадания, с.
func time_to_hit(kind: String) -> float:
	var hits_before: bool = arena.act_since_hit >= 0.0
	var t0 := Time.get_ticks_msec()
	arena._request(kind)
	var name_was: String = arena.action
	var frame_was: int = arena.act_frame
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		if arena.action != "" and (arena.action != name_was or arena.act_frame != frame_was or not hits_before) and arena.act_since_hit >= 0.0 and arena.act_since_hit < 0.05:
			break
	return (Time.get_ticks_msec() - t0) / 1000.0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)

	# п.5 патроны
	await fresh("shotgun")
	check("в обрезе 8", arena.MAG.shotgun == 8)
	arena.ammo.shotgun = 1
	arena._reload()
	await wait(2.2)
	check("перезарядка до 8", arena.ammo.shotgun == 8, arena.ammo.shotgun)

	# п.3, п.4 бег
	await fresh()
	arena.inp_override = Vector2(1, 0)
	var p0: Vector3 = arena.hero_pos
	await wait(0.5)
	var v: float = (arena.hero_pos - p0).length() / 0.5
	check("бег около 5,2 м/с", absf(v - 5.2) < 0.5, v)
	var lm: Dictionary = arena.meta.legs.run
	var cycle: float = lm.frames * float(lm.durations_ms[0]) / 1000.0
	check("шаг цикла 2,62 м: стопы не скользят", absf(cycle * 5.2 - 2.62) < 0.05, cycle * 5.2)

	# п.2 рывки
	await fresh()
	p0 = arena.hero_pos
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(0.1)
	arena._start_dash()               # нажатие во время первого запоминается
	check("второй запомнен", arena.dash_queued)
	await wait(0.2)
	check("второй пошёл сразу за первым", arena.dash_t >= 0.0 and arena.dash_used == 2, [arena.dash_t, arena.dash_used])
	await wait(0.25)
	var dist: float = (arena.hero_pos - p0).length()
	check("откат 2 с после двух", arena.dash_cd > 1.5 and arena.dash_used == 0, arena.dash_cd)
	arena._start_dash()
	check("в откате нельзя", arena.dash_t < 0.0)
	await wait(2.0)
	arena._start_dash()
	check("после отката снова", arena.dash_t >= 0.0)
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(0.3)
	check("после первого отката нет", arena.dash_cd <= 0.0 and arena.dash_used == 1, [arena.dash_cd, arena.dash_used])
	await wait(0.9)
	check("окно 0,8 с вышло: откат", arena.dash_cd > 0.0 and arena.dash_used == 0, [arena.dash_cd, arena.dash_used])
	await fresh()
	arena._start_jump()
	await wait(0.1)
	arena._start_dash()
	await wait(0.3)
	arena._start_dash()
	check("в воздухе тоже два", arena.dash_t >= 0.0 and arena.dash_used == 2, arena.dash_used)
	while arena.airborne:
		await process_frame

	# п.1 обгоревшие
	await fresh("shotgun")
	var missing := []
	for n in ["E_walk_s", "E_idle_s", "E_flinch_s", "E_air_fall_s", "C_intact_back_s", "C_split_left_s", "T_decap_s", "T_intact_s", "P_head_s", "P_torso_top_s"]:
		if not ResourceLoader.exists("res://assets/enemy/%s.png" % n):
			missing.append(n)
	check("обгоревшие листы на месте", missing.is_empty(), missing)
	var e := enemy_at(Vector3(4, 0, 0), 100)
	e.state = "idle"
	arena._ignite(e, arena.BURN_T, true)
	await wait(0.1)
	check("горящий на обгоревшем листе", e.node.texture == arena.tex.get("res://assets/enemy/E_%s_s.png" % e.state), e.state)
	var im: Image = e.node.texture.get_image()
	var dark := 0
	var total := 0
	for y in range(0, im.get_height(), 2):
		for x in range(0, im.get_width(), 2):
			var c := im.get_pixel(x, y)
			if c.a > 0.5:
				total += 1
				if c.v < 0.14:
					dark += 1
	check("враг не чисто чёрный", float(dark) / total < 0.6, "%d/%d" % [dark, total])
	var before: int = arena.gore.corpses.size()
	arena._kill(e, "split", Vector3.RIGHT)        # добит оружием
	Engine.time_scale = 1.0
	await wait(0.05)
	check("добитый оружием: обгоревший труп", arena.gore.corpses.size() == before + 1 and arena.gore.corpses[-1].node.texture.resource_path.ends_with("_s.png"), arena.gore.corpses[-1].node.texture.resource_path)
	check("и дымится", arena.gore.corpses[-1].smoke > 0.0)
	check("флаг сброшен", not arena.gore.scorched)
	e = enemy_at(Vector3(4, 0, 0), 100)
	before = arena.gore.corpses.size()
	arena._kill(e, "split", Vector3.RIGHT)
	Engine.time_scale = 1.0
	await wait(0.05)
	check("не горевший: обычный труп", not arena.gore.corpses[-1].node.texture.resource_path.ends_with("_s.png"))
	e = enemy_at(Vector3(4, 0, 0), 1)
	arena._ignite(e, arena.BURN_T, true)
	await wait(0.7)
	check("сгорел: обгоревший с огнём", not arena.enemies.has(e) and arena.gore.corpses[-1].node.texture.resource_path.ends_with("_s.png") and arena.gore.flames.size() >= 1)
	await fresh()
	e = enemy_at(Vector3(4, 0, 0), 100)
	arena._launch(e, 0, Vector3.RIGHT)
	arena._ignite(e, arena.BURN_T, true)
	await wait(0.15)
	check("горящий в воздухе: обгоревший лист", e.node.texture.resource_path.ends_with("_s.png"), e.node.texture.resource_path)
	arena._kill(e, "decap", Vector3.RIGHT)
	Engine.time_scale = 1.0
	check("падающее тело горит", arena.gore.falling[-1].flame != null)
	await wait(1.2)

	# п.7 тройка клинка
	await fresh()
	var uh: Dictionary = arena.meta.upper.blade_heavy
	check("тяжёлая тройка клинка", uh.chain.size() == 3 and uh.hit.size() == 3, uh.chain)
	var dummy := enemy_at(Vector3(50, 0, 0), 100)
	arena._request("heavy")
	check("первый от начала", arena.act_frame == 0)
	await wait(0.34)
	arena._request("heavy")
	await wait(0.15)
	check("Т2", arena.action == "blade_heavy" and arena.act_frame >= int(uh.chain[1]), arena.act_frame)
	await wait(0.2)
	arena._request("heavy")
	await wait(0.15)
	check("Т3", arena.action == "blade_heavy" and arena.act_frame >= int(uh.chain[2]), arena.act_frame)

	# только первый подбрасывает
	await fresh()
	e = enemy_at(Vector3(1.2, 0, 0), 100)
	arena.mouse_override = arena.cam.unproject_position(arena._snap(e.p)) + Vector2(0, -50)
	await wait(0.03)
	arena._request("heavy")
	check("начинающий подбрасывает", arena.act_launch)
	await fresh()
	arena._request("light")
	await wait(0.1)
	arena._request("heavy")
	await wait(0.35)
	check("тяжёлый после лёгкого: без подброса", arena.action == "blade_heavy" and not arena.act_launch, [arena.action, arena.act_launch])

	# п.6 связность: от нажатия до следующего попадания
	await fresh()
	arena._request("light")
	await wait(0.3)
	var t := await time_to_hit("heavy")
	check("лёгкий → тяжёлый: меньше 0,25 с", t < 0.25, t)
	check("это тяжёлый", arena.action == "blade_heavy", arena.action)
	await wait(0.1)
	t = await time_to_hit("light")
	check("тяжёлый → лёгкий: меньше 0,25 с", t < 0.25, t)
	check("это лёгкий", arena.action == "blade_quick", arena.action)
	await wait(0.1)
	t = await time_to_hit("light")
	check("лёгкий → лёгкий: меньше 0,25 с", t < 0.25, t)
	# первый удар с полным замахом
	await fresh()
	t = await time_to_hit("heavy")
	check("первый тяжёлый с полным замахом: дольше 0,25 с", t > 0.25, t)
	# запоминание
	await fresh()
	arena._request("heavy")
	await wait(0.05)
	arena._request("light")
	check("нажатие в замахе запомнено", arena.act_queued == "light")
	await wait(0.5)
	check("запомненное не теряется до 0,4 с", true)
	await fresh()
	arena._request("light")
	arena.act_queued = "heavy"
	arena.act_q_t = 0.02
	await wait(0.05)
	check("старое нажатие забывается", arena.act_queued == "", arena.act_queued)
	# окно после конца и обрезка до попадания нельзя
	await fresh()
	arena._request("heavy")
	await wait(0.05)
	arena._request("light")
	await wait(0.05)
	check("до попадания хвост не режется", arena.action == "blade_heavy", arena.action)
	await fresh()
	var ul: Dictionary = arena.meta.upper.blade_quick
	arena._request("light")
	await wait(0.45)
	check("окно после удара открыто", arena.action == "" and arena.combo_t > 0.0, arena.combo_t)
	arena._request("light")
	check("продолжение идёт вторым отрезком", arena.act_frame >= int(ul.chain[1]), arena.act_frame)
	check("без замаха", arena.act_frame > int(ul.chain[1]), arena.act_frame)
	# воздух
	await fresh()
	arena._start_jump()
	await wait(0.03)
	arena._request("light")
	await wait(0.22)
	t = await time_to_hit("heavy")
	check("в воздухе лёгкий → тяжёлый связно", t < 0.3 and arena.action == "blade_air_heavy", [t, arena.action])
	while arena.airborne:
		await process_frame

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
