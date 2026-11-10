extends SceneTree
## Проверка правок раунда 17 без окна: godot --headless --path . -s res://tests/test_round17.gd
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
	arena.module = mod
	arena.hook = ""
	arena.hook_cd = 0.0
	arena.spin_cd = 0.0
	arena.ult_t = -1.0
	arena.hero_pos = Vector3.ZERO
	arena.mouse_override = Vector2(480, 500)
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
		if e.flame != null:
			e.flame.queue_free()
	arena.respawn.clear()
	for c in arena.gore.corpses:
		c.node.queue_free()
	arena.gore.corpses.clear()
	await wait(0.05)


func on_floor(c: Dictionary) -> bool:
	var s: Sprite3D = c.node
	var up: Vector3 = s.global_basis.z.normalized()        # нормаль спрайта
	return s.billboard == BaseMaterial3D.BILLBOARD_DISABLED and absf(up.y) > 0.99 \
		and s.global_position.y > 0.0 and s.global_position.y < 0.04


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): print("FAIL таймаут"); quit(1))
	arena = load("res://scripts/test_arena.gd").new()
	root.add_child(arena)
	run.call_deferred()


func run() -> void:
	await wait(0.2)
	var gore = arena.gore

	# п.1 трупы на полу
	await fresh()
	arena._spawn_enemy(Vector3(2, 0, 0))
	arena._kill(arena.enemies[-1], "intact", Vector3.RIGHT)
	var c0: Dictionary = gore.corpses[-1]
	check("падение (кадры 0–3) — ещё стоячий спрайт", c0.node.billboard == BaseMaterial3D.BILLBOARD_ENABLED)
	await wait(0.6)
	check("лежащий труп — на плоскости пола", on_floor(c0), [c0.frame, c0.node.global_position])
	var s: Sprite3D = c0.node
	var stretch: float = s.global_basis.y.length() / s.global_basis.x.length()
	check("растянут вдвое вдоль взгляда (камера 30°): на экране тот же рисунок", absf(stretch - 2.0) < 0.01, stretch)
	# экранное положение центра не изменилось: проекция точки трупа = проекция точки на полу
	var cam: Camera3D = arena.cam
	var scr_floor := cam.unproject_position(Vector3(c0.p.x, 0.0, c0.p.z))
	var scr_node := cam.unproject_position(s.global_position)
	check("центр трупа на экране там же, где точка на полу", scr_floor.distance_to(scr_node) <= 1.0, [scr_floor, scr_node])

	for h in [0.5, 2.0, 3.5]:
		await fresh()
		arena._spawn_enemy(Vector3(2, 0, 1))
		var e: Dictionary = arena.enemies[-1]
		e.h = h
		e.vy = 0.0
		e.state = "air_hang"
		arena._kill(e, "split", Vector3.RIGHT)
		var t := 0.0
		while gore.falling.size() > 0 and t < 4.0:
			await process_frame
			t += arena.get_process_delta_time()
		await wait(0.1)
		var all_floor: bool = gore.corpses.size() == 1
		for c in gore.corpses:
			all_floor = all_floor and on_floor(c)
		check("убит в воздухе на высоте %.1f м — лежит на полу" % h, all_floor and gore.falling.is_empty(),
			[gore.corpses.size(), gore.falling.size()])

	# лимит трупов
	await fresh()
	for i in 46:
		arena._spawn_enemy(Vector3(3 + (i % 8) * 0.7, 0, -3 + (i / 8) * 0.7))
		arena._kill(arena.enemies[-1], "intact", Vector3.RIGHT)
	check("сверх 40 старые начинают таять", gore.corpses.filter(func(c): return float(c.get("fade", -1.0)) >= 0.0).size() == 6)
	await wait(1.2)
	check("через 1 с трупов 40", gore.corpses.size() == 40, gore.corpses.size())

	# п.2 кольцо ульты после использования заполняется постепенно (откат прежний)
	await fresh("sickle")
	var mat: ShaderMaterial = arena.hud_g.mat
	arena._hook_fire()
	while arena.hook != "":
		await process_frame
	await wait(0.05)
	var f1: float = mat.get_shader_parameter("ult_fill")
	check("после броска цепи кольцо почти пустое (раньше ≈90 %)", f1 < 0.1, f1)
	check("откат серпа прежний: 5 с с броска", arena.HOOK_CD == 5.0 and arena.hook_cd > 3.5 and arena.hook_cd < 5.0, arena.hook_cd)
	await wait(1.0)
	var f2: float = mat.get_shader_parameter("ult_fill")
	check("и заполняется по откату", f2 > f1 + 0.15 and f2 < 0.5, [f1, f2])
	var src := FileAccess.get_file_as_string("res://scripts/hud_gauge.gdshader")
	check("заливка ульты плавная, не сегментами", src.contains("a < ult_fill"))

	# п.3 цвета мрачнее
	var img: Image = arena.hud_g.gauge.texture.get_image()
	var hm: Dictionary = arena.hud_g.meta
	var cx := float(hm.center[0])
	var cy := float(hm.center[1])
	var hp_c := img.get_pixel(int(cx + 43), int(cy + 3))       # середина кольца здоровья справа
	var ult_c := img.get_pixel(int(cx + 21), int(cy + 21))     # кольцо ульты справа-снизу (r≈30), вне значков
	check("здоровье бордовое (7d0f1c)", hp_c.to_html(false) == "7d0f1c", hp_c.to_html(false))
	check("ульта тусклая латунь (9a7a2e)", ult_c.to_html(false) == "9a7a2e", ult_c.to_html(false))

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
