extends SceneTree
## Проверка правок раунда 11 без окна: godot --headless --path . -s res://tests/test_round11.gd
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
	arena.dash_cd = 0.0
	arena.dash_used = 0
	arena.hook = ""
	arena.ult_t = -1.0
	arena.invuln = false
	arena.aim_free = 0.0
	arena.switch_t = -1.0
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


func hold_mouse(p_rel: Vector3, frames: int) -> void:
	for i in frames:
		arena.mouse_override = arena.cam.unproject_position(arena._snap(arena.hero_pos + p_rel))
		await process_frame


func off_legs() -> float:
	return absf(wrapf(arena.upper_ang - arena.legs_tgt, -180.0, 180.0))


## Угол дула наведённой руки от показанного корпуса, ° (плюс — вправо героя).
func arm_yaw(col: int, states: int) -> float:
	return float(arena.meta.aim_arm.offsets[col / states])


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var fwd: Vector3 = arena._world_dir(Vector2(1, 0))
	var left_back: Vector3 = (-fwd).rotated(Vector3.UP, deg_to_rad(-30.0))
	var right_back: Vector3 = (-fwd).rotated(Vector3.UP, deg_to_rad(30.0))

	# п.2 конус
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	var a := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(25.0)) * 3.0)
	var b := enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(-35.0)) * 3.0)
	arena._shotgun_hits()
	check("конус 28°: в 25° попадает", a.hp < 100, a.hp)
	check("конус 28°: в 35° мимо", b.hp == 100, b.hp)
	await fresh("shotgun")
	await aim_at(fwd * 3.0)
	a = enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(37.0)) * 3.0)
	b = enemy_at(fwd.rotated(Vector3.UP, deg_to_rad(-46.0)) * 3.0)
	arena._shotgun_hits(true)
	check("залп 40°: в 37° попадает", a.hp < 100, a.hp)
	check("залп 40°: в 46° мимо", b.hp == 100, b.hp)

	# п.3 бег без бокового сдвига
	var offs: Array = arena.meta.legs.run.offsets_px.s
	var xs := {}
	for o in offs:
		xs[int(o[0])] = true
	check("бег: корпус вбок не ходит (вид спереди)", xs.size() == 1 and xs.has(0), xs.keys())

	# п.1 обрез: рука наведена отдельно, выстрел по мыши
	await fresh("shotgun")
	arena._fire_shotgun()
	await wait(0.3)
	check("в прицеле корпус без руки и отдельный слой руки", arena.garm.visible and arena.upper.texture.resource_path.ends_with("_noarm.png"), arena.upper.texture.resource_path)
	var st: int = int(arena.meta.aim_arm.shotgun.states)
	# стоя корпус догоняет мышь, рука смотрит почти прямо
	await aim_at(fwd * 3.0)
	await wait(0.3)
	check("стоя рука по корпусу", absf(arm_yaw(arena.garm_col, st)) <= 22.5, arm_yaw(arena.garm_col, st))
	# мышь дёрнули в сторону: рука сразу туда, корпус догоняет
	var side_dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(-90.0))
	arena.mouse_override = arena.cam.unproject_position(arena._snap(side_dir * 3.0))
	await process_frame
	var screen_err := absf(wrapf(arena._screen_ang(arena.aim_vec) - (arena.upper_dir * 45.0 - arm_yaw(arena.garm_col, st)), -180.0, 180.0))
	check("мышь дёрнули: рука смотрит на мышь в тот же кадр", screen_err <= 12.0, screen_err)
	var e := enemy_at(side_dir * 3.0)
	arena._fire_shotgun()
	await wait(0.15)
	check("выстрел ушёл в мышь, а не по корпусу", e.hp < 100, e.hp)
	# бег, цель за спиной слева: корпус в пределе 45°, рука тянется назад через правое плечо
	await fresh("shotgun")
	arena._fire_shotgun()
	arena.inp_override = Vector2(1, 0)
	await hold_mouse(left_back * 3.0, 40)
	check("бег, цель сзади-слева: корпус не дальше 45°", off_legs() <= 47.0, off_legs())
	var ay := arm_yaw(arena.garm_col, st)
	check("рука обреза тянется назад своей стороной", ay >= 112.0 or ay <= -157.0, ay)
	var eb := enemy_at(arena.hero_pos + left_back * 3.0)
	arena._shotgun_hits()
	check("и попадает назад", eb.hp < 100, eb.hp)
	check("муфта выброса и дуло берутся с руки", arena._upper_anchor("muzzle") == arena.meta.aim_arm.shotgun.anchors[arena.meta.dirs[arena.upper_dir]][arena.garm_col].muzzle)

	# п.4 пистолет назад на бегу
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await hold_mouse(right_back * 4.0, 30)
	var pe := enemy_at(arena.hero_pos + right_back * 4.0)
	await hold_mouse(right_back * 4.0, 2)
	arena._fire_pistol()
	await hold_mouse(right_back * 4.0, 2)
	check("пистолет на бегу назад попадает", pe.hp == 99, pe.hp)
	check("левая рука наведена", arena.parm_col >= 0 and arena.arm.texture == arena.tex.get(arena._layer("A_aim")))
	await hold_mouse(right_back * 4.0, 10)
	var pst: int = int(arena.meta.aim_arm.pistol.states)
	var py := arm_yaw(arena.parm_col, pst)
	check("левая рука тянется назад своей стороной (после доворота корпуса)", py <= -112.0 or py >= 157.0, py)
	check("корпус не дальше 45° от ног", off_legs() <= 47.0, off_legs())
	await wait(0.4)
	check("через 0,35 с рука вернулась в бег", arena.parm_col < 0, arena.parm_col)

	# п.5 удар назад: разворот не мгновенный
	await fresh()
	await aim_at(fwd * 3.0)
	await wait(0.3)
	var d0: int = arena.upper_dir
	await aim_at(-fwd * 3.0)
	arena._request("light")
	check("сразу после нажатия корпус ещё не развёрнут", arena.upper_dir == d0, [d0, arena.upper_dir])
	var seen := {}
	for i in 8:
		await process_frame
		seen[arena.upper_dir] = true
	check("разворот через промежуточные направления", seen.size() >= 2, seen.keys())
	await wait(0.15)
	check("за 0,15 с развернулся", arena.upper_dir == arena.act_dir, [arena.upper_dir, arena.act_dir])
	arena.action = ""
	# на бегу удар назад: корпус назад, ноги по ходу
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await hold_mouse(-fwd * 3.0, 20)
	await wait(0.4)
	await hold_mouse(-fwd * 3.0, 3)
	var be := enemy_at(arena.hero_pos - fwd * 1.2)
	arena._request("light")
	for i in 10:
		arena.mouse_override = arena.cam.unproject_position(arena._snap(arena.hero_pos - fwd * 3.0))
		await process_frame
	check("на бегу удар назад: корпус не дальше 90° от хода (раунд 12)", absf(wrapf(arena.upper_ang - arena._screen_ang(fwd), -180.0, 180.0)) <= 92.0, arena.upper_ang)
	check("ноги по ходу", arena.legs_dir == arena._dir_index(fwd), [arena.legs_dir, arena.legs_tgt, arena.legs_ang, arena.loco, arena._screen_ang(fwd)])
	await wait(0.3)
	check("враг точно сзади не задет (раунд 12)", be.hp == 100, be.hp)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
