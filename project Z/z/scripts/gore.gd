class_name Gore
extends Node3D
## Кровь, куски тел, трупы, гильзы, пар, вспышки. Всё на жёстких пикселях палитры PZ-28, без прозрачности.
## Капли — MultiMesh квадратиков 2x2 px; пятна на полу — плоские спрайты, повёрнутые по камере
## (каждая строка экрана — две строки текстуры, поэтому на полу пиксели 1:1).

const PX := 1.0 / 56.0
const GRAVITY := 16.0
const MAX_DROPS := 1500
const MAX_DECALS := 300          # правка 5: лимит пятен; старые удаляются
const DRY_AFTER := 25.0          # свежая кровь засыхает (бриф: blood-2/3 без блика)
const MAX_DEBRIS := 150
const DROP_COLORS := [Color("4f0a12"), Color("7d0f1c"), Color("b3162a"), Color("e02a3c")]

var arena: Node3D
var cam: Camera3D
var fx := {}
var drops: Array = []            # {p, v, c}
var drop_mm: MultiMeshInstance3D
var decals: Array = []           # {node, born, size, v, dried}
var debris: Array = []           # куски, мясо, гильзы: {node, p, v, frame, spin, frames, rest, bleed, kind, bias}
var oneshots: Array = []         # вспышки и пар: {node, t, frames, ms, rise}
var emitters: Array = []         # фонтаны крови: {p, dir, until, rate, acc, follow}
var corpses: Array = []          # {node, frame, ms, durs, p, pool, pool_t, lay_h, fade}
var corpse_n := 0                 # счётчик уложенных трупов: высота над полом, новый поверх старого
const CORPSE_MAX := 40            # больше трупов не держим: старые тают (раунд 17)
const CORPSE_FADE := 1.0          # с
const CORPSE_H := 0.015           # лежащий труп над полом, м: выше луж (0,002–0,012)
var scorched := false            # куски и тела следующей смерти обгоревшие: листы <имя>_s
var flames: Array = []           # огонь на трупах: {node, t, life}
var falling: Array = []          # тела, убитые в воздухе: {node, p, v, frame, spin, dir, outcome}
var pellets: Array = []          # дробь обреза: {p, v, life} (раунд 10)
const PELLET_V := 55.0
const PELLET_HEAD := Color("ece8ee")
const PELLET_TAIL := Color("e0b84a")
const SPARK_COLORS := [Color("ece8ee"), Color("e0b84a"), Color("c4bfcc")]
var rng := RandomNumberGenerator.new()


