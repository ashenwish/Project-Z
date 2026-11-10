extends SceneTree
## Проверка правок раунда 10 без окна: godot --headless --path . -s res://tests/test_round10.gd
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
	arena.pistol = 0
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
	arena.dash_cd = 0.0
	arena.dash_used = 0
	arena.hook = ""
	arena.hook_cd = 0.0
	arena.ult_t = -1.0
	arena.spin_cd = 0.0
	arena.invuln = false
	arena.aim_free = 0.0
	arena.ammo = {"shotgun": 8, "pistol": 12}
	arena._hide_chain()
	arena.gore.pellets.clear()
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


func off_legs() -> float:
	return absf(wrapf(arena.upper_ang - arena.legs_tgt, -180.0, 180.0))


## Бег по fwd с курсором в точке p (держим курсор за героем каждый кадр).
func run_aiming(fwd: Vector3, p_rel: Vector3, frames: int) -> void:
	arena.inp_override = Vector2(1, 0)
	for i in frames:
		arena.mouse_override = arena.cam.unproject_position(arena._snap(arena.hero_pos + p_rel))
		await process_frame


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var fwd: Vector3 = arena._world_dir(Vector2(1, 0))
	var side: Vector3 = fwd.cross(Vector3.UP)

	# п.1 бег: корпус не дальше 45°, стопы под бёдрами
	await fresh()
	await run_aiming(fwd, -fwd * 3.0, 40)
	check("курсор позади: корпус не дальше 45° от ног", off_legs() <= 47.0, off_legs())
	check("ноги по ходу", arena.legs_dir == arena._dir_index(fwd), arena.legs_dir)
	var img: Image = load("res://assets/hero/layers/L_run.png").get_image()
	var fw: int = img.get_width() / 8
	var fh: int = img.get_height() / 8
	# вид спереди (строка s): ширина ног у стоп в кадре опоры больше прежних 6 px
	var widest := 0
	for f in 8:
		var y: int = fh - 6
		var xs := []
		for x in fw:
			if img.get_pixel(f * fw + x, y).a > 0.5:
				xs.append(x)
		if xs.size() > 0:
			widest = maxi(widest, xs.max() - xs.min())
	check("стопы разведены: ширина ног внизу ≥ 9 px", widest >= 9, widest)

	# п.4 револьвер на бегу назад: не дальше 80°, корпус не разворачивается
	await fresh()
	var behind := enemy_at(-fwd * 4.0)
	await run_aiming(fwd, -fwd * 4.0, 20)
	arena._fire_pistol()
	var worst := 0.0
	for i in 12:
		arena.mouse_override = arena.cam.unproject_position(arena._snap(arena.hero_pos - fwd * 4.0))
		await process_frame
		worst = maxf(worst, off_legs())
	check("выстрел назад на бегу: корпус не дальше 45° (раунд 11)", worst <= 47.0, worst)
	check("выстрел назад на бегу: рука наведена (раунд 11)", arena.pistol_aim_t > 0.0 or arena.parm_col >= 0)
	check("враг точно позади задет: выстрел по мыши (раунд 11)", behind.hp == 99, behind.hp)
	var sv: Vector3 = arena._shot_vec()
	check("пуля прямо в мышь (раунд 11)", sv.is_equal_approx(arena.aim_vec), rad_to_deg(sv.angle_to(fwd)))
	await fresh()
	await aim_at(-fwd * 4.0)
	var stand := enemy_at(-fwd * 4.0)
	await aim_at(-fwd * 4.0)
	arena._fire_pistol()
	await wait(0.05)
	check("стоя стреляет прямо назад", stand.hp == 99, stand.hp)
	# обрез на бегу назад
	await fresh("shotgun")
	var b2 := enemy_at(-fwd * 2.0)
	await run_aiming(fwd, -fwd * 4.0, 20)
	arena._shotgun_hits()
	check("обрез на бегу назад попадает (раунд 11)", b2.hp < 100, b2.hp)
	var sv2: Vector3 = arena._shot_vec()
	check("обрез на бегу в мышь (раунд 11)", sv2.is_equal_approx(arena.aim_vec))

	# п.3 обрез: конус 40°, 8 м, 12/8/4, дробь, толчок
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	var wide := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(22.0)) * 3.0)
	var out := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(-45.0)) * 3.0)
	var far := enemy_at(fwd * 7.5)
	var p_wide: Vector3 = wide.p
	arena._shotgun_hits()
	check("в 22° попадает (конус 28°, раунд 11)", wide.hp == 92, wide.hp)
	check("в 45° мимо", out.hp == 100, out.hp)
	check("на 7,5 м 4 урона", far.hp == 96, far.hp)
	check("дробь отталкивает", (wide.p - arena.hero_pos).length() > (p_wide - arena.hero_pos).length() + 0.2)
	check("дроби нет (раунд 12)", arena.gore.pellets.is_empty(), arena.gore.pellets.size())
	await wait(0.25)
	check("дробины погасли", arena.gore.pellets.is_empty(), arena.gore.pellets.size())
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	var w2 := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(35.0)) * 3.0)
	arena._shotgun_hits(true)
	check("залп: в 35° попадает (конус 40°, раунд 11)", w2.hp < 100, w2.hp)
	check("залп: дроби нет (раунд 12)", arena.gore.pellets.is_empty())

	# п.5 ассист крюка
	await fresh("sickle")
	var tgt := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(10.0)) * 6.0)
	await aim_at(fwd * 6.0)
	arena._ult_press()
	await wait(0.03)
	check("ассист: пунктир доворачивает на цель", rad_to_deg(arena._hook_aim().angle_to(fwd)) > 8.0)
	arena._ult_release()
	while arena.hook == "fly":
		await process_frame
	check("ассист: крюк в 10° от курсора зацепил", arena.hook == "pull" and arena.hook_target == tgt, arena.hook)
	while arena.hook != "":
		await process_frame
	await fresh("sickle")
	var miss := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(20.0)) * 6.0)
	await aim_at(fwd * 6.0)
	arena._ult_press()
	await wait(0.03)
	arena._ult_release()
	while arena.hook == "fly":
		await process_frame
	check("в 20° ассиста нет", arena.hook == "back" and miss.hp == 100, [arena.hook, miss.hp])
	while arena.hook != "":
		await process_frame
	await fresh("sickle")
	var on_line := enemy_at(fwd * 4.0)
	var near_side := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(8.0)) * 3.0)
	await aim_at(fwd * 6.0)
	check("враг на линии: без доворота", arena._hook_aim().is_equal_approx(arena.aim_vec))

	# п.6 ульта клинка
	await fresh()
	var t0 := Time.get_ticks_msec()
	arena._ult_press()
	while arena.ult_t >= 0.0:
		await process_frame
	var dur := (Time.get_ticks_msec() - t0) / 1000.0
	check("ульта 1,5 с", absf(dur - 1.5) < 0.1, dur)
	check("4 оборота: шаг направления около 0,041 с", absf(arena.SPIN_DIR_T - 0.04125) < 0.002, arena.SPIN_DIR_T)

	# п.2 серп: больше кадров, шаг кисти ровный, попадания в своих отрезках
	for n in ["sickle_quick", "sickle_heavy"]:
		var u: Dictionary = arena.meta.upper[n]
		var ok_hits := true
		for i in u.chain.size():
			var a: int = int(u.chain[i])
			var b: int = int(u.chain[i + 1]) if i + 1 < u.chain.size() else int(u.frames)
			ok_hits = ok_hits and int(u.hit[i]) > a and int(u.hit[i]) < b
		check("%s: попадание внутри отрезка, после замаха" % n, ok_hits, [u.chain, u.hit])
		var mx := 0.0
		var tips: Array = u.anchors.se
		for f in range(1, int(u.frames)):
			if not (f in u.chain):
				mx = maxf(mx, Vector2(tips[f].sickle_tip[0], tips[f].sickle_tip[1]).distance_to(Vector2(tips[f - 1].sickle_tip[0], tips[f - 1].sickle_tip[1])))
		check("%s: острие за кадр не дальше 50 px (было 60-77)" % n, mx <= 50.0, mx)
	check("лёгкая серия серпа стала плотнее", int(arena.meta.upper.sickle_quick.frames) >= 20, arena.meta.upper.sickle_quick.frames)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
