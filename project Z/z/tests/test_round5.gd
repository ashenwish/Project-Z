extends SceneTree
## Проверка правок раунда 5 без окна: godot --headless --path . -s res://tests/test_round5.gd
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
	arena.hero_pos = Vector3.ZERO
	arena.airborne = false
	arena.hero_h = 0.0
	arena.hero_vy = 0.0
	arena.jumps_used = 0
	arena.dash_used = 0
	arena.dash_t = -1.0
	arena.dash_cd = 0.0
	arena.dash_queued = false
	arena.slam = ""
	arena.slam_cd = 0.0
	arena.invuln = false
	arena.pr_i = -1
	arena.ammo = {"shotgun": 6, "pistol": 12}
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
	arena.respawn.clear()
	Engine.time_scale = 1.0
	await wait(0.03)


func enemy_at(p: Vector3, hp := 100) -> Dictionary:
	arena._spawn_enemy(p)
	var e: Dictionary = arena.enemies[-1]
	e.hp = hp
	return e


## Двойной прыжок и удар о землю, ожидание приземления.
func do_slam() -> void:
	arena._start_jump()
	await wait(0.05)
	arena._start_jump()
	await wait(0.05)
	arena._start_slam()
	while arena.slam == "fall":
		await process_frame
	await wait(0.03)


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)

	# п.1 дуга
	await fresh()
	var e := enemy_at(Vector3(5, 0, 0))
	arena._launch(e, 0, Vector3.RIGHT)
	var t0 := Time.get_ticks_msec()
	var top := 0.0
	while arena._is_air_state(e):
		top = maxf(top, e.h)
		await process_frame
	var air := (Time.get_ticks_msec() - t0) / 1000.0
	check("полёт без ударов около 0,75 с", absf(air - 0.75) < 0.12, air)
	check("высота около 1,5 м", absf(top - 1.5) < 0.2, top)
	await fresh()
	e = enemy_at(Vector3(5, 0, 0))
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.3)
	arena._air_hit(e, Vector3.RIGHT)
	check("удар даёт толчок вверх", e.vy > 2.0, e.vy)
	check("состояние реакции", e.state == "air_hit", e.state)

	# п.2 рывок
	await fresh()
	arena.inp_override = Vector2(1, 0)
	var p0: Vector3 = arena.hero_pos
	arena._start_dash()
	arena.inp_override = Vector2.ZERO
	await wait(0.3)
	var dist: float = (arena.hero_pos - p0).length()
	check("рывок на земле около 3,2 м", absf(dist - 3.2) < 0.3, dist)
	await fresh()
	arena._start_jump()
	await wait(0.2)
	arena.inp_override = Vector2(1, 0)
	p0 = arena.hero_pos
	var h0: float = arena.hero_h
	arena._start_dash()
	arena.inp_override = Vector2.ZERO
	check("воздушный рывок начался", arena.dash_t >= 0.0)
	await wait(0.15)
	check("в рывке высота сохраняется", absf(arena.hero_h - h0) < 0.05, [h0, arena.hero_h])
	await wait(0.15)
	dist = (arena.hero_pos - p0).length()
	check("воздушный рывок около 2,6 м", absf(dist - 2.6) < 0.3, dist)
	while arena.airborne:
		await process_frame
	# рывок не прерывает удар
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._request("light")
	arena._start_dash()
	check("рывок не прерывает удар", arena.action == "blade_quick" and arena.dash_t >= 0.0)
	await wait(0.05)
	check("корпус бьёт, ноги в рывке", arena.upper.texture == arena.tex.get(arena._layer("U_blade_quick")) and arena.legs.texture == arena.tex.get(arena._layer("L_dash")))
	await fresh()
	arena.dash_t = 0.01
	arena.dash_speed = 0.0
	arena._request("light")
	check("в рывке можно начать удар", arena.action == "blade_quick", arena.action)
	arena.dash_t = -1.0
	await wait(0.03)
	arena.action = ""

	# п.3 тень падающего тела
	await fresh()
	e = enemy_at(Vector3(4, 0, 0))
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.2)
	arena._kill(e, "decap", Vector3.RIGHT)
	Engine.time_scale = 1.0
	await wait(0.03)
	var b: Dictionary = arena.gore.falling[0]
	check("у падающего тела есть тень", b.shadow.visible)
	var sp: Vector3 = b.shadow.global_position
	check("тень на полу, под телом", sp.y < 0.05 and Vector2(sp.x, sp.z).distance_to(Vector2(b.p.x, b.p.z)) < 0.6, sp)
	var sh = b.shadow
	while arena.gore.falling.size() > 0:
		await process_frame
	await wait(0.03)
	check("тень исчезла с телом", not is_instance_valid(sh))

	# п.4 перезарядка на всех корпусах
	await fresh()
	var src: Array = arena.meta.pistol_reload.src
	for n in ["blade_quick", "blade_heavy", "sickle_quick", "sickle_heavy", "blade_air_quick", "blade_air_heavy",
			"sickle_air_quick", "sickle_air_heavy", "dash", "jump", "slam", "slam_gun", "gun_shoot"]:
		check("перезарядка есть на корпусе %s" % n, src.has(n) and ResourceLoader.exists("res://assets/hero/layers/R_%s.png" % n))
	arena.ammo.pistol = 3
	arena._reload_pistol()
	arena._request("light")
	await wait(0.05)
	check("перезарядка видна во время удара", arena.arm.texture == arena.tex.get(arena._layer("R_blade_quick")))
	arena.action = ""
	await wait(1.4)
	check("перезарядка закончилась", arena.ammo.pistol == 12 and arena.pr_i == -1)

	# п.5 удар о землю: условие
	await fresh()
	arena._start_slam()
	check("с земли нельзя", arena.slam == "")
	arena._start_jump()
	await wait(0.05)
	arena._start_slam()
	check("после одного прыжка нельзя", arena.slam == "")
	arena._start_jump()
	await wait(0.05)
	arena._start_slam()
	check("после двойного можно", arena.slam == "fall" and arena.hero_vy < -10.0, arena.hero_vy)
	check("в падении неуязвим", arena.invuln)
	arena._request("light")
	check("в падении удар не начать", arena.action == "")
	await wait(0.03)
	check("свои ноги и корпус", arena.legs.texture == arena.tex.get(arena._layer("L_slam")) and arena.upper.texture == arena.tex.get(arena._layer("U_slam_blade")))
	while arena.slam == "fall":
		await process_frame
	check("приземление: удар", arena.slam == "impact" and not arena.airborne)
	check("откат 3 с", absf(arena.slam_cd - 3.0) < 0.1, arena.slam_cd)
	check("после удара ещё неуязвим", arena.invuln)
	var pp: Vector3 = arena.hero_pos
	arena.inp_override = Vector2(1, 0)
	await wait(0.1)
	check("на ударе герой стоит", arena.hero_pos.distance_to(pp) < 0.01)
	arena.inp_override = Vector2.ZERO
	await wait(0.5)
	check("удар закончился, уязвим", arena.slam == "" and not arena.invuln)
	arena._start_jump()
	await wait(0.05)
	arena._start_jump()
	await wait(0.05)
	arena._start_slam()
	check("откат не пускает", arena.slam == "")
	while arena.airborne:
		await process_frame

	# клинок: круг 3 м, урон спадает, стан
	await fresh()
	var near := enemy_at(Vector3(0.5, 0, 0))
	var edge := enemy_at(Vector3(0, 0, 2.8))
	var far := enemy_at(Vector3(-3.5, 0, 0))
	await do_slam()
	check("клинок: в центре 3", near.hp == 97, near.hp)
	check("клинок: у края 1", edge.hp == 99, edge.hp)
	check("клинок: дальше 3 м нет", far.hp == 100, far.hp)
	check("стан на земле", near.state == "flinch" and near.t < 0.0, [near.state, near.t])
	var pn: Vector3 = near.p
	await wait(0.3)
	check("в стане стоит", near.state == "flinch" and near.p.distance_to(pn) < 0.05, near.state)
	await wait(0.35)
	check("стан кончился", near.state != "flinch", near.state)

	# серп: 2,3 м
	await fresh("sickle")
	var a := enemy_at(Vector3(0, 0, 2.0))
	var o := enemy_at(Vector3(0, 0, -2.7))
	var c := enemy_at(Vector3(0.3, 0, 0))
	await do_slam()
	check("серп: на 2 м попал", a.hp < 100, a.hp)
	check("серп: на 2,7 м нет", o.hp == 100, o.hp)
	check("серп: в центре 2", c.hp == 98, c.hp)

	# обрез: конус
	await fresh("shotgun")
	var ang: Vector3 = arena._world_dir(Vector2(1, 0))
	arena.mouse_override = arena.cam.unproject_position(ang * 3.0)
	await wait(0.03)
	var front := enemy_at(ang * 1.0)
	var mid := enemy_at(ang * 4.0)
	var side := enemy_at(ang.cross(Vector3.UP) * 2.0)
	var back := enemy_at(-ang * 2.0)
	await do_slam()
	check("обрез: вблизи около 5", front.hp <= 96, front.hp)
	check("обрез: дальше слабее", mid.hp > front.hp and mid.hp < 100, mid.hp)
	check("обрез: сбоку нет", side.hp == 100, side.hp)
	check("обрез: сзади нет", back.hp == 100, back.hp)
	check("обрез: патроны не тратит", arena.ammo.shotgun == 6, arena.ammo.shotgun)

	# висящих сбрасывает
	await fresh()
	e = enemy_at(Vector3(1, 0, 0))
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.2)
	await do_slam()
	check("висящего сбрасывает", not arena._is_air_state(e) or e.vy < 0.0, [e.state, e.vy])
	await wait(0.25)
	check("упавший оглушён", e.h == 0.0 and e.state == "flinch", [e.h, e.state])

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