func setup(a: Node3D, c: Camera3D) -> void:
	arena = a
	cam = c
	for n in ["flash_shotgun", "flash_pistol", "shell", "steam", "chunks"]:
		fx[n] = load("res://assets/fx/%s.png" % n)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = MAX_DROPS
	mm.visible_instance_count = 0
	var q := QuadMesh.new()
	q.size = Vector2(PX * 2, PX * 2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true      # иначе цвета палитры светлеют (розовые капли вместо красных)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	mm.mesh = q
	drop_mm = MultiMeshInstance3D.new()
	drop_mm.multimesh = mm
	add_child(drop_mm)


func _tex(path: String) -> Texture2D:
	if not fx.has(path):
		fx[path] = load(path)
	return fx[path]


func _sprite(tex: Texture2D, hf: int, vf: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = hf
	s.vframes = vf
	s.pixel_size = PX
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	add_child(s)
	return s


## Точка на полу с привязкой к пиксельной сетке: сдвиг вдоль взгляда камеры не меняет картинку.
func ground_snap(p: Vector3, h: float = 0.0) -> Vector3:
	var q: Vector3 = arena._snap(p)
	var d := -cam.global_basis.z
	return q + d * ((h - q.y) / d.y)


# ---------- кровь ----------
func spray(p: Vector3, dir: Vector3, count: int, speed: float, cone: float = 0.7) -> void:
	for i in count:
		var v := (dir.normalized() + Vector3(rng.randf_range(-cone, cone), rng.randf_range(-0.2, cone + 0.4),
			rng.randf_range(-cone, cone))).normalized() * speed * rng.randf_range(0.35, 1.0)
		_drop(p, v)


func _drop(p: Vector3, v: Vector3, c: Variant = null) -> void:
	if drops.size() >= MAX_DROPS:
		drops.pop_front()
	drops.append({"p": p, "v": v, "c": c if c != null else DROP_COLORS[rng.randi_range(0, DROP_COLORS.size() - 1)], "blood": c == null})


## Дробь веером из дула: каждая дробина летит до своей дальности и гаснет искрами (раунд 10).
func pellets_fan(p: Vector3, dir: Vector3, n: int, half_deg: float, rng_m: float) -> void:
	for i in n:
		var a := deg_to_rad(lerpf(-half_deg, half_deg, (float(i) + rng.randf_range(0.2, 0.8)) / float(n)))
		var d := dir.rotated(Vector3.UP, a)
		var life := rng_m * rng.randf_range(0.55, 1.0) / PELLET_V
		var drop_v := -p.y / life * rng.randf_range(0.2, 0.9)     # к концу полёта дробина опускается к полу
		pellets.append({"p": p, "v": d * PELLET_V + Vector3.UP * drop_v, "life": life})


## Фонтан из обрубка: пульсирует, пока не кончится время. follow — узел, за которым он движется.
func spurt(p: Vector3, dir: Vector3, time: float, rate: float, follow: Dictionary = {}) -> void:
	emitters.append({"p": p, "dir": dir, "until": time, "rate": rate, "acc": 0.0, "t": 0.0, "follow": follow})


func decal(p: Vector3, size: String, variant: int = -1) -> Dictionary:
	var v := variant if variant >= 0 else rng.randi_range(0, 2)
	var s := Sprite3D.new()
	s.texture = _tex("res://assets/fx/splat_%s_fresh_%d.png" % [size, v])
	s.pixel_size = PX
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.basis = Basis(Vector3.UP, deg_to_rad(arena.YAW)) * Basis(Vector3.RIGHT, deg_to_rad(-90))
	add_child(s)
	s.global_position = ground_snap(p, 0.002 + (decals.size() % 50) * 0.0002)
	var d := {"node": s, "born": Time.get_ticks_msec() / 1000.0, "size": size, "v": v, "dried": false}
	decals.append(d)
	while decals.size() > MAX_DECALS:
		decals.pop_front().node.queue_free()
	return d


func _set_decal(d: Dictionary, size: String, dried: bool) -> void:
	d.size = size
	d.dried = dried
	d.node.texture = _tex("res://assets/fx/splat_%s_%s_%d.png" % [size, "dried" if dried else "fresh", d.v])


# ---------- куски, мясо, гильзы ----------
func throw(tex: Texture2D, frames: int, row: int, p: Vector3, v: Vector3, kind: String, bleed: float, bias: float) -> Dictionary:
	var s := _sprite(tex, frames, 4 if kind == "chunk" else 1)   # мясо: 4 вида строками
	var d := {"node": s, "p": p, "v": v, "frame": rng.randf_range(0, frames), "spin": rng.randf_range(10, 22) * (1 if rng.randf() < 0.5 else -1),
		"frames": frames, "row": row, "rest": false, "bleed": bleed, "kind": kind, "bias": bias, "drip": 0.0}
	debris.append(d)
	var n := 0
	for i in range(debris.size() - 1, -1, -1):
		if debris[i].kind != "piece":
			n += 1
			if n > MAX_DEBRIS:
				debris[i].node.queue_free()
				debris.remove_at(i)
	return d


func piece(name: String, p: Vector3, v: Vector3) -> void:
	var d := throw(_tex("res://assets/enemy/P_%s%s.png" % [name, _suffix()]), 8, 0, p, v, "piece", 1.4, 0.4)
	spurt(p, Vector3.UP, 1.4, 70.0, d)


func chunks(p: Vector3, dir: Vector3, n: int, speed: float) -> void:
	for i in n:
		var v := (dir.normalized() + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 1.0), rng.randf_range(-0.6, 0.6))).normalized()
		throw(fx.chunks, 8, rng.randi_range(0, 3), p, v * speed * rng.randf_range(0.5, 1.0), "chunk", 0.4, 0.1)


