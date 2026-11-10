extends SceneTree
## Проверка правок раунда 6 без окна: godot --headless --path . -s res://tests/test_round6.gd
## Код выхода 1 — есть ошибки. Управление проверяется подачей событий ввода в обработчик арены.

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
	arena.dash_used = 0
	arena.dash_t = -1.0
	arena.dash_cd = 0.0
	arena.dash_queued = false
	arena.slam = ""
	arena.slam_cd = 0.0
	arena.invuln = false
	arena.pr_i = -1
	arena.pistol = 0
	arena.ammo = {"shotgun": 6, "pistol": 12}
	arena.ult_t = -1.0
	arena.spin_cd = 0.0
	arena.hook = ""
	arena.hook_cd = 0.0
	arena.fire_cd = 0.0
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


func key(code: int, pressed := true) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	arena._unhandled_input(ev)


func mouse(button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	arena._unhandled_input(ev)


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)

	# п.1 подброс больше не бесконечен
	await fresh()
	check("здоровье врага 8", arena.ENEMY_HP == 8)
	var e := enemy_at(Vector3(1.2, 0, 0))
	await aim_at(e.p)
	arena._launch(e, 5, Vector3.RIGHT, "split")
	check("подброс снял полный урон", e.hp == 3, e.hp)
	check("выживший в воздухе", arena._is_air_state(e), e.state)
	while arena._is_air_state(e):
		await process_frame
	check("после падения иммунитет", e.immune > 2.5, e.immune)
	var hp_before: int = e.hp
	arena.act_launch = true
	arena.action = "blade_heavy"
	arena.act_end = 10
	arena.act_fwd = Vector3.RIGHT
	arena.hero_h = 0.0
	e.hp = 20
	arena._melee_hits()
	arena.action = ""
	check("в иммунитете не подбрасывает, урон идёт", not arena._is_air_state(e) and e.hp == 15, [e.state, e.hp])
	await fresh()
	e = enemy_at(Vector3(1.2, 0, 0), 3)
	arena._launch(e, 5, Vector3.RIGHT, "split")
	check("тяжёлый убивает слабого, а не подбрасывает", not arena.enemies.has(e))
	await fresh()
	e = enemy_at(Vector3(1.2, 0, 0))
	for i in 3:
		arena._launch(e, 5, Vector3.RIGHT, "split")
		if not arena.enemies.has(e):
			break
	check("серия подбросов убивает: цикла нет", not arena.enemies.has(e))

	# п.5 управление
	await fresh()
	key(KEY_Q)
	check("Q: клинок → серп", arena.module == "sickle", arena.module)
	key(KEY_Q)
	check("Q: серп → обрез", arena.module == "shotgun", arena.module)
	key(KEY_Q)
	check("Q: обрез → клинок", arena.module == "blade", arena.module)
	key(KEY_E)
	check("E больше не меняет", arena.module == "blade", arena.module)
	await fresh()
	mouse(MOUSE_BUTTON_LEFT)
	check("ЛКМ: лёгкая сразу", arena.action == "blade_quick", arena.action)
	await fresh()
	mouse(MOUSE_BUTTON_RIGHT)
	check("ПКМ: тяжёлая сразу, без удержания", arena.action == "blade_heavy", arena.action)
	await fresh()
	var am0: int = arena.ammo.pistol
	key(KEY_ALT)
	check("Alt: револьвер", arena.ammo.pistol == am0 - 1 and arena.pistol != 0, arena.ammo.pistol)
	await fresh()
	mouse(MOUSE_BUTTON_RIGHT)
	var am1: int = arena.ammo.pistol
	check("ПКМ не стреляет из револьвера", am1 == 12, am1)
	await fresh()
	key(KEY_SHIFT)
	check("Shift: рывок", arena.dash_t >= 0.0)
	await fresh()
	key(KEY_SPACE)
	check("Space: прыжок", arena.airborne)
	await wait(0.05)
	mouse(MOUSE_BUTTON_RIGHT)
	check("после одного прыжка ПКМ — воздушный тяжёлый", arena.action == "blade_air_heavy", arena.action)
	arena.action = ""
	key(KEY_SPACE)
	await wait(0.05)
	mouse(MOUSE_BUTTON_RIGHT)
	check("двойной прыжок и ПКМ — удар о землю", arena.slam == "fall", arena.slam)
	await fresh()
	arena.slam_cd = 2.0
	key(KEY_SPACE)
	await wait(0.03)
	key(KEY_SPACE)
	await wait(0.03)
	mouse(MOUSE_BUTTON_RIGHT)
	check("в откате удара о землю — воздушный тяжёлый", arena.slam == "" and arena.action == "blade_air_heavy", [arena.slam, arena.action])
	await wait(1.5)

	# обрез: ЛКМ и залп
	await fresh("shotgun")
	mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	check("обрез, ЛКМ: 1 патрон", arena.ammo.shotgun == 5, arena.ammo.shotgun)
	await wait(0.5)
	e = enemy_at(arena.hero_pos + arena.aim_vec * 2.0, 100)
	var p0: Vector3 = arena.hero_pos
	mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.05)
	check("обрез, ПКМ: 2 патрона", arena.ammo.shotgun == 3, arena.ammo.shotgun)
	check("залп: 16 урона вблизи (раунд 8)", e.hp == 84, e.hp)
	check("залп: отдача двигает героя", arena.hero_pos.distance_to(p0) > 0.15)
	await wait(0.7)
	arena.ammo.shotgun = 1
	mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.05)
	check("на залп мало патронов: перезарядка", arena.gun == "reload" and arena.ammo.shotgun == 1, arena.gun)

	# п.2 клинок
	await fresh()
	var near := enemy_at(Vector3(1.5, 0, 0), 100)
	var far := enemy_at(Vector3(-5.5, 0, 0), 100)   # успевает подойти за ульту, но не на 3 м
	key(KEY_CTRL)
	check("Ctrl, клинок: вращение", arena.ult_t >= 0.0)
	check("откат 20 с", absf(arena.spin_cd - 20.0) < 0.1, arena.spin_cd)
	check("неуязвим", arena.invuln)
	key(KEY_CTRL, false)
	await wait(0.05)
	check("свой лист и кольцо", arena.upper.texture == arena.tex.get(arena._layer("U_ult_spin")) and arena.legs.texture == arena.tex.get(arena._layer("L_ult_spin")))
	mouse(MOUSE_BUTTON_LEFT)
	check("в ульте удар не начать", arena.action == "")
	var dirs := {}
	arena.inp_override = Vector2(1, 0)
	p0 = arena.hero_pos
	var t0 := Time.get_ticks_msec()
	await wait(0.3)
	var spd: float = arena.hero_pos.distance_to(p0) / ((Time.get_ticks_msec() - t0) / 1000.0)
	check("движение 70 % (раунд 10)", absf(spd - 5.2 * 0.7) < 0.5, spd)
	arena.inp_override = Vector2.ZERO
	while arena.ult_t >= 0.0:
		dirs[arena.upper_dir] = true
		await process_frame
	check("прошёл все направления", dirs.size() == 8, dirs.size())
	check("вращение наносит урон", near.hp < 100, near.hp)
	check("дальше 3 м не задело", far.hp == 100, far.hp)
	check("после ульты уязвим", not arena.invuln)
	key(KEY_CTRL)
	check("откат не пускает", arena.ult_t < 0.0)
	await fresh()
	arena._start_jump()
	await wait(0.03)
	key(KEY_CTRL)
	check("в воздухе ульты клинка нет", arena.ult_t < 0.0)
	await wait(0.8)

	# п.3 хук
	await fresh("sickle")
	var ang: Vector3 = arena._world_dir(Vector2(1, 0))
	e = enemy_at(ang * 5.0)
	await aim_at(ang * 5.0)
	key(KEY_CTRL)
	check("Ctrl, серп: прицел, не бросок", arena.hook == "aim" and absf(arena.hook_cd) < 0.01, arena.hook)
	await wait(0.05)
	check("виден пунктир и лезвие", arena.chain.multimesh.visible_instance_count > 5 and arena.hook_tip.visible and arena.hook_ghost.visible, arena.chain.multimesh.visible_instance_count)
	var probe: Array = arena._hook_probe()
	check("прицел находит врага на линии", probe[0] == e)
	check("лезвие показано у врага", absf(float(probe[1]) - 5.0) < 0.3, probe[1])
	key(KEY_CTRL, false)
	check("отпускание: бросок", arena.hook == "fly", arena.hook)
	check("откат 5 с", absf(arena.hook_cd - 5.0) < 0.1, arena.hook_cd)
	mouse(MOUSE_BUTTON_LEFT)
	check("пока цепь летит, удар не начать", arena.action == "")
	await wait(0.03)
	check("пока летит, протез без лезвия", arena.upper.texture == arena.tex.get(arena._layer("U_hook")))
	var hp1: int = e.hp
	while arena.hook == "fly":
		await process_frame
	check("зацепил и притягивает", arena.hook == "pull" and e.hp == hp1 - 1, [arena.hook, e.hp])
	while arena.hook == "pull":
		await process_frame
	var dd: float = Vector2(e.p.x, e.p.z).length()
	check("враг у героя", absf(dd - 1.0) < 0.2, dd)
	check("стан 1 с", e.state == "flinch" and e.t < -0.5, [e.state, e.t])
	var ps: Vector3 = e.p
	await wait(0.7)
	check("в стане стоит", e.state == "flinch" and e.p.distance_to(ps) < 0.05, e.state)
	await wait(0.5)
	check("стан кончился", e.state != "flinch", e.state)
	check("цепь спрятана", not arena.hook_tip.visible and arena.chain.multimesh.visible_instance_count == 0)
	await fresh("sickle")
	await aim_at(ang * 3.0)
	key(KEY_CTRL)
	await wait(0.03)
	key(KEY_CTRL, false)
	await wait(0.6)
	check("мимо: цепь вернулась", arena.hook == "", arena.hook)
	key(KEY_CTRL)
	check("откат хука не пускает", arena.hook == "", arena.hook)
	await fresh("sickle")
	e = enemy_at(ang * 5.0, 1)
	await aim_at(ang * 5.0)
	key(KEY_CTRL)
	await wait(0.03)
	key(KEY_CTRL, false)
	await wait(0.3)
	check("цель умерла от хука: цепь пустая", not arena.enemies.has(e) and arena.hook in ["back", ""], arena.hook)
	await wait(0.4)
	await fresh("sickle")
	arena._start_jump()
	await wait(0.03)
	key(KEY_CTRL)
	check("в воздухе хука нет", arena.hook == "", arena.hook)
	await wait(0.7)
	await fresh("sickle")
	key(KEY_CTRL)
	key(KEY_SPACE)
	check("прыжок отменяет прицел", arena.hook == "" and not arena.hook_tip.visible, arena.hook)
	await wait(0.7)

	# п.4 огонь
	await fresh("shotgun")
	await aim_at(ang * 3.0)
	var front := enemy_at(ang * 3.0, 100)
	var wide := enemy_at((ang + ang.cross(Vector3.UP) * 0.7).normalized() * 3.0, 100)  # 35° от оси: шире удара о землю (30°)
	var out := enemy_at(ang.cross(Vector3.UP) * 3.0, 100)
	var neighbour := enemy_at(ang * 6.0 + ang.cross(Vector3.UP) * 0.0, 100)
	var am2: int = arena.ammo.shotgun
	key(KEY_CTRL)
	check("Ctrl, обрез: выстрел", arena.gun == "ult", arena.gun)
	check("откат 12 с", absf(arena.fire_cd - 12.0) < 0.1, arena.fire_cd)
	await wait(0.25)
	check("патроны не тратит", arena.ammo.shotgun == am2)
	check("в конусе: горит", front.burn > 0.0 and front.hp == 98, [front.burn, front.hp])
	check("конус шире удара о землю", wide.burn > 0.0, wide.burn)
	check("вне конуса не горит", out.burn <= 0.0 and out.hp == 100, out.hp)
	check("дальше 5,5 м не горит", neighbour.burn <= 0.0)
	check("пламя на враге", front.flame != null)
	await wait(0.1)
	check("вид обугленного", arena.tex.has("res://assets/enemy/E_%s_s.png" % front.state), front.state)
	key(KEY_CTRL)
	var cd_was: float = arena.fire_cd
	await wait(1.6)
	check("тик 1 урон за 0,5 с", front.hp <= 96 and front.hp >= 92, front.hp)
	check("горящий идёт, не вздрагивает", front.state != "flinch", front.state)
	await wait(3.0)
	check("за 4 с около 8 урона", front.hp >= 89 and front.hp <= 91, front.hp)
	check("огонь погас, вид остался", front.burn <= 0.0 and front.flame == null and front.charred)
	await fresh("shotgun")
	var src := enemy_at(ang * 5.0, 100)
	var nb := enemy_at(ang * 5.0 + ang.cross(Vector3.UP) * 0.8, 100)
	src.state = "idle"
	arena._ignite(src, arena.BURN_T, true)
	await wait(0.7)
	check("огонь перекинулся на соседа", nb.burn > 0.0 and nb.burn <= arena.BURN_T_SPREAD, nb.burn)
	check("сосед не передаёт дальше", not nb.burn_spread)
	await fresh("shotgun")
	e = enemy_at(ang * 5.0, 1)
	arena._ignite(e, arena.BURN_T, true)
	var c0: int = arena.gore.corpses.size()
	await wait(0.7)
	check("сгорел: обугленный труп с огнём", not arena.enemies.has(e) and arena.gore.corpses.size() == c0 + 1 and arena.gore.flames.size() >= 1)
	await fresh("shotgun")
	arena._start_jump()
	await wait(0.03)
	key(KEY_CTRL)
	check("в воздухе выстрел работает", arena.gun == "ult", arena.gun)
	await wait(0.9)

	# п.6 расчленение: все исходы и падения есть и не падают
	await fresh()
	var names: Array = arena.emeta.corpse.keys()
	check("исходов 11, обгоревший теперь перекраска (раунд 7)", names.size() == 11, names.size())
	var missing := []
	for o in names:
		for f in arena.emeta.corpse[o].falls:
			if not ResourceLoader.exists("res://assets/enemy/C_%s_%s.png" % [o, f]):
				missing.append("%s_%s" % [o, f])
		if not ResourceLoader.exists("res://assets/enemy/T_%s.png" % o):
			missing.append("T_" + o)
	for p in ["leg_r", "torso_top"]:
		if not ResourceLoader.exists("res://assets/enemy/P_%s.png" % p):
			missing.append("P_" + p)
	check("все листы на месте", missing.is_empty(), missing)
	for o in names:
		await fresh()
		e = enemy_at(Vector3(3, 0, 0))
		arena._kill(e, o, Vector3.RIGHT)
		Engine.time_scale = 1.0
		await wait(0.05)
		check("смерть %s на земле" % o, not arena.enemies.has(e) and arena.gore.corpses.size() > 0)
	var falls := {}
	for i in 60:
		falls[arena.gore._pick_fall(arena.emeta.corpse.intact.falls)] = true
	check("падения разные", falls.size() >= 3, falls.keys())
	await fresh()
	e = enemy_at(Vector3(3, 0, 0))
	arena._launch(e, 0, Vector3.RIGHT)
	await wait(0.2)
	arena._kill(e, "waist", Vector3.RIGHT)
	Engine.time_scale = 1.0
	check("новый исход и в воздухе", arena.gore.falling.size() >= 1)
	await wait(1.5)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
