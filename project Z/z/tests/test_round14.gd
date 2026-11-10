extends SceneTree
## Проверка правок раунда 14 без окна: godot --headless --path . -s res://tests/test_round14.gd
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
	arena.pistol = 0
	arena.inp_override = Vector2.ZERO
	arena.mouse_override = Vector2(480, 500)
	arena.module = mod
	arena.loco = "idle"
	arena.hero_pos = Vector3.ZERO
	arena.airborne = false
	arena.dash_t = -1.0
	arena.fire_cd = 0.0
	arena.ammo = {"shotgun": 8, "pistol": 12}
	for e in arena.enemies.duplicate():
		arena.enemies.erase(e)
		e.node.queue_free()
		e.shadow.queue_free()
		if e.flame != null:
			e.flame.queue_free()
	arena.respawn.clear()
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

	# п.1 стоны и крики врагов убраны
	check("в наборе нет стонов и криков", not meta.has("grunt") and not meta.has("death")
		and not FileAccess.file_exists("res://assets/audio/grunt_0.ogg") and not FileAccess.file_exists("res://assets/audio/death_0.ogg"))
	await fresh()
	for i in 6:
		arena._spawn_enemy(arena.hero_pos + Vector3(2.0 + i, 0, 0))
	for e in arena.enemies.duplicate():
		e.hp = 2
		arena._damage(e, 1, "intact", Vector3.RIGHT)
		arena._damage(e, 5, "split", Vector3.RIGHT)
	await wait(0.2)
	check("попадания и смерти без голоса, кровь и удар остались",
		not heard("grunt") and not heard("death") and heard("hit") and heard("gore"), arena.sfx.played)

	# п.4 револьвер: один и тот же звук
	check("у выстрела револьвера один вариант", meta.revolver.size() == 1, meta.revolver)
	var r: AudioStreamRandomizer = arena.sfx.streams["revolver"]
	check("без разброса высоты и громкости", r.random_pitch == 1.0 and r.random_volume_offset_db == 0.0)
	check("у остальных разброс остался", arena.sfx.streams["shotgun"].random_pitch > 1.0)

	# п.5 скольжение убрано
	await fresh()
	arena.inp_override = Vector2(1, 0)
	await wait(0.5)
	arena.inp_override = Vector2.ZERO
	await wait(0.3)
	check("резкая остановка без звука скольжения", not heard("skid") and not meta.has("skid") and arena.loco == "idle", [arena.loco, arena.sfx.played])

	# п.7 шаги: больше вариантов
	check("шагов 4 похожих варианта (раунд 16: было 12, звучали слишком по-разному)", meta.step.size() == 4, meta.step.size())
	check("шаги звучат на бегу", heard("step"))

	# п.2, п.6 новые звуки на месте
	check("пар ульты, звон готовности, тумблер — есть", meta.steam_long.size() >= 2 and meta.ult_ready.size() >= 1 and meta.switch.size() >= 2)
	var src := FileAccess.get_file_as_string("res://scripts/test_arena.gd")
	# раунд 15: пар ещё тише (−12), бросок цепи новый насыщенный (−4)
	check("ульты тише: пар −12 дБ, цепь −4/−8, залп −4, огонь −7, готовность −14",
		src.contains('sfx.play("steam_long", -12.0)') and src.contains('sfx.play("chain_throw", -4.0)')
		and src.contains('sfx.play("chain", -8.0)') and src.contains('sfx.play("fire_burst", -7.0)')
		and src.contains('sfx.play("ult_ready", -14.0)'))
	check("тумблер рывка −16 дБ", src.contains('sfx.play("switch", -16.0)'))

	# п.3 кольцо ульты одного цвета (латунь, без серо-фиолетового)
	for n in ["full", "glow"]:
		var img: Image = load("res://assets/ui/hud_%s.png" % n).get_image()
		var mask: Image = load("res://assets/ui/hud_mask.png").get_image()
		var bad := 0
		var cnt := 0
		for y in img.get_height():
			for x in img.get_width():
				if mask.get_pixel(x, y).g < 0.5:
					continue
				var c := img.get_pixel(x, y)
				cnt += 1
				# серо-фиолетовые 4a4558/6b6578/948ea0/c4bfcc/ece8ee: синий >= красного
				if c.b >= c.r and c.b > 0.15:
					bad += 1
		check("кольцо ульты (%s) только латунь" % n, cnt > 500 and bad == 0, [cnt, bad])

	print("ошибок: %d" % fails)
	quit(1 if fails > 0 else 0)