func shell(p: Vector3, v: Vector3) -> void:
	throw(fx.shell, 8, 0, p, v, "shell", 0.0, 0.05)


# ---------- трупы ----------
## Тело, убитое в воздухе: кувыркается, истекает кровью и у пола становится трупом того же исхода.
func _suffix() -> String:
	return "_s" if scorched else ""


func falling_body(outcome: String, dir: int, p: Vector3, v: Vector3, burning: bool = false) -> Dictionary:
	var s := _sprite(_tex("res://assets/enemy/T_%s%s.png" % [outcome, _suffix()]), 8, 8)
	var b := {"node": s, "p": p, "v": v, "frame": 0.0, "spin": rng.randf_range(10.0, 15.0) * (1 if rng.randf() < 0.5 else -1),
		"dir": dir, "outcome": outcome, "drip": 0.0}
	b["scorch"] = scorched
	b["burning"] = burning
	b["flame"] = flame_sprite() if burning else null
	b["shadow"] = arena._make_shadow()
	add_child(b.shadow)
	b.shadow.visible = true
	falling.append(b)
	return b


func _update_falling(delta: float) -> void:
	for i in range(falling.size() - 1, -1, -1):
		var b: Dictionary = falling[i]
		b.v.y -= GRAVITY * delta
		b.p += b.v * delta
		b.frame = fposmod(b.frame + b.spin * delta, 8.0)
		b.drip += delta
		if b.drip > 0.04:              # след из капель за падающим телом
			b.drip = 0.0
			_drop(b.p, Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 1.0), rng.randf_range(-0.8, 0.8)))
		if b.p.y <= 0.45:
			var ground := Vector3(b.p.x, 0.0, b.p.z)
			spray(ground + Vector3.UP * 0.2, Vector3.UP, 45, 3.5, 1.0)
			chunks(ground + Vector3.UP * 0.2, Vector3.UP, 2, 2.5)
			decal(ground, "m")
			corpse(b.outcome, b.dir, ground, Vector3.ZERO, true, b.scorch, b.burning)
			if b.flame != null:
				b.flame.queue_free()
			arena.shake = maxf(arena.shake, 3.0)
			b.node.queue_free()
			b.shadow.queue_free()
			falling.remove_at(i)
			continue
		b.node.frame = int(b.dir) * 8 + int(b.frame)
		b.node.global_position = arena._snap(b.p) + cam.global_basis.z * 0.1
		b.shadow.global_position = arena._snap(Vector3(b.p.x, 0.0, b.p.z)) - cam.global_basis.z * 0.02
		if b.flame != null:
			b.flame.frame = int(b.frame) % 6
			b.flame.global_position = arena._snap(b.p - Vector3.UP * 0.9) + cam.global_basis.z * 0.15


## scorch — листы обгоревшего, дым 3 с; burning — ещё и догорает на полу.
func corpse(outcome: String, dir: int, p: Vector3, knock: Vector3, landed: bool = false, scorch: bool = false, burning: bool = false) -> void:
	var m: Dictionary = arena.emeta.corpse[outcome]
	var s := _sprite(_tex("res://assets/enemy/C_%s_%s%s.png" % [outcome, _pick_fall(m.falls), "_s" if scorch else ""]), 5, 8)
	s.frame = dir * 5 + (4 if landed else 0)
	if burning:
		burn_flames(p)
	var c := {"node": s, "frame": 4 if landed else 0, "ms": 0.0, "durs": m.durations_ms, "dir": dir, "p": p, "knock": knock,
		"pool": null, "pool_t": 0.0, "smoke": 3.0 if scorch else 0.0, "smoke_t": 0.0}
	corpses.append(c)
	_place_corpse(c)
	_cull_corpses()


## Падение выбирается случайно: у каждого исхода свои веса.
func _pick_fall(falls: Dictionary) -> String:
	var total := 0.0
	for k in falls:
		total += float(falls[k])
	var r := rng.randf() * total
	for k in falls:
		r -= float(falls[k])
		if r <= 0.0:
			return k
	return falls.keys()[0]


