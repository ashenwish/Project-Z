extends SceneTree
## Проверка правок раунда 3 без окна: godot --headless --path . -s res://tests/test_round3.gd
## Управляет ареной напрямую (мышь и ввод подменены), сравнивает состояние с ожидаемым. Код выхода 1 — есть ошибки.

var arena
var fails := 0


func check(name: String, ok: bool, info: Variant = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if str(info) == "" else "  [%s]" % str(info)))
	if not ok:
		fails += 1


func wait(t: float) -> void:
	await create_timer(t).timeout


func fresh() -> void:
	arena.action = ""
	arena.act_queued = ""
	arena.combo_t = 0.0
	arena.gun = ""
	arena.inp_override = Vector2.ZERO
	arena.module = "blade"
	arena.hero_pos = Vector3.ZERO
	arena.ammo = {"shotgun": 6, "pistol": 12}
	arena.pr_i = -1
	arena.dash_cd = 0.0
	arena.dash_queued = false
	arena.dash_used = 0
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
	arena.respawn.clear()
	await wait(0.05)


func _initialize() -> void:
	# таймер первым: ошибка загрузки арены не должна вешать прогон
	create_timer(120.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)

	# п.1 бег по умолчанию
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.inp_override = Vector2(1, 0)
	var p0: Vector3 = arena.hero_pos
	await wait(0.5)
	var v: float = (arena.hero_pos - p0).length() / 0.5
	check("бег без Shift: цикл run", arena.loco == "run", arena.loco)
	check("бег без Shift: скорость около 5,2", absf(v - 5.2) < 0.5, v)

	# п.2 ноги и корпус за мышью
	await fresh()
	arena.mouse_override = arena.cam.unproject_position(arena.hero_pos + arena._world_dir(Vector2(1, 0)) * 3.0)
	await wait(0.3)
	arena.inp_override = Vector2(1, 0)
	await wait(0.4)
	var side: Vector2 = arena.cam.unproject_position(arena.hero_pos + arena._world_dir(Vector2(0, 1)) * 3.0)
	arena.mouse_override = side
	await wait(0.2)
	var legs_before: int = arena.legs_dir
	var dirs_seen := {}
	arena.mouse_override = arena.cam.unproject_position(arena.hero_pos - arena._world_dir(Vector2(1, 0)) * 3.0)
	var was: int = arena.upper_dir
	for i in 30:
		await process_frame
		dirs_seen[arena.upper_dir] = true
		arena.mouse_override = arena.cam.unproject_position(arena.hero_pos - arena._world_dir(Vector2(1, 0)) * 3.0)
	await wait(0.4)
	check("прицел за спиной: ноги по ходу (раунд 8)", arena.legs_dir == arena._dir_index(arena._world_dir(Vector2(1, 0))), arena.legs_dir)

	# п.3 наведение на спрайт врага, а не на пол под ним
	await fresh()
	arena._spawn_enemy(Vector3(4, 0, 0))
	var e: Dictionary = arena.enemies[0]
	e.state = "idle"
	var feet: Vector2 = arena.cam.unproject_position(arena._snap(e.p))
	var chest := feet + Vector2(0, -60)
	arena._update_aim()
	arena.mouse_override = chest
	arena._update_aim()
	check("курсор на груди врага: цель найдена", arena.aim_target == e)
	var want: Vector3 = (e.p - arena.hero_pos).normalized()
	check("прицел идёт в точку врага на полу", arena.aim_vec.distance_to(want) < 0.02, arena.aim_vec)
	arena.mouse_override = feet + Vector2(40, -60)
	arena._update_aim()
	check("курсор мимо спрайта: цели нет", arena.aim_target == null)

	# п.5 удар на бегу не останавливает, тяжёлый на 70 %
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.inp_override = Vector2(1, 0)
	await wait(0.1)
	arena._request("light")
	p0 = arena.hero_pos
	await wait(0.2)
	check("лёгкий удар идёт", arena.action == "blade_quick", arena.action)
	v = (arena.hero_pos - p0).length() / 0.2
	check("лёгкий удар на бегу: скорость полная", absf(v - 5.2) < 0.6, v)
	check("лёгкий удар на бегу: ноги в цикле бега", arena.legs.texture == arena.tex.get(arena._layer("L_run")))
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.inp_override = Vector2(1, 0)
	await wait(0.2)                  # разгон закончился (раунд 9)
	arena._request("heavy")
	p0 = arena.hero_pos
	await wait(0.2)
	v = (arena.hero_pos - p0).length() / 0.2
	check("тяжёлый на бегу: около 70 %", absf(v - 5.2 * 0.7) < 0.5, v)

	# п.7 серии
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	var u: Dictionary = arena.meta.upper.blade_quick
	check("клинок: три отрезка", u.chain.size() == 3, u.chain)
	arena._request("light")
	await wait(0.05)
	arena._request("light")
	await wait(0.2)
	check("Л-Л: второй отрезок", arena.action == "blade_quick" and arena.act_frame >= int(u.chain[1]), arena.act_frame)
	arena._request("light")
	await wait(0.2)
	check("Л-Л-Л: третий отрезок", arena.action == "blade_quick" and arena.act_frame >= int(u.chain[2]), arena.act_frame)
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena._request("light")
	await wait(0.05)
	arena._request("heavy")
	await wait(0.32)
	check("Л-Т: тяжёлый завершает", arena.action == "blade_heavy", arena.action)
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena._request("light")
	await wait(0.4)
	check("окно серии открыто после отрезка", arena.action == "" and arena.combo_t > 0.0, arena.combo_t)
	arena._request("light")
	check("нажатие в окне продолжает серию", arena.act_frame >= int(u.chain[1]) and arena.act_frame < int(u.chain[2]), arena.act_frame)
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.module = "sickle"
	var us: Dictionary = arena.meta.upper.sickle_heavy
	check("серп: тяжёлая двойка", us.chain.size() == 2, us.chain)
	arena._request("heavy")
	await wait(0.05)
	arena._request("heavy")
	await wait(0.42)
	check("Т-Т: второй удар серпа", arena.action == "sickle_heavy" and arena.act_frame >= int(us.chain[1]), arena.act_frame)
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.module = "sickle"
	arena._request("light")
	await wait(0.05)
	arena._request("light")
	await wait(0.2)
	check("серп: лёгкая серия осталась", arena.action == "sickle_quick", arena.action)

	# п.4 темп тяжёлой атаки
	var total := 0.0
	for i in int(arena.meta.upper.blade_heavy.chain[1]):
		total += float(arena.meta.upper.blade_heavy.durations_ms[i])
	check("клинок, тяжёлый: около 670 мс (раунд 8)", absf(total - 670.0) < 3.0, total)

	# п.6 патроны и перезарядка
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	for i in 12:
		arena._fire_pistol()
		await wait(0.17)
	check("револьвер: 12 выстрелов и пусто", arena.ammo.pistol == 0, arena.ammo.pistol)
	check("револьвер: перезарядка сама", arena.pr_i >= 0, arena.pr_i)
	arena._fire_pistol()
	check("револьвер: в перезарядке не стреляет", arena.ammo.pistol == 0)
	arena._request("light")
	check("во время перезарядки револьвера бить можно", arena.action == "blade_quick", arena.action)
	await wait(1.35)
	check("револьвер: 12 после 1,2 с", arena.ammo.pistol == 12 and arena.pr_i == -1, arena.ammo.pistol)
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.module = "shotgun"
	for i in 6:
		arena._fire_shotgun()
		await wait(0.6)
	check("обрез: 6 выстрелов и пусто", arena.ammo.shotgun == 0, arena.ammo.shotgun)
	await wait(0.2)
	check("обрез: перезарядка сама", arena.gun == "reload", arena.gun)
	arena._fire_shotgun()
	check("обрез: в перезарядке не стреляет", arena.gun == "reload" and arena.ammo.shotgun == 0)
	await wait(2.2)
	check("обрез: 8 после 2 с (раунд 7)", arena.ammo.shotgun == 8, arena.ammo.shotgun)
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.module = "shotgun"
	arena.ammo.shotgun = 3
	arena.inp_override = Vector2(1, 0)
	arena._reload()
	await wait(0.1)
	check("R обреза на бегу: свой корпус", arena.upper.texture == arena.tex.get(arena._layer("U_gun_reload_run")))
	arena.module = "blade"
	arena.gun = ""
	await wait(0.05)
	check("смена модуля прерывает: патроны те же", arena.ammo.shotgun == 3, arena.ammo.shotgun)

	# п.8 рывок и прыжок
	await fresh()
	arena.mouse_override = Vector2(480, 500)
	arena.inp_override = Vector2(1, 0)
	p0 = arena.hero_pos
	arena._request("light")
	arena._start_dash()
	check("рывок не прерывает удар (раунд 5)", arena.action == "blade_quick" and arena.dash_t >= 0.0, arena.action)
	check("в рывке неуязвим", arena.invuln)
	await wait(0.03)
	check("в рывке свои ноги", arena.legs.texture == arena.tex.get(arena._layer("L_dash")))
	arena.inp_override = Vector2.ZERO
	await wait(0.3)
	var dist: float = (arena.hero_pos - p0).length()
	check("рывок около 3,2 м", absf(dist - 3.2) < 0.35, dist)
	check("после рывка уязвим", not arena.invuln)
	await fresh()
	arena.dash_t = -1.0
	arena.mouse_override = Vector2(480, 500)
	arena._start_jump()
	await wait(0.31)
	check("прыжок: высота около 0,9 м", absf(arena.hero_h - 0.9) < 0.15, arena.hero_h)
	arena.hero_vy = minf(arena.hero_vy, 0.0)
	check("прыжок: тень видна", arena.shadow.visible)
	check("прыжок: свои ноги", arena.legs.texture == arena.tex.get(arena._layer("L_jump")))
	arena._request("light")
	check("в прыжке можно бить: воздушный удар", arena.action == "blade_air_quick", arena.action)
	await wait(0.03)
	check("в прыжке корпус удара, ноги прыжка", arena.upper.texture == arena.tex.get(arena._layer("U_blade_air_quick")) and arena.legs.texture == arena.tex.get(arena._layer("L_jump")))
	await wait(1.6)
	check("приземление", not arena.airborne and arena.hero_h == 0.0, arena.hero_h)
	check("тень скрыта", not arena.shadow.visible)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
