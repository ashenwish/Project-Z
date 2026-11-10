extends SceneTree
## Проверка правок раунда 13 без окна: godot --headless --path . -s res://tests/test_round13.gd
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
	arena.dash_cd = 0.0
	arena.dash_used = 0
	arena.dash_spent = 0
	arena.dash_queued = false
	arena.hook = ""
	arena.ult_t = -1.0
	arena.spin_cd = 0.0
	arena.hook_cd = 0.0
	arena.fire_cd = 0.0
	arena.invuln = false
	arena.ammo = {"shotgun": 8, "pistol": 12}
	arena.hero_hp = 1.0
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
		if e.flame != null:
			e.flame.queue_free()
	arena.respawn.clear()
	Engine.time_scale = 1.0
	await wait(0.05)
	arena.sfx.played.clear()


func key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = true
	arena._unhandled_input(ev)


func heard(name: String) -> bool:
	return arena.sfx.played.has(name)


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var hud = arena.hud_g
	var mat: ShaderMaterial = hud.mat

	# п.2 датчик
	check("датчик есть, старая надпись спрятана", hud != null and hud.visible and not arena.hud.visible)
	key(KEY_F1)
	check("F1 показывает подсказку клавиш", arena.hud.visible)
	key(KEY_F1)
	var vp: Vector2 = hud.get_viewport_rect().size
	check("левый верхний угол (с раунда 15)", hud.position.x <= 10.0 and hud.position.y <= 10.0 and vp.y > 0.0, hud.position)
	var tex: Texture2D = hud.gauge.texture
	check("датчик без обода: холст 104x104 (раунд 16)", tex.get_width() == 104 and tex.get_height() == 104, [tex.get_width(), tex.get_height()])
	await fresh()
	key(KEY_F9)
	await wait(0.05)
	check("F9: здоровье 90 %", absf(float(mat.get_shader_parameter("hp_fill")) - 0.9) < 0.01, mat.get_shader_parameter("hp_fill"))
	key(KEY_F10)
	await wait(0.05)
	check("F10: здоровье полное", absf(float(mat.get_shader_parameter("hp_fill")) - 1.0) < 0.01)
	arena.hero_hp = 0.2
	var glow_seen := false
	for i in 30:
		await process_frame
		glow_seen = glow_seen or bool(mat.get_shader_parameter("hp_glow"))
	check("мало здоровья: кольцо пульсирует", glow_seen)
	check("и стучит сердце", heard("heartbeat"))
	arena.hero_hp = 1.0

	# ульта: тратится сразу, восстанавливается по откату
	await fresh()
	check("ульта готова: кольцо полное", float(mat.get_shader_parameter("ult_fill")) >= 0.999)
	arena._ult_press()
	await wait(0.05)
	check("ульта клинка: кольцо сразу пустое", float(mat.get_shader_parameter("ult_fill")) < 0.01, mat.get_shader_parameter("ult_fill"))
	while arena.ult_t >= 0.0:
		await process_frame
	await wait(0.05)
	var f: float = mat.get_shader_parameter("ult_fill")
	check("после вращения кольцо восстанавливается по откату", f > 0.0 and f < 0.2, f)
	arena.spin_cd = 0.05
	await wait(0.15)
	check("откат прошёл: кольцо полное и вспыхивает", float(mat.get_shader_parameter("ult_fill")) >= 0.999 and hud.ult_flash_t > 0.0)
	check("и гудок готовности", heard("ult_ready"))
	await fresh("shotgun")
	arena.fire_cd = arena.FIRE_CD * 0.5
	await wait(0.05)
	check("кольцо показывает ульту текущего оружия (обрез наполовину)", absf(float(mat.get_shader_parameter("ult_fill")) - 0.5) < 0.05, mat.get_shader_parameter("ult_fill"))

	# патроны
	await fresh("shotgun")
	arena._fire_shotgun()
	await wait(0.4)
	check("патроны обреза в центре", hud.shotgun == [7, 8], hud.shotgun)
	arena._fire_pistol()
	await wait(0.05)
	check("патроны револьвера в центре", hud.pistol == [11, 12], hud.pistol)
	arena.ammo.pistol = 3
	arena.pistol = 0
	arena._reload_pistol()
	await wait(0.05)
	check("перезарядка револьвера отмечена", hud.pistol_reload)

	# тумблеры рывка
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(0.05)
	check("один рывок: опущен один тумблер", hud.dash_down == 1 and hud.switch_frame(0) != 0 and hud.switch_frame(1) == 0, [hud.dash_down])
	await wait(0.4)
	check("окно второго рывка: тумблер ещё опущен", hud.dash_down == 1)
	await wait(1.4)
	check("откат прошёл: тумблер поднят", hud.dash_down == 0 and hud.switch_frame(0) == 0, [arena.dash_cd, hud.dash_down])
	check("щелчок тумблера", heard("switch"))
	await fresh()
	arena.inp_override = Vector2(1, 0)
	arena._start_dash()
	await wait(0.1)
	arena._start_dash()
	await wait(0.5)
	check("два рывка: оба тумблера опущены", hud.dash_down == 2, hud.dash_down)
	await wait(1.0)
	check("пока откат 2 с — опущены", hud.dash_down == 2 and arena.dash_cd > 0.0)
	await wait(1.2)
	check("откат прошёл — оба подняты", hud.dash_down == 0, hud.dash_down)

	# п.1 звуки
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx.json"))
	var missing := []
	var total := 0
	for n in meta:
		for fn in meta[n]:
			total += 1
			if not ResourceLoader.exists("res://assets/audio/" + fn):
				missing.append(fn)
	check("все звуки на месте", missing.is_empty() and total >= 80, [total, missing])
	check("учёт источников", FileAccess.file_exists("res://assets/audio/CREDITS.md"))
	var need := ["step", "land", "dash", "jump", "steam", "switch_module", "swing_light", "swing_heavy", "slash", "gore",
		"shotgun", "shotgun_double", "shell", "revolver", "dry_fire", "chain_throw", "fire_burst", "slam", "ult_ready"]   # death убран в раунде 14
	var empty := []
	for n in need:
		if not arena.sfx.has(n):
			empty.append(n)
	check("у каждого события есть звук", empty.is_empty(), empty)

	await fresh("shotgun")
	arena._fire_shotgun()
	await wait(0.9)
	check("выстрел обреза и гильза у ног", heard("shotgun") and heard("shell"), arena.sfx.played)
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await wait(0.6)
	var steps: int = arena.sfx.played.count("step")
	check("шаги в такт бегу (цикл 0,5 с, два шага: за 0,6 с 2–3)", steps >= 2 and steps <= 3, steps)
	arena.inp_override = Vector2.ZERO
	await fresh()
	arena._start_dash()
	await wait(0.35)
	arena._start_jump()
	await wait(0.05)
	check("рывок и прыжок", heard("dash") and heard("jump"), arena.sfx.played)
	while arena.airborne:
		await process_frame
	await wait(0.05)
	check("приземление", heard("land"))
	await fresh()
	arena._spawn_enemy(arena.hero_pos + arena.aim_vec * 1.2)
	var e: Dictionary = arena.enemies[-1]
	e.hp = 1
	arena._request("heavy")
	await wait(0.6)
	check("взмах, разрез и смерть", heard("swing_heavy") and heard("gore") and (heard("slash") or heard("hit")), arena.sfx.played)
	await wait(0.6)
	check("тело падает со звуком", heard("body_fall"))
	await fresh()
	arena.ammo.pistol = 0
	arena._fire_pistol()
	check("пустой барабан щёлкает", heard("dry_fire"))
	await fresh()
	arena._next_module()
	await wait(0.2)
	check("смена оружия: шестерни и пар", heard("switch_module"))

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
