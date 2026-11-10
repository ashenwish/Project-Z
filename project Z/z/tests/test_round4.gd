extends SceneTree
## Проверка правок раунда 4 без окна: godot --headless --path . -s res://tests/test_round4.gd
## Код выхода 1 — есть ошибки.

var arena
var fails := 0


func check(name: String, ok: bool, info: Variant = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if str(info) == "" else "  [%s]" % str(info)))
	if not ok:
		fails += 1


func wait(t: float) -> void:
	await create_timer(t).timeout


## Чистая сцена и один враг перед героем.
func fresh(with_enemy := true, mod := "blade") -> Variant:
	arena.action = ""
	arena.act_queued = ""
	arena.act_finisher = false
	arena.combo_t = 0.0
	arena.gun = ""
	arena.inp_override = Vector2.ZERO
	arena.mouse_override = Vector2(480, 500)
	arena.module = mod
	arena.hero_pos = Vector3.ZERO
	arena.airborne = false
	arena.hero_h = 0.0
	arena.hero_vy = 0.0
	arena.jumps_used = 0
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
	arena.respawn.clear()
	Engine.time_scale = 1.0
	await wait(0.03)
	if not with_enemy:
		return null
	arena._spawn_enemy(Vector3(1.2, 0, 0))
	var en: Dictionary = arena.enemies[0]
	# прицел точно на враге
	arena.mouse_override = arena.cam.unproject_position(arena._snap(en.p)) + Vector2(0, -50)
	await wait(0.03)
	return en


## Прогон до кадра попадания без хит-стопа и времени.
func strike(n: String, from := 0) -> void:
	arena._start_action(n, from)
	while arena.action == n and not (arena.pending.has("melee")):
		await process_frame
	await wait(0.03)