func flame_sprite() -> Sprite3D:
	var s := _sprite(_tex("res://assets/fx/flame.png"), 6, 1)
	s.offset = Vector2(0, 48)        # низ спрайта у стоп, как у живого врага
	return s


## Догорает на полу.
func burn_flames(p: Vector3) -> void:
	var s := flame_sprite()
	s.global_position = arena._snap(p) + cam.global_basis.z * 1.1
	flames.append({"node": s, "t": 0.0, "life": 1.6})


func _place_corpse(c: Dictionary) -> void:
	if int(c.frame) >= 4:
		_lay_on_floor(c)
		return
	# падение (кадры 0–3): тело ещё стоит или валится — вертикальный спрайт, сдвинут к камере,
	# чтобы пол не срезал нижнюю половину
	c.node.global_position = arena._snap(c.p) + cam.global_basis.z * 1.0


## Лежащий труп (раунд 17): кадр нарисован так, как его видит камера, поэтому его можно положить на пол,
## растянув вдвое вдоль взгляда (камера смотрит под 30°: отрезок пола виден вдвое короче) — на экране
## пиксель в пиксель тот же рисунок, но глубину решает пол: труп не перекрывает стоящих рядом и не висит.
func _lay_on_floor(c: Dictionary) -> void:
	var s: Sprite3D = c.node
	if s.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var stretch := 1.0 / sin(deg_to_rad(-arena.PITCH))
		s.basis = Basis(Vector3.UP, deg_to_rad(arena.YAW)) * Basis(Vector3.RIGHT, deg_to_rad(-90)) \
			* Basis.from_scale(Vector3(1.0, stretch, 1.0))
		c["lay_h"] = CORPSE_H + float(corpse_n % CORPSE_MAX) * 0.0003    # поверх луж; новый поверх старого
		corpse_n += 1
	s.global_position = ground_snap(c.p, float(c.lay_h))


## Лишние трупы (раунд 17): сверх CORPSE_MAX самые старые тают за CORPSE_FADE.
func _cull_corpses() -> void:
	var extra := corpses.size() - CORPSE_MAX
	for c in corpses:
		if extra <= 0:
			break
		if float(c.get("fade", -1.0)) < 0.0:
			c["fade"] = CORPSE_FADE
			c.node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED     # прозрачность вместо отсечения
		extra -= 1


# ---------- вспышки и пар ----------
func oneshot(tex: Texture2D, frames: int, row: int, vframes: int, p: Vector3, ms: float, rise: float = 0.0) -> void:
	var s := _sprite(tex, frames, vframes)
	s.frame = row * frames
	s.global_position = p
	oneshots.append({"node": s, "t": 0.0, "frames": frames, "row": row, "ms": ms, "rise": rise, "p": p})


func flash(kind: String, p: Vector3, angle_idx: int) -> void:
	var frames := 3 if kind == "shotgun" else 2
	oneshot(fx["flash_" + kind], frames, angle_idx, 8, p + cam.global_basis.z * 0.3, 35.0)


## Пороховой дым обреза (раунд 12): клубы вдоль выстрела от дула, темнее пара.
func smoke(p: Vector3, dir: Vector3, n: int) -> void:
	for i in n:
		var o := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.05, 0.1), rng.randf_range(-0.12, 0.12))
		oneshot(_tex("res://assets/fx/smoke.png"), 6, 0, 1, p + dir * (0.15 + 0.22 * i) + o + cam.global_basis.z * 0.25,
			rng.randf_range(75, 110), 0.25)


func steam(p: Vector3, n: int = 1) -> void:
	for i in n:
		var o := Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0, 0.1), rng.randf_range(-0.08, 0.08))
		oneshot(fx.steam, 6, 0, 1, p + o + cam.global_basis.z * 0.2, rng.randf_range(90, 130), 0.5)


