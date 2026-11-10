extends Control
class_name HeroHud
## HUD героя (раунд 13): круглый паровой датчик, с раунда 15 в левом верхнем углу и без трубы слева.
## Внешнее кольцо — здоровье, внутреннее — ульта текущего модуля (тратится сразу, восстанавливается по откату),
## в центре патроны обреза и револьвера, под кругом два тумблера рывка.
## Листы рисует tools/hud_gen.py; движок только выбирает сегменты и кадры.

const MARGIN := 8
const SWITCH_FLIP := 0.06        # тумблер проходит среднее положение
const ULT_FLASH := 0.45          # вспышка кольца, когда ульта готова
const LOW_HP := 0.25
const PULSE_HZ := 3.0

var meta: Dictionary
var gauge := TextureRect.new()
var over := Control.new()       # цифры и тумблеры поверх датчика
var mat := ShaderMaterial.new()
var digits: Texture2D
var icons: Texture2D
var switch_tex: Texture2D
var plate: Texture2D
var t := 0.0

# состояние, которое задаёт игра
var hp := 1.0
var ult := 1.0
var shotgun := [8, 8]
var pistol := [12, 12]
var shotgun_reload := false
var pistol_reload := false
var dash_down := 0              # сколько тумблеров опущено

var ult_flash_t := 0.0
var shown_down := [false, false]
var flip_t := [0.0, 0.0]


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/hud.json"))
	digits = load("res://assets/ui/hud_digits.png")
	icons = load("res://assets/ui/hud_icons.png")
	switch_tex = load("res://assets/ui/hud_switch.png")
	plate = load("res://assets/ui/hud_plate.png")
	mat.shader = load("res://scripts/hud_gauge.gdshader")
	mat.set_shader_parameter("tex_empty", load("res://assets/ui/hud_empty.png"))
	mat.set_shader_parameter("tex_glow", load("res://assets/ui/hud_glow.png"))
	mat.set_shader_parameter("tex_mask", load("res://assets/ui/hud_mask.png"))
	mat.set_shader_parameter("size_px", Vector2(meta.size[0], meta.size[1]))
	mat.set_shader_parameter("center_px", Vector2(meta.center[0], meta.center[1]))
	mat.set_shader_parameter("hp_segs", float(meta.hp_segs))
	mat.set_shader_parameter("ult_segs", float(meta.ult_segs))
	gauge.texture = load("res://assets/ui/hud_full.png")
	gauge.material = mat
	gauge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(gauge)
	add_child(over)
	over.draw.connect(_draw_over)
	over.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Вызывается игрой каждый кадр.
func set_state(s: Dictionary, delta: float) -> void:
	t += delta
	var was_ready := ult >= 1.0
	hp = clampf(float(s.hp), 0.0, 1.0)
	ult = clampf(float(s.ult), 0.0, 1.0)
	if ult >= 1.0 and not was_ready:
		ult_flash_t = ULT_FLASH
	ult_flash_t = maxf(ult_flash_t - delta, 0.0)
	shotgun = s.shotgun
	pistol = s.pistol
	shotgun_reload = s.shotgun_reload
	pistol_reload = s.pistol_reload
	dash_down = int(s.dash_down)
	for i in 2:
		var down := i < dash_down
		if down != shown_down[i]:
			shown_down[i] = down
			flip_t[i] = SWITCH_FLIP
		flip_t[i] = maxf(flip_t[i] - delta, 0.0)
	mat.set_shader_parameter("hp_fill", hp)
	mat.set_shader_parameter("ult_fill", ult)
	mat.set_shader_parameter("hp_glow", hp > 0.0 and hp <= LOW_HP and fmod(t * PULSE_HZ, 1.0) < 0.5)
	mat.set_shader_parameter("ult_glow", ult_flash_t > 0.0 and fmod(ult_flash_t * 10.0, 1.0) < 0.6)
	position = Vector2(MARGIN, MARGIN)      # верхний левый угол (раунд 15)
	queue_redraw()
	over.queue_redraw()


## Номер кадра тумблера: 0 вверх, 1 середина, 2 вниз.
func switch_frame(i: int) -> int:
	if flip_t[i] > 0.0:
		return 1
	return 2 if shown_down[i] else 0


## Под датчиком: планка тумблеров (щиток датчика ложится поверх неё).
func _draw() -> void:
	var pw := float(meta.plate[0])
	draw_texture(plate, Vector2(roundf(float(meta.center[0]) - pw / 2.0), float(meta.size[1]) - 4.0))


## Поверх датчика: патроны и тумблеры рывка.
func _draw_over() -> void:
	var cx := float(meta.center[0])
	var cy := float(meta.center[1])
	_count_row(Vector2(cx, cy - 9.0), 0, shotgun, shotgun_reload)
	_count_row(Vector2(cx, cy + 3.0), 1, pistol, pistol_reload)
	var py := float(meta.size[1]) - 4.0
	var pw := float(meta.plate[0])
	var sw: Array = meta.switch
	for i in 2:
		var x := roundf(cx - pw / 2.0) + 6.0 + i * 13.0
		over.draw_texture_rect_region(switch_tex, Rect2(x, py + 2.0, sw[0], sw[1]),
			Rect2(switch_frame(i) * sw[0], 0, sw[0], sw[1]))


## Строка «значок N/M» по центру; при перезарядке мигает тусклыми цифрами.
func _count_row(at: Vector2, icon: int, v: Array, reloading: bool) -> void:
	var dw: int = meta.digit[0]
	var dh: int = meta.digit[1]
	var iw: int = meta.icon[0]
	var text := "%d/%d" % [v[0], v[1]]
	var w := iw + 2 + text.length() * (dw + 1) - 1
	var x := roundf(at.x - w / 2.0)
	over.draw_texture_rect_region(icons, Rect2(x, at.y, iw, meta.icon[1]), Rect2(icon * iw, 0, iw, meta.icon[1]))
	x += iw + 2
	var row := 1 if reloading and fmod(t * 4.0, 1.0) < 0.5 else 0
	var order: String = meta.digit_order
	for ch in text:
		var k := order.find(ch)
		over.draw_texture_rect_region(digits, Rect2(x, at.y, dw, dh), Rect2(k * dw, row * dh, dw, dh))
		x += dw + 1