func _initialize() -> void:
	# таймер первым: ошибка загрузки арены не должна вешать прогон
	create_timer(120.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)

	# п.4 бег
	await fresh(false)
	arena.inp_override = Vector2(1, 0)
	await wait(0.2)                  # разгон закончился (раунд 9)
	var p0: Vector3 = arena.hero_pos
	await wait(0.5)
	var v: float = (arena.hero_pos - p0).length() / 0.5
	check("бег около 5,2 м/с", absf(v - 5.2) < 0.4, v)
	var fps: float = 1000.0 / float(arena.meta.legs.run.durations_ms[0])
	check("цикл бега ускорен", absf(fps - 15.87) < 0.5, fps)

	# п.1 двойной прыжок
	await fresh(false)
	arena._start_jump()
	await wait(0.31)
	check("первый прыжок: около 0,9 м", absf(arena.hero_h - 0.9) < 0.15, arena.hero_h)
	arena._start_jump()
	check("второй прыжок: снова толчок", arena.hero_vy > 5.0, arena.hero_vy)
	await wait(0.31)
	check("вместе около 1,6–1,8 м", arena.hero_h > 1.4 and arena.hero_h < 1.95, arena.hero_h)
	arena._start_jump()
	check("третьего прыжка нет", arena.jumps_used == 2 and arena.hero_vy < 1.0, arena.hero_vy)
	await wait(0.9)
	check("приземлился", not arena.airborne and arena.hero_h == 0.0, arena.hero_h)
	arena._start_jump()
	check("после земли прыжки снова есть", arena.airborne and arena.jumps_used == 1)
	await wait(0.7)

	# п.2 подброс первым тяжёлым
	var e: Variant = await fresh()
	await strike("blade_heavy")
	check("клинок: тяжёлый подбрасывает выжившего", arena.enemies.has(e) and arena._is_air_state(e), e.state)
	check("тяжёлый нанёс полный урон (раунд 6)", e.hp == 8 - 5, e.hp)
	e = await fresh()
	arena._launch(e, 0, Vector3.RIGHT)
	var pos: Vector3 = e.p
	var top := 0.0
	var shadow_seen := false
	while arena._is_air_state(e):
		top = maxf(top, e.h)
		shadow_seen = shadow_seen or e.shadow.visible
		await process_frame
	check("враг взлетает примерно на 1,5 м", absf(top - 1.5) < 0.2, top)
	check("у врага тень", shadow_seen)
	check("в воздухе беспомощен: не идёт", e.p.distance_to(pos) < 0.001)
	check("упал на пол живым", e.h == 0.0 and not arena._is_air_state(e) and arena.enemies.has(e), e.state)

	e = await fresh(true, "sickle")
	await strike("sickle_heavy")
	check("серп: первый тяжёлый подбрасывает", arena._is_air_state(e), e.state)

	# только ПЕРВЫЙ тяжёлый: завершающий лёгкую серию и второй удар серии не подбрасывают
	e = await fresh()
	arena.act_finisher = true
	await strike("blade_heavy")
	check("тяжёлый после лёгких не подбрасывает", not arena.enemies.has(e) or not arena._is_air_state(e))
	e = await fresh(true, "sickle")
	var chain2: int = int(arena.meta.upper.sickle_heavy.chain[1])
	await strike("sickle_heavy", chain2)
	check("второй тяжёлый серпа не подбрасывает", not arena._is_air_state(e), e.state)
	e = await fresh(true, "sickle")
	await strike("sickle_quick")
	check("лёгкий не подбрасывает", not arena._is_air_state(e), e.state)

	# выбор удара и дальность по высоте
	e = await fresh()
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.25)
	var hp0: int = e.hp
	arena.action = "blade_quick"
	arena.act_end = 6
	arena.act_fwd = Vector3.RIGHT
	arena._melee_hits()
	arena.action = ""
	check("с земли до летящего высоко не достать", e.hp == hp0 and e.hits == 0, [e.h, e.hp, e.hits])
	arena._start_jump()
	await wait(0.03)
	arena._request("light")
	check("в воздухе лёгкий — воздушный", arena.action == "blade_air_quick", arena.action)
	arena.action = ""
	arena._request("heavy")
	check("в воздухе тяжёлый — воздушный", arena.action == "blade_air_heavy", arena.action)
	arena.action = ""

	# п.3 толчки по врагу в воздухе
	e = await fresh()
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.25)
	arena.airborne = true
	arena.hero_h = e.h
	arena.hero_vy = 0.0
	hp0 = e.hp
	arena.action = "blade_air_quick"
	arena.act_end = 6
	arena.act_fwd = Vector3.RIGHT
	arena._melee_hits()
	arena.action = ""
	check("воздушный удар попал", e.hp == hp0 - 1 and e.hits == 1, [e.hp, e.hits])
	check("удар дал толчок вверх", e.vy > 1.0, e.vy)
	check("удар подхватил героя", arena.hero_vy >= arena.AIR_HIT_VY - 0.01, arena.hero_vy)
	e.hp = 100
	for i in 7:
		arena.action = "blade_air_quick"
		arena.hero_h = e.h
		arena._melee_hits()
	arena.action = ""
	check("после 8 ударов падает", e.state == "air_fall" and e.hits >= 8 and e.vy <= 0.0, [e.state, e.hits, e.vy])
	# серия в воздухе
	e = await fresh(false)
	arena._start_jump()
	await wait(0.05)
	var ua: Dictionary = arena.meta.upper.blade_air_quick
	check("клинок: воздушная тройка", ua.chain.size() == 3, ua.chain)
	check("серп: воздушная тройка", arena.meta.upper.sickle_air_quick.chain.size() == 3)
	check("серп: воздушная тяжёлая двойка", arena.meta.upper.sickle_air_heavy.chain.size() == 2)
	arena._request("light")
	await wait(0.05)
	arena._request("light")
	await wait(0.2)
	check("Л-Л в воздухе", arena.action == "blade_air_quick" and arena.act_frame >= int(ua.chain[1]), arena.act_frame)
	var vy_slow: float = arena.hero_vy
	await wait(0.05)
	check("в воздушном ударе падает медленнее", absf(arena.hero_vy - vy_slow) < arena.HERO_G * 0.05 * 0.6, [vy_slow, arena.hero_vy])
	await wait(2.0)
	check("приземление прервало воздушный удар", not arena.airborne and not arena._is_air_action())

	# удар вниз
	e = await fresh()
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.25)
	arena.airborne = true
	arena.hero_h = e.h
	e.hp = 20
	arena.action = "blade_air_heavy"
	arena.act_frame = 4
	arena.act_end = int(arena.meta.upper.blade_air_heavy.frames)
	arena.act_fwd = Vector3.RIGHT
	arena._melee_hits()
	arena.action = ""
	check("удар вниз сбрасывает", e.state == "air_fall" and e.vy < -10.0, [e.state, e.vy])
	await wait(0.3)
	check("урон о пол", e.h == 0.0 and e.hp == 20 - 3 - arena.SPIKE_DMG, [e.h, e.hp])

	# п.5 (вопрос Д) смерть в воздухе
	for outcome in ["decap", "arm_off_r", "split", "gut", "blast", "intact"]:
		e = await fresh()
		arena._launch(e, 0, Vector3.RIGHT)
		await wait(0.2)
		var corpses0: int = arena.gore.corpses.size()
		arena._kill(e, outcome, Vector3.RIGHT)
		Engine.time_scale = 1.0
		check("смерть в воздухе: %s, тело летит" % outcome, arena.gore.falling.size() >= 1 and not arena.enemies.has(e))
		check("  сразу трупа нет", arena.gore.corpses.size() == corpses0)
		await wait(1.5)
		check("  долетело и стало трупом", arena.gore.corpses.size() == corpses0 + 1 and arena.gore.falling.size() == 0, arena.gore.corpses.size())

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