# ---------- удар о землю ----------
## Волна и залп лежат на полу, как пятна крови: персонажи стоят на них, а не под ними.
func _floor_fx(tex: Texture2D, frames: int, row: int, vframes: int, p: Vector3, ms: float) -> void:
	oneshot(tex, frames, row, vframes, p, ms)
	var s: Sprite3D = oneshots[-1].node
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.basis = Basis(Vector3.UP, deg_to_rad(arena.YAW)) * Basis(Vector3.RIGHT, deg_to_rad(-90))
	s.global_position = ground_snap(p, 0.003)


func shock(p: Vector3, kind: String) -> void:
	_floor_fx(_tex("res://assets/fx/shock_%s.png" % kind), 5, 0, 1, p, 45.0)


func fire(p: Vector3, dir: int) -> void:
	_floor_fx(_tex("res://assets/fx/fire_gun.png"), 4, dir, 8, p, 70.0)


func blast(p: Vector3, dir: int) -> void:
	_floor_fx(_tex("res://assets/fx/blast_gun.png"), 4, dir, 8, p, 45.0)


## Трещины на полу: живут как пятна крови и общий лимит с ними делят, не сохнут.
func crack(p: Vector3, size: String) -> void:
	var v := rng.randi_range(0, 2)
	var s := Sprite3D.new()
	s.texture = _tex("res://assets/fx/crack_%s_%d.png" % [size, v])
	s.pixel_size = PX
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.basis = Basis(Vector3.UP, deg_to_rad(arena.YAW)) * Basis(Vector3.RIGHT, deg_to_rad(-90))
	add_child(s)
	s.global_position = ground_snap(p, 0.0015)
	decals.append({"node": s, "born": Time.get_ticks_msec() / 1000.0, "size": size, "v": v, "dried": true})
	while decals.size() > MAX_DECALS:
		decals.pop_front().node.queue_free()


