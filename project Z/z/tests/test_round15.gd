extends SceneTree
## Проверка правок раунда 15 без окна: godot --headless --path . -s res://tests/test_round15.gd
## Код выхода 1 — есть ошибки.

var arena
var fails := 0


func check(name: String, ok: bool, info: Variant = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if str(info) == "" else "  [%s]" % str(info)))
	if not ok:
		fails += 1


func wait(t: float) -> void:
	await create_timer(t).timeout


func clear_enemies() -> void:
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
		if e.flame != null:
			e.flame.queue_free()
	arena.respawn.clear()


func fresh(mod := "blade") -> void:
	arena.action = ""
	arena.act_queued = ""
	arena.combo_t = 0.0
	arena.gun = ""
	arena.inp_override = Vector2.ZERO
	arena.mouse_override = Vector2(480, 500)
	arena.module = mod
	arena.loco = "idle"
	arena.hero_pos = Vector3.ZERO
	arena.airborne = false
	arena.dash_t = -1.0
	arena.hook = ""
	arena.hook_cd = 0.0
	clear_enemies()
	await wait(0.05)
	arena.sfx.played.clear()


func heard(name: String) -> bool:
	return arena.sfx.played.has(name)


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx.json"))
	var src := FileAccess.get_file_as_string("res://scripts/test_arena.gd")

	# п.2, п.9 датчик в верхнем левом углу, без трубы слева
	var hud = arena.hud_g
	check("датчик в верхнем левом углу", hud.position == Vector2(hud.MARGIN, hud.MARGIN), hud.position)
	var img: Image = hud.gauge.texture.get_image()
	check("холст без трубы (раунд 16 — и без обода: 104 px)", img.get_width() == 104, img.get_width())
	var cy := float(hud.meta.center[1])
	var pipe := 0
	for y in img.get_height():
		for x in 10:
			if absf(y - cy) > 30.0 and img.get_pixel(x, y).a > 0.0:
				pipe += 1
	check("слева от кольца ничего нет (П-образной трубы)", pipe == 0, pipe)
	check("подсказка F1 правее датчика", arena.hud.position.x >= hud.position.x + 116.0, arena.hud.position)

	# п.8 прицел
	var ch: TextureRect = arena.crosshair
	check("прицел есть, 15 px", ch != null and ch.texture.get_width() == 15)
	var cimg: Image = ch.texture.get_image()
	check("в центре прицела V (остриё в центре)", cimg.get_pixel(7, 7).a > 0.0 and cimg.get_pixel(5, 5).a > 0.0
		and cimg.get_pixel(9, 5).a > 0.0 and cimg.get_pixel(7, 5).a == 0.0)
	var c := cimg.get_pixel(7, 7)
	check("прицел латунный", c.r > c.b and c.g > c.b, c)
	arena.mouse_override = Vector2(300, 200)
	await wait(0.05)
	var center: Vector2 = ch.position + Vector2(7, 7)
	check("центр прицела под мышью (туда же целится герой)", center.distance_to(Vector2(300, 200)) <= 1.0, [ch.position])
	check("системный курсор скрыт", src.contains("Input.mouse_mode = Input.MOUSE_MODE_HIDDEN"))

	# п.1 пар тише на 4 группы
	# раунд 16: двойной прыжок — короткий steam_puff −12, обычный прыжок без пара
	check("пар тише в игре: накачка −6, двойной прыжок −12, прыжок −8, смена оружия −5, ульта клинка −12",
		src.contains('sfx.play("steam", -6.0)') and src.contains('sfx.play("steam_puff", -12.0)') and src.contains('sfx.play("jump", -8.0)')
		and src.contains('sfx.play("switch_module", -5.0)') and src.contains('sfx.play("steam_long", -12.0)'))

	# п.3 шаги героя по камню, п.5 шаги NPC
	check("шагов героя 4 (раунд 16), NPC 10", meta.step.size() == 4 and meta.npc_step.size() == 10, [meta.step.size(), meta.npc_step.size()])
	await fresh()
	arena._spawn_enemy(Vector3(3, 0, 0))
	await wait(1.0)
	check("идущий рядом NPC шагает", heard("npc_step"), arena.sfx.played)
	await fresh()
	arena._spawn_enemy(Vector3(15, 0, 0))
	await wait(1.0)
	check("далёкий NPC (15 м) не слышен", not heard("npc_step"))
	await fresh()
	for i in 8:
		arena._spawn_enemy(Vector3(3.0 + i * 0.5, 0, 2.0 - i * 0.5))
	await wait(0.3)
	check("шаги слышны не больше чем у 4 ближайших", arena._step_listeners().size() <= 4, arena._step_listeners().size())
	check("шаги NPC тише героя", arena.NPC_STEP_DB < -12.0)

	# п.6 второй лёгкий удар клинка
	await fresh()
	var n: String = arena._light_name()
	var chain: Array = arena.meta.upper[n].get("chain", [0])
	arena._start_action(n, 0)
	check("первый лёгкий удар — обычный взмах", heard("swing_light") and not heard("swing_snap"))
	arena.action = ""
	arena.sfx.played.clear()
	var second := 0
	for k in chain:
		if int(k) > 0:
			second = int(k)
			break
	arena._start_action(n, second, true)
	check("второй лёгкий удар — резкий взмах", heard("swing_snap"), [chain, arena.sfx.played])
	arena.action = ""
	check("у лёгкого взмаха остались только варианты с ударом в начале", meta.swing_light.size() >= 2 and meta.swing_snap.size() >= 3)

	# п.10 ульта серпа: звук на всё время и плавный конец
	await fresh("sickle")
	arena._hook_fire()
	await wait(0.15)
	check("цепь звучит, пока летит", arena.sfx.hold_gain("chain_loop") > 0.9 and heard("chain_throw"), arena.sfx.hold_gain("chain_loop"))
	while arena.hook != "":
		await process_frame
	await wait(0.2)
	var g: float = arena.sfx.hold_gain("chain_loop")
	check("после ульты затухает плавно (через 0,2 с ещё слышно)", g > 0.2 and g < 0.9, g)
	await wait(0.5)
	check("через 0,7 с тишина", arena.sfx.hold_gain("chain_loop") == 0.0)

	# п.4, п.7
	check("револьвер: один вариант без разброса", meta.revolver.size() == 1 and arena.sfx.streams["revolver"].random_pitch == 1.0)
	check("рывок тише: −3 дБ в игре, варианты без нарастания", src.contains('sfx.play("dash", -3.0)') and meta.dash.size() >= 2)

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