# ---------- кадр ----------
func update(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# фонтаны
	for i in range(emitters.size() - 1, -1, -1):
		var e: Dictionary = emitters[i]
		e.t += delta
		if e.follow:
			e.p = e.follow.p
		var pulse := 0.6 + 0.4 * sin(e.t * 14.0)
		e.acc += e.rate * delta * pulse * clampf(1.0 - e.t / e.until, 0.0, 1.0)
		while e.acc >= 1.0:
			e.acc -= 1.0
			var v: Vector3 = (e.dir + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.2, 0.7), rng.randf_range(-0.35, 0.35))) * rng.randf_range(1.2, 2.6)
			_drop(e.p, v)
		if e.t >= e.until:
			emitters.remove_at(i)
	# капли
	var mm := drop_mm.multimesh
	var alive := 0
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d.v.y -= GRAVITY * delta
		d.p += d.v * delta
		if d.p.y <= 0.0:
			if d.blood and rng.randf() < 0.07:
				decal(d.p, "s")
			drops.remove_at(i)
	for d in drops:
		mm.set_instance_transform(alive, Transform3D(Basis(), arena._snap(d.p) + cam.global_basis.z * 0.5))
		mm.set_instance_color(alive, d.c)
		alive += 1
	# дробь: светлая головка и жёлтый штрих за ней
	for i in range(pellets.size() - 1, -1, -1):
		var pl: Dictionary = pellets[i]
		pl.p += pl.v * delta
		pl.life -= delta
		if pl.life <= 0.0 or pl.p.y <= 0.0:
			pl.p.y = maxf(pl.p.y, 0.02)
			for k in 3:
				_drop(pl.p, Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(0.8, 2.0), rng.randf_range(-1.2, 1.2)), SPARK_COLORS[rng.randi_range(0, 2)])
			pellets.remove_at(i)
	var cap: int = mm.instance_count
	for pl in pellets:
		var back: Vector3 = -pl.v.normalized()
		for k in 7:                       # штрих около 14 px: дробь видна на полном ходу (раунд 10)
			if alive >= cap:
				break
			mm.set_instance_transform(alive, Transform3D(Basis(), arena._snap(pl.p + back * PX * 2.0 * k) + cam.global_basis.z * 0.5))
			mm.set_instance_color(alive, PELLET_HEAD if k < 2 else PELLET_TAIL)
			alive += 1
	mm.visible_instance_count = alive
	# куски, мясо, гильзы
	for d in debris:
		if d.rest:
			continue
		d.v.y -= GRAVITY * 0.8 * delta
		d.p += d.v * delta
		d.frame = fposmod(d.frame + d.spin * delta, float(d.frames))
		if d.p.y <= 0.05:
			d.p.y = 0.05
			if d.v.y < -1.5:
				d.v = Vector3(d.v.x * 0.5, -d.v.y * 0.3, d.v.z * 0.5)
				d.spin *= 0.6
				if d.bleed > 0.0:
					decal(d.p, "s" if d.kind == "chunk" else "m")
			else:
				d.rest = true
				if d.kind == "piece":
					decal(d.p, "m")
		var row := int(d.row) if d.kind == "chunk" else 0
		d.node.frame = row * int(d.frames) + int(d.frame)
		if d.rest and d.kind in ["metal", "pilot_part"]:
			d.node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			d.node.global_basis = Basis(Vector3.UP,deg_to_rad(arena.YAW))*Basis(Vector3.RIGHT,-PI/2)*Basis.from_scale(Vector3(1,2,1))
			d.node.global_position = ground_snap(d.p,0.018)
		else:
			d.node.global_position = arena._snap(d.p) + cam.global_basis.z * float(d.bias)
	_update_falling(delta)
	for i in range(flames.size() - 1, -1, -1):
		var fl: Dictionary = flames[i]
		fl.t += delta
		fl.node.frame = int(fl.t * 14.0) % 6
		if fl.t >= float(fl.life):
			fl.node.queue_free()
			flames.remove_at(i)
	# трупы: кадры падения и растущая лужа; лишние тают
	for i in range(corpses.size() - 1, -1, -1):
		var cf: Dictionary = corpses[i]
		if float(cf.get("fade", -1.0)) >= 0.0:
			cf.fade -= delta
			cf.node.modulate.a = clampf(float(cf.fade) / CORPSE_FADE, 0.0, 1.0)
			if float(cf.fade) <= 0.0:
				cf.node.queue_free()
				corpses.remove_at(i)
	for c in corpses:
		if c.frame < 4:
			c.ms += delta * 1000.0
			while c.frame < 4 and c.ms >= float(c.durs[c.frame]):
				c.ms -= float(c.durs[c.frame])
				c.frame += 1
				c.p += c.knock / 4.0
			c.node.frame = int(c.dir) * 5 + int(c.frame)
			_place_corpse(c)
		c.pool_t += delta
		if float(c.smoke) > 0.0:             # обгоревший дымится
			c.smoke -= delta
			c.smoke_t -= delta
			if float(c.smoke_t) <= 0.0:
				c.smoke_t = 0.45
				steam(c.p + Vector3.UP * 0.25, 1)
		if c.pool == null and c.pool_t > 0.35:
			c.pool = decal(c.p, "pool1")
		elif c.pool != null and c.pool.size == "pool1" and c.pool_t > 1.2:
			_set_decal(c.pool, "pool2", false)
		elif c.pool != null and c.pool.size == "pool2" and c.pool_t > 2.6:
			_set_decal(c.pool, "pool3", false)
	# засыхание
	for d in decals:
		if not d.dried and now - float(d.born) > DRY_AFTER:
			_set_decal(d, d.size, true)
	# вспышки и пар
	for i in range(oneshots.size() - 1, -1, -1):
		var o: Dictionary = oneshots[i]
		o.t += delta * 1000.0
		var f := int(o.t / float(o.ms))
		if o.has("durs"):
			f = 0
			var elapsed := float(o.t)
			while f < int(o.frames) and elapsed >= float(o.durs[f]):
				elapsed -= float(o.durs[f])
				f += 1
		if f >= int(o.frames):
			o.node.queue_free()
			oneshots.remove_at(i)
			continue
		o.node.frame = int(o.row) * int(o.frames) + f
		if o.rise > 0.0:
			o.p += Vector3.UP * float(o.rise) * delta
			o.node.global_position = arena._snap(o.p) + cam.global_basis.z * 0.2
