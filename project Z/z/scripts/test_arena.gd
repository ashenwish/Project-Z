extends Node3D

const Mech = preload("res://scripts/mech.gd")
## Тестовая арена: Чернов из трёх слоёв, противники-люди с расчленёнкой, эффекты.
## WASD — бег, мышь — прицел (наведение на врага целит в него), ЛКМ — лёгкая атака (у обреза выстрел),
## ПКМ — тяжёлая (у обреза залп двумя стволами; после двойного прыжка — удар о землю), Alt — револьвер,
## Shift — рывок (и в воздухе), Space — прыжок (дважды), Ctrl — ульта (у серпа зажать — прицел, отпустить — бросок),
## R — перезарядка, Q — смена оружия, F11 — полный экран, C — манекены, 1–4 — проверка ударов.
## Скриншот и выход: godot --path . -- --shot=C:/path/out.png [--move=walk|run] [--aim=0..7]
##   [--module=blade|sickle|shotgun] [--act=blade_heavy] [--fire=shotgun|pistol] [--wait=кадров]
##   [--enemy=метров] (один противник на линии прицела) [--kill=decap|arm_off_r|split|gut|blast|intact]
##   [--ult=1] (ульта текущего модуля; у серпа прицел) [--mouse=x,y] [--reload=1] [--dash=1] [--jump=1] [--slam=1] (двойной прыжок и удар о землю) [--slow=0.1] [--launch=1] (первый враг подброшен; вместе с --kill — смерть в воздухе)

const PX := 1.0 / 56.0          # 1 м = 56 px
const BASE_VIEW := Vector2i(960, 540)
const PITCH := -30.0
const YAW := 45.0
const CROWD := 40
const SPRITE_FEET := 48         # низ холста (96) на точке опоры: стопы на y=93, 2 px запаса, пол не режет подошвы
const HERO_FEET := 64           # слои героя: холст 128x128, стопы на y=125
const HERO_CANVAS := 128.0
const LAYER_BIAS := 0.02        # слои корпуса и руки чуть ближе к камере, чтобы не мерцали с ногами
const COMBAT_HOLD := 1.5        # сколько обрез держится поднятым после выстрела, с
const COMBO_WINDOW := 0.35      # окно нажатия после удара: следующий идёт как продолжение серии, с
const COMBO_BUFFER := 0.4       # нажатие во время удара запоминается на столько секунд
const COMBO_CANCEL := 0.07      # через столько после попадания хвост удара обрезается следующим ударом
const COMBO_WINDUP := 0.4       # доля замаха, которая остаётся у удара в серии
const HEAVY_RUN_SLOW := 0.7     # скорость бега во время тяжёлого удара
const TURN_UPPER := 720.0       # скорость поворота корпуса за мышью, °/с: проходит промежуточные направления
const TURN_LEGS := 540.0
const TORSO_LIMIT := 45.0        # на бегу корпус за курсором, но не дальше этого от ног (раунд 10, было 80)
const ARM_CROSS := 60.0          # раунд 11: рука с оружием через грудь не дальше этого; корпус на бегу выбирает сторону
const AIM_STEP := 22.5           # наведённая рука: шаг направлений относительно корпуса
const PISTOL_AIM_HOLD := 0.35     # столько после выстрела левая рука остаётся наведённой
const TURN_ACT := 1500.0          # удар разворачивает корпус через промежуточные направления: 180° за 0,12 с (раунд 12)
const ACT_RUN_LIMIT := 90.0      # на бегу удар не дальше этого от хода (раунд 12)
const AIM_FREE := 0.3           # столько после удара или выстрела корпус ещё свободен, потом возврат
const ASSIST_ANGLE := 30.0      # помощь прицеливания: удар наводится на врага в этом угле от курсора
const ASSIST_REACH := 0.8       # и чуть дальше дальности удара, м
const RUN_START_T := 0.15
const RUN_START_SPEED := 0.7
const RUN_STOP_T := 0.19
const RUN_STOP_SLIDE := 0.5     # доля скорости бега в начале торможения
const LAND_T := 0.18
const TAKEOFF_T := 0.07
const SWITCH_T := 0.28
const GHOST_EVERY := 0.05       # остаточные силуэты рывка
const GHOST_LIFE := 0.15
const IDLE_CYCLE := 1.02
const LEGS_TURN_ON := 105.0     # стоя ноги разворачиваются к прицелу, только когда он за плечом
const DIR_HYST := 5.0           # запас смены кадра направления, °
const ENEMY_HIT_W := 14.0       # полуширина спрайта врага для наведения мышью, px
const ENEMY_HIT_H := 90.0
const MAG := {"shotgun": 8, "pistol": 12}
const DASH_TIME := 0.25
const DASH_DIST := 3.2
const DASH_DIST_AIR := 2.6
const DASH_CD := 2.0            # откат после двух рывков
const DASH_WINDOW := 0.8        # столько ждёт второй рывок
const DASH_CD_MIN := 0.6        # откат, если второго рывка не было или пауза между ними во всё окно
const DASH_GAP_FAST := 0.35     # пауза до этого времени считается «подряд»: полный откат
const JUMP_TIME := 0.62          # один прыжок: столько длится и на такую высоту поднимает
const JUMP_HEIGHT := 0.9
const HERO_G := 8.0 * JUMP_HEIGHT / (JUMP_TIME * JUMP_TIME)
const JUMP_V := 4.0 * JUMP_HEIGHT / JUMP_TIME
const MAX_JUMPS := 2
const AIR_ACT_G := 0.25         # в воздушном ударе герой падает медленнее
const AIR_HIT_VY := 0.6         # попадание в воздухе подхватывает героя: комбо не обрывается падением
const AIR_ACT_VY := 1.5         # воздушный удар гасит подъём: герой остаётся на высоте цели, а не улетает
const AIR_ACT_SPEED := 0.6      # доля скорости бега во время воздушного удара
const AIR_REACH := 0.8          # удар достаёт врага при такой разнице высот, м
const LAUNCH_H := 1.5           # подброс: высота и время подъёма
const LAUNCH_T := 0.35
const LAUNCH_V := 2.0 * LAUNCH_H / LAUNCH_T
const ENEMY_G := LAUNCH_V / LAUNCH_T
const FALL_T := 0.4             # падение с вершины: настоящая дуга, без зависания
const ENEMY_FALL_G := 2.0 * LAUNCH_H / (FALL_T * FALL_T)
const JUGGLE_V := 3.2           # удар по врагу в воздухе даёт короткий толчок вверх
const JUGGLE_MAX_H := 1.9       # выше не подбрасывает
const AIR_V_HANG := 2.0         # при такой вертикальной скорости враг показан у вершины
const HANG_HITS := 8            # после стольких ударов падает в любом случае
const LAUNCH_IMMUNE := 3.0      # столько секунд после падения врага нельзя подбросить снова
const SPIKE_V := 14.0           # удар вниз
const SPIKE_DMG := 2            # урон о пол
const ENEMY_AIR_FEET := 64      # воздушные листы врага: холст 128x128
# Ульты (раунд 6), Ctrl.
const SPIN_CD := 20.0
const SPIN_T := 1.5
const SPIN_R := 3.0
const SPIN_DMG := 2
const SPIN_HITS := 0.15         # удар каждые столько секунд
const SPIN_SPEED := 0.7         # доля скорости бега
const SPIN_WIND := 0.08         # замах и возврат без вращения
const SPIN_END := 0.1
const SPIN_DIR_T := (SPIN_T - SPIN_WIND - SPIN_END) / 32.0   # 4 оборота: 32 направления (раунд 10)
const SPIN_KNOCK := 0.5         # отбрасывание по радиусу
const SPIN_DRIFT := 0.5         # без ввода герой понемногу идёт к прицелу, м/с
const HOOK_CD := 5.0
const HOOK_RANGE := 8.0
const HOOK_V := 35.0
const HOOK_BACK_V := 45.0
const HOOK_SAG := 0.35          # провисание цепи в полёте, м на 8 м
const HOOK_FREE := 0.6          # столько после притяжения первый удар идёт без замаха
const HOOK_PULL_T := 0.25
const HOOK_STUN := 1.0
const HOOK_WIDTH := 0.7         # радиус захвата цепью, м
const HOOK_LINK := 0.11         # шаг звеньев цепи, м
const HOOK_MAX_LINKS := 90
const FIRE_CD := 12.0
const FIRE_R := 5.5
const FIRE_HALF := 40.0         # полуугол: шире удара о землю (30)
const FIRE_DMG := 2
const BURN_T := 4.0
const BURN_T_SPREAD := 3.0
const BURN_TICK := 0.5
const BURN_DMG := 1
const BURN_SPREAD_R := 1.0
const SHOOT2_RANGE := 7.0       # залп двумя стволами: 2 патрона
const SHOOT2_CONE := 40.0       # полуугол (раунд 11; раунд 10 — 55)
const SHOOT2_DMG := [16, 8, 4]
const SLAM_V := 16.0            # удар о землю: скорость падения
const SLAM_CD := 3.0
const STUN := 0.5
const FLINCH_T := 0.21          # обычная реакция на удар; стан длиннее за счёт отрицательного старта
const SLAM := {  # радиус м, урон в центре, урон у края, исход
	"blade": [3.0, 3, 1, "split"], "sickle": [2.3, 2, 1, "gut"]}
const SLAM_GUN := [4.5, 30.0]    # длина м, полуугол °
const SLAM_GUN_ZONES := [[2.0, 20, "blast"], [3.5, 12, "intact"], [4.5, 8, "intact"]]  # до м, урон, исход (раунд 9)
const MODULES := ["blade", "sickle", "shotgun"]
const MODULE_NAMES := {"blade": "паровой клинок", "sickle": "серп", "shotgun": "обрез"}
const LIGHT := {"blade": "blade_quick", "sickle": "sickle_quick"}
const HEAVY := {"blade": "blade_heavy", "sickle": "sickle_heavy"}
const AIR_LIGHT := {"blade": "blade_air_quick", "sickle": "sickle_air_quick"}
const AIR_HEAVY := {"blade": "blade_air_heavy", "sickle": "sickle_air_heavy"}
const SPIKE_ACTIONS := ["blade_air_heavy", "sickle_air_heavy"]   # у серпа сбрасывает второй удар
const TEST_KEYS := {KEY_1: "blade_quick", KEY_2: "blade_heavy", KEY_3: "sickle_quick", KEY_4: "sickle_heavy"}
## Исходы смерти по оружию (раунд 6): случайный из списка.
const OUTCOMES := {
	"blade_quick": ["decap", "arm_off_r", "arm_off_l", "leg_off"], "blade_air_quick": ["decap", "arm_off_r", "arm_off_l", "leg_off"],
	"blade_heavy": ["split", "waist"], "blade_air_heavy": ["split", "waist"],
	"sickle_quick": ["stab", "gut", "leg_off"], "sickle_air_quick": ["stab", "gut", "leg_off"],
	"sickle_heavy": ["gut", "stab"], "sickle_air_heavy": ["gut", "stab"],
	"spin": ["waist", "decap", "arm_off_r", "arm_off_l", "leg_off"]}
const SHAKE := {"blade_quick": 1.0, "blade_heavy": 3.0, "sickle_quick": 1.0, "sickle_heavy": 2.0,
	"gun_shoot": 4.0, "pistol": 1.0, "blade_air_quick": 1.0, "blade_air_heavy": 3.0,
	"sickle_air_quick": 1.0, "sickle_air_heavy": 2.0}
## Скорость шага берётся из tools/hero_render.py (без проскальзывания стоп).
const SPEED := {"walk": 1.19, "run": 5.2}
const HERO_IDLE := preload("res://assets/hero/hero_idle.png")
const FLOOR_TEX := preload("res://assets/env/floor_test.png")

## Противники: урон, дальность и исход смерти по оружию (правка 5, раунд 2).
const ENEMY_COUNT := 6
const ENEMY_HP := 8
const MELEE := {  # урон, дальность м, полуугол °
	"blade_quick": [2, 1.8, 80.0], "blade_heavy": [5, 2.0, 85.0],
	"sickle_quick": [1, 1.7, 80.0], "sickle_heavy": [2, 1.9, 85.0],
	"blade_air_quick": [1, 2.0, 90.0], "blade_air_heavy": [3, 2.2, 90.0],
	"sickle_air_quick": [1, 1.9, 90.0], "sickle_air_heavy": [2, 2.1, 90.0]}
const SHOTGUN_RANGE := 8.0
const SHOTGUN_CLOSE := 2.5       # вплотную: убивает и расчленяет с одного выстрела (раунд 8)
const SHOTGUN_MID := 4.5
const SHOTGUN_DMG := [12, 8, 4]  # вплотную, средне, дальше
const SHOTGUN_CONE := 28.0       # полуугол (раунд 11; раунд 10 — 40)
const SHOTGUN_PELLETS := 9
const SHOTGUN_KNOCK := [0.6, 0.35, 0.15]   # толчок дробью по зонам, м
const HOOK_ASSIST := 12.0         # ассист крюка: доворот на врага в этом угле от курсора, °
const NPC_STEP_RANGE := 9.0       # шаги NPC слышны до этого расстояния, м (раунд 15)
const NPC_STEP_MAX := 4           # и только у стольких ближайших
const NPC_STEP_DB := -20.0        # громкость шага NPC рядом (шаг героя −12)
const CHAIN_FADE := 0.5           # затухание звука цепи после ульты серпа, с
const STEP_MIN := 0.17            # шаги не чаще, с (раунд 16)
const STEP_GAP := 0.12            # короткий обрыв бега (смена клавиш) не сбрасывает такт шагов, с
const PISTOL_RANGE := 14.0
const PISTOL_CONE := 7.0

var meta: Dictionary
var emeta: Dictionary
var tex := {}
var cam: Camera3D
var legs: Sprite3D
var upper: Sprite3D
var arm: Sprite3D
var garm: Sprite3D             # правая рука с обрезом, наведённая отдельно от корпуса (раунд 11)
var garm_col := -1              # кадр листа S_aim или -1
var parm_col := -1              # кадр листа A_aim (левая рука с револьвером) или -1
var pistol_aim_t := 0.0
var trail: Sprite3D
var gore: Gore
var crowd := Node3D.new()
var hud := Label.new()          # подсказка клавиш, F1 (раунд 13)
var hud_g: HeroHud              # круглый датчик (раунд 13)
var hero_hp := 1.0              # доля здоровья; F9/F10 — отладка
var mech_camera := Vector2.ZERO
var dash_spent := 0             # опущенные тумблеры рывка: сколько рывков ждут отката
var sfx: Sfx                    # звуки (раунд 13)
var crosshair: TextureRect      # прицел вместо курсора (раунд 15)
var ult_was_ready := true
var heart_t := 0.0
var step_dist := 0.0            # путь с последнего шага, м (раунд 16)
var step_since := 1.0           # время с последнего шага, с
var step_gap := 1.0             # сколько бег прерван, с
var step_last := Vector3.ZERO
var heavy_count := 0            # тяжёлые удары с последнего пара
var heavy_every := 4            # пар на этом по счёту тяжёлом (4 или 5)
var act_steam := false          # текущий тяжёлый удар с паром
var ult_cd_end := {}            # модуль -> остаток отката в момент конца ульты (-1 — ульта идёт), для кольца HUD
var rng := RandomNumberGenerator.new()

var hero_pos := Vector3.ZERO
var module := "blade"
var aim_dir := 1
var aim_vec := Vector3(1, 0, 0)
var aim_target: Variant = null  # враг под курсором
var upper_ang := 45.0           # плавный поворот корпуса и ног, ° относительно экрана
var upper_dir := 1
var legs_ang := 45.0
var legs_tgt := 45.0
var mouse_override: Variant = null   # для проверок без мыши и клавиатуры
var inp_override: Variant = null
var combat_t := 0.0
var shake := 0.0
var lift := Vector2(0, HERO_FEET)
var upper_now := ["idle_blade", 0, 1]   # имя листа корпуса, кадр, направление — для точек эффектов
var steam_t := 0.0

var loco := "idle"
var leg_phase := 0.0
var legs_dir := 1

var action := ""                # удар правым модулем
var act_frame := 0
var act_turn := false           # стоя: шаг-разворот перед ударом (раунд 12)
var act_ms := 0.0
var act_end := 0
var act_queued := ""            # следующий удар, нажатый во время текущего: light | heavy
var combo_name := ""            # окно продолжения серии после отрезка
var combo_start := 0
var combo_t := 0.0
var act_dir := 1
var act_fwd := Vector3.FORWARD
var act_right := Vector3.RIGHT
var act_launch := false         # этот тяжёлый начинает комбо и подбрасывает
var act_finisher := false       # следующий тяжёлый идёт в серии и не подбрасывает
var act_q_t := 0.0              # сколько ещё помнится нажатие
var act_since_hit := -1.0       # времени с попадания в этом отрезке, -1 — ещё не било

var gun := ""                   # обрез: "" | raise | aim | shoot | lower
var gun_frame := 0
var gun_ms := 0.0
var gun_queued := ""            # выстрел в очереди: shoot | shoot2
var pistol := 0                 # 0 готов, 1 выстрел, 2–3 отдача
var pistol_ms := 0.0
var ammo := {"shotgun": 8, "pistol": 12}
var pr_i := -1                  # перезарядка револьвера: номер шага или -1
var pr_ms := 0.0
var pending := []               # выстрелы и удары, которые надо отрисовать эффектами в этом кадре

var dash_t := -1.0              # рывок: время с начала или -1
var dash_cd := 0.0
var dash_vec := Vector3.ZERO
var dash_speed := 0.0
var dash_used := 0              # сколько рывков из двух уже сделано
var dash_window := 0.0
var dash_queued := false        # второй рывок нажат во время первого
var dash_gap := 0.0             # пауза перед вторым рывком
var slam := ""                  # удар о землю: "" | fall | impact
var slam_frame := 0
var slam_ms := 0.0
var slam_cd := 0.0
var invuln := false             # неуязвимость рывка; проверит её будущая атака противников
var airborne := false
var hero_vy := 0.0
var jumps_used := 0
var hero_h := 0.0
var shadow: Sprite3D

var aim_dist := 5.0             # до точки прицела, м
var aim_free := 0.0             # корпус пока не ограничен углом от ног
var run_start_t := -1.0         # разгон: время с начала или -1
var run_stop_t := -1.0          # торможение
var run_stop_vec := Vector3.ZERO
var land_t := -1.0
var takeoff_t := -1.0
var idle_t := 0.0
var switch_t := -1.0            # смена оружия
var switch_from := "blade"
var switch_steamed := false
var ghost_t := 0.0
var ghosts: Array = []          # {node, t}
var combo_free := false         # следующий удар быстрый, но подбросить может (после хука)
var ult_t := -1.0               # вращение клинка: время с начала или -1
var ult_hit_t := 0.0
var ult_start_dir := 0
var spin_cd := 0.0
var hook := ""                  # хук: "" | aim | fly | pull | back
var hook_t := 0.0
var hook_cd := 0.0
var hook_dir := Vector3.RIGHT
var hook_len := 0.0
var hook_dist := 0.0
var hook_target: Variant = null
var hook_from := Vector3.ZERO
var fire_cd := 0.0
var chain: MultiMeshInstance3D
var hook_tip: Sprite3D
var hook_ghost: Sprite3D
var enemies: Array = []         # {node, shadow, p, h, vy, hp, dir, state, t, hits, spiked, immune, burn, burn_tick, burn_spread, charred, flame}
var respawn: Array = []
var demo := {}
var last_win := Vector2i.ZERO


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hero/layers/layers.json"))
	emeta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemy/enemy.json"))
	_make_camera()
	_make_floor()
	legs = _make_sprite()
	upper = _make_sprite()
	arm = _make_sprite()
	garm = _make_sprite()
	trail = _make_sprite()
	legs.offset = Vector2(0, HERO_FEET)
	shadow = _make_shadow()
	for s in [shadow, legs, upper, garm, arm, trail]:
		add_child(s)
	_make_ult_nodes()
	gore = Gore.new()
	add_child(gore)
	gore.setup(self, cam)
	add_child(crowd)
	_make_crowd()
	crowd.visible = false
	var cl := CanvasLayer.new()
	hud_g = HeroHud.new()
	cl.add_child(hud_g)
	# подсказка F1 — правее датчика: датчик теперь в верхнем левом углу (раунд 15)
	hud.position = Vector2(HeroHud.MARGIN * 2 + 120, 4)
	hud.add_theme_font_size_override("font_size", 10)
	hud.visible = false
	cl.add_child(hud)
	# прицел вместо курсора мыши (раунд 15)
	crosshair = TextureRect.new()
	crosshair.texture = load("res://assets/ui/crosshair.png")
	crosshair.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.size = crosshair.texture.get_size()
	cl.add_child(crosshair)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	sfx = Sfx.new()
	add_child(sfx)
	add_child(cl)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.trim_prefix("--").split("=", true, 1)
			demo[kv[0]] = kv[1]
	_fit_window()
	_apply_resolution()

	module = demo.get("module", module)
	if demo.has("aim"):
		aim_dir = int(demo.aim)
		upper_dir = aim_dir
		upper_ang = aim_dir * 45.0
		legs_ang = upper_ang
		legs_tgt = upper_ang
		legs_dir = aim_dir
		aim_vec = _dir_vector(aim_dir)
	if demo.has("mech"):
		_spawn_mech(hero_pos + aim_vec * float(demo.mech))
	elif demo.has("enemy"):
		_spawn_enemy(hero_pos + aim_vec * float(demo.enemy))
	else:
		for i in ENEMY_COUNT:
			_spawn_enemy()
	if not demo.has("enemy") and not demo.has("mech") and get_tree().current_scene == self:
		_spawn_mech(hero_pos + _dir_vector(3) * 8.0)
	if demo.has("launch") and enemies.size() > 0:
		_launch(enemies[0], 0, aim_vec)
		if demo.has("kill"):
			enemies[0].h = LAUNCH_H
	if demo.has("kill") and enemies.size() > 0:
		_kill(enemies[0], demo.kill, aim_vec)
	if demo.has("act"):
		var n: String = demo.act
		module = "blade" if n.begins_with("blade") else "sickle"
		_start_action(n)
	if demo.get("fire", "") == "shotgun":
		module = "shotgun"
		_fire_shotgun()
	elif demo.get("fire", "") == "pistol":
		_fire_pistol()
	if demo.has("mouse"):
		var mp: PackedStringArray = demo.mouse.split(",")
		mouse_override = Vector2(float(mp[0]), float(mp[1]))
	if demo.has("ult"):
		_ult_press()
	if demo.has("reload"):
		_reload()
	if demo.has("dash"):
		_start_dash()
	if demo.has("jump"):
		_start_jump()
	if demo.has("slam"):
		_start_jump()
		_start_jump()
		_start_slam()
	if demo.has("slow"):
		Engine.time_scale = float(demo.slow)   # для снимков коротких эффектов
	if demo.has("shot"):
		_shot(demo.shot, int(demo.get("wait", "20")))
	if demo.has("toggle"):
		await get_tree().create_timer(2.0).timeout
		_toggle_fullscreen()


# ---------- окно и разрешение (правка 3, раунд 2) ----------
## Целый масштаб x2/x3 подбирается под окно, внутреннее разрешение подгоняется: без обрезки и полос.
func _apply_resolution() -> void:
	var ws := get_window().size
	last_win = ws
	var s := maxi(1, mini(ws.x / BASE_VIEW.x, ws.y / BASE_VIEW.y))
	var vs := Vector2i(ws.x / s, ws.y / s)
	get_tree().root.content_scale_size = vs
	cam.size = vs.y * PX
	if demo.has("debug"):
		print("DBG mode=%d win=%s root.size=%s content=%s scale=%d screen=%s" % [DisplayServer.window_get_mode(), ws, get_tree().root.size, vs, s, DisplayServer.screen_get_size()])


## Стартовое окно не больше рабочей области экрана (у 2560x1440 при 150% это 1707x960).
func _fit_window() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED or demo.has("shot"):
		return
	var usable := DisplayServer.screen_get_usable_rect()
	var s := maxi(1, mini(usable.size.x / BASE_VIEW.x, (usable.size.y - 48) / BASE_VIEW.y))
	var size := BASE_VIEW * s
	if get_window().size.x > usable.size.x or get_window().size.y > usable.size.y - 48:
		get_window().size = size
		get_window().position = usable.position + (usable.size - size) / 2


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------- сцена ----------
func _make_camera() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = BASE_VIEW.y * PX
	cam.rotation_degrees = Vector3(PITCH, YAW, 0)
	cam.far = 200.0
	add_child(cam)


func _make_floor() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = FLOOR_TEX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(20, 20, 1)   # плита 2 м на 40 м пола
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(40, 40)
	mesh.material = mat
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = mesh
	add_child(floor_mi)


func _make_sprite() -> Sprite3D:
	var s := Sprite3D.new()
	s.pixel_size = PX
	s.offset = Vector2(0, SPRITE_FEET)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	return s


## Тень героя в прыжке: эллипс тёмного цвета палитры с дизером, без полупрозрачности.
func _make_shadow() -> Sprite3D:
	var img := Image.create(30, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 30:
			var d := Vector2((x - 14.5) / 15.0, (y - 6.5) / 7.0).length()
			if d <= 1.0 and (d < 0.7 or (x + y) % 2 == 0):
				img.set_pixel(x, y, Color("0b0a10"))
	var s := _make_sprite()
	s.texture = ImageTexture.create_from_image(img)
	s.offset = Vector2(0, 7)        # низ эллипса на уровне пола: иначе пол срезает его нижнюю половину
	s.visible = false
	return s


func _make_ult_nodes() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = HOOK_MAX_LINKS
	mm.visible_instance_count = 0
	var q := QuadMesh.new()
	q.size = Vector2(PX * 2, PX * 2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	mm.mesh = q
	chain = MultiMeshInstance3D.new()
	chain.multimesh = mm
	add_child(chain)
	hook_tip = _make_sprite()
	hook_tip.texture = load("res://assets/fx/hook_tip.png")
	hook_tip.vframes = 8
	hook_tip.offset = Vector2.ZERO
	hook_tip.visible = false
	add_child(hook_tip)
	hook_ghost = _make_shadow()
	add_child(hook_ghost)


func _make_crowd() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in CROWD:
		var ang := r.randf() * TAU
		var dist := r.randf_range(2.0, 8.5)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var s := _make_sprite()
		s.texture = HERO_IDLE
		s.vframes = 8
		s.modulate = Color(0.75, 0.45, 0.45)
		s.frame = _dir_index(-p)
		crowd.add_child(s)
		s.global_position = _snap(p)


## Лист: строки — направления (s, se, e, ne, n, nw, w, sw), столбцы — кадры.
func _show(s: Sprite3D, path: String, cols: int, dir: int, col: int) -> void:
	if not tex.has(path):
		tex[path] = load(path)
	if s.texture != tex[path]:
		s.texture = tex[path]
		s.hframes = cols
		s.vframes = 8
	s.frame = dir * cols + col


func _layer(name: String) -> String:
	return "res://assets/hero/layers/%s.png" % name


# ---------- направления ----------
## Направление в мире -> строка листа относительно экрана.
func _dir_index(dir: Vector3) -> int:
	var yb := Basis(Vector3.UP, deg_to_rad(YAW))
	var x := dir.dot(yb * Vector3.RIGHT)
	var y := dir.dot(yb * Vector3.BACK)
	var ang := fposmod(rad_to_deg(atan2(x, y)), 360.0)
	return int(round(ang / 45.0)) % 8


func _dir_vector(index: int) -> Vector3:
	var yb := Basis(Vector3.UP, deg_to_rad(YAW))
	var ang := deg_to_rad(index * 45.0)
	return ((yb * Vector3.RIGHT) * sin(ang) + (yb * Vector3.BACK) * cos(ang)).normalized()


## Направление в мире -> угол относительно экрана, ° (0 — s, 45 — se ...).
func _screen_ang(dir: Vector3) -> float:
	var yb := Basis(Vector3.UP, deg_to_rad(YAW))
	return rad_to_deg(atan2(dir.dot(yb * Vector3.RIGHT), dir.dot(yb * Vector3.BACK)))


func _turn(cur: float, target: float, rate: float, delta: float) -> float:
	var diff := wrapf(target - cur, -180.0, 180.0)
	return wrapf(cur + clampf(diff, -rate * delta, rate * delta), -180.0, 180.0)


## Кадр направления по углу, с запасом: у границы двух кадров спрайт не мерцает.
func _shown(ang: float, cur: int) -> int:
	if absf(wrapf(ang - cur * 45.0, -180.0, 180.0)) > 22.5 + DIR_HYST:
		return posmod(int(round(ang / 45.0)), 8)
	return cur


## Привязка к пиксельной сетке в плоскости экрана: иначе пиксели «плывут».
func _snap(p: Vector3) -> Vector3:
	var b := cam.global_basis
	var q := b.inverse() * p
	q.x = round(q.x / PX) * PX
	q.y = round(q.y / PX) * PX
	return b * q


func _update_aim() -> void:
	if demo.has("aim") and mouse_override == null:
		return
	var mp: Vector2 = mouse_override if mouse_override != null else get_viewport().get_mouse_position()
	aim_target = _enemy_under(mp)
	var hit: Vector3
	if aim_target != null:
		hit = aim_target.p
	else:
		var o := cam.project_ray_origin(mp)
		var n := cam.project_ray_normal(mp)
		if absf(n.y) < 0.001:
			return
		hit = o + n * (-o.y / n.y)
	var d := hit - hero_pos
	d.y = 0
	if d.length() > 0.05:
		aim_vec = d.normalized()
		aim_dir = _dir_index(d)
		aim_dist = d.length()


## Враг под курсором (правка 3, раунд 3): точка на его спрайте, из нескольких — ближний к камере.
func _enemy_under(mp: Vector2) -> Variant:
	var best: Variant = null
	var best_y := -INF
	for e in enemies:
		var f := cam.unproject_position(_snap(e.p + Vector3.UP * e.h))
		var hit: bool = e.node.under_mouse(mp) if e.get("kind", "") == "mech" else (absf(mp.x - f.x) <= ENEMY_HIT_W and mp.y <= f.y + 3.0 and mp.y >= f.y - ENEMY_HIT_H)
		if hit and f.y > best_y:
			best = e
			best_y = f.y
	return best


## Пиксель холста слоя корпуса (64x96) -> точка в мире с учётом сдвига корпуса за тазом.
func _anchor_world(pt: Array) -> Vector3:
	var p := _snap(hero_pos + Vector3.UP * hero_h)
	return p + cam.global_basis.x * ((float(pt[0]) - HERO_CANVAS / 2.0 + lift.x) * PX) \
		+ cam.global_basis.y * ((HERO_CANVAS - float(pt[1]) + lift.y - HERO_FEET) * PX)


func _upper_anchor(key: String) -> Array:
	if garm_col >= 0:              # раунд 11: у наведённой руки обреза свои точки
		return meta.aim_arm.shotgun.anchors[meta.dirs[upper_now[2]]][garm_col][key]
	var um: Dictionary = meta.upper[upper_now[0]]
	return um.anchors[meta.dirs[upper_now[2]]][upper_now[1]][key]


func _angle_idx(a: Array, b: Array) -> int:
	return int(round(rad_to_deg(atan2(float(a[1]) - float(b[1]), float(a[0]) - float(b[0]))) / 45.0))


# ---------- ввод ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var k: int = event.physical_keycode
		if not event.pressed:
			if k == KEY_CTRL:
				_ult_release()
			return
		if k == KEY_C:
			crowd.visible = not crowd.visible
		elif k == KEY_F11:
			_toggle_fullscreen()
		elif k == KEY_F1:
			hud.visible = not hud.visible
		elif k == KEY_F2:
			_spawn_mech(hero_pos + aim_vec * 7.0)
		elif k == KEY_F9:
			hero_hp = maxf(hero_hp - 0.1, 0.0)    # отладка датчика здоровья
		elif k == KEY_F10:
			hero_hp = 1.0
		elif k == KEY_Q:
			_next_module()
		elif k == KEY_R:
			_reload()
		elif k == KEY_SHIFT:
			_start_dash()
		elif k == KEY_SPACE:
			_start_jump()
		elif k == KEY_ALT:
			_fire_pistol()
		elif k == KEY_CTRL:
			_ult_press()
		elif TEST_KEYS.has(k) and action == "" and not _busy():
			var n: String = TEST_KEYS[k]
			module = "blade" if n.begins_with("blade") else "sickle"
			gun = ""
			_start_action(n)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_light()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_heavy()


func _next_module() -> void:
	if action != "" or _busy():
		return
	switch_from = module
	switch_t = 0.0
	switch_steamed = false
	module = MODULES[(MODULES.find(module) + 1) % MODULES.size()]
	gun = ""                  # смена модуля прерывает перезарядку обреза, патроны не теряются
	combo_t = 0.0
	if hook == "aim":
		_hook_cancel()


## Герой занят ультой или ударом о землю: новые удары не начинаются.
func _busy() -> bool:
	return slam != "" or ult_t >= 0.0 or hook in ["fly", "pull", "back"]


func _light() -> void:
	if module == "shotgun":
		_fire_shotgun()
	else:
		_request("light")


## ПКМ: после двойного прыжка — удар о землю, пока не на откате; иначе тяжёлая атака.
func _heavy() -> void:
	if airborne and jumps_used >= MAX_JUMPS and slam_cd <= 0.0 and slam == "" and ult_t < 0.0:
		_start_slam()
	elif module == "shotgun":
		_fire_shotgun(true)
	else:
		_request("heavy")

# ---------- удары правым модулем ----------
func _segment_end(d: Dictionary, frame: int) -> int:
	for c in d.get("chain", [0]):
		if int(c) > frame:
			return int(c)
	return int(d.frames)


## Номер отрезка серии, с которого начинается удар: 0 — первый, 1 — второй…
func _segment_index(d: Dictionary, frame: int) -> int:
	var k := 0
	for c in d.get("chain", [0]):
		if int(c) > 0 and int(c) <= frame:
			k += 1
	return k


## Удар по нажатию. Во время удара нажатие запоминается и срабатывает, как только хвост можно обрезать.
## Серии свободные: лёгкие и тяжёлые в любом порядке; тот же тип идёт следующим отрезком.
func _request(kind: String) -> void:
	if _busy() or module == "shotgun":
		return
	if hook == "aim":
		_hook_cancel()
	if action != "":
		act_queued = kind
		act_q_t = COMBO_BUFFER
		return
	_chain_to(kind, combo_t > 0.0)


## chained: удар продолжает серию — быстрый старт и без подброса.
func _chain_to(kind: String, chained: bool) -> void:
	var n: String = _heavy_name() if kind == "heavy" else _light_name()
	var from := 0
	if chained and combo_name == n and combo_start >= 0:
		from = combo_start
	act_finisher = chained and not combo_free
	combo_free = false
	_start_action(n, from, chained)

## В воздухе те же нажатия дают воздушные удары.
func _light_name() -> String:
	return AIR_LIGHT[module] if airborne else LIGHT[module]


func _heavy_name() -> String:
	return AIR_HEAVY[module] if airborne else HEAVY[module]


func _is_air_action() -> bool:
	return action != "" and action.contains("_air_")


func _start_action(n: String, from: int = 0, fast: bool = false) -> void:
	var snd := "swing_heavy" if n.ends_with("heavy") else "swing_light"
	if snd == "swing_heavy" and n.begins_with("sickle"):
		snd = "swing_heavy_sickle"  # у серпа свой тяжёлый взмах (раунд 16)
	if snd == "swing_light" and _segment_index(meta.upper[n], from) == 1:
		snd = "swing_snap"          # второй лёгкий удар серии: резкий короткий взмах (раунд 15)
	sfx.play(snd, -2.0, 0.0)
	# пар у тяжёлого — только на каждый 4–5-й тяжёлый удар, и звук, и облако (раунд 16)
	act_steam = false
	if n.ends_with("heavy"):
		heavy_count += 1
		if heavy_count >= heavy_every:
			heavy_count = 0
			heavy_every = rng.randi_range(4, 5)
			act_steam = true
			sfx.play("steam", -8.0, 0.05)
	_update_aim()
	action = n
	# подбрасывает только тяжёлый, который начинает комбо: не второй удар серии и не завершение лёгкой
	act_launch = n == HEAVY.get(module, "") and from == 0 and not act_finisher
	if _is_air_action():
		hero_vy = minf(hero_vy, AIR_ACT_VY)
	act_finisher = false
	act_frame = _fast_frame(meta.upper[n], from) if fast else from
	act_ms = 0.0
	act_queued = ""
	act_since_hit = -1.0
	combo_t = 0.0
	_aim_segment()
	combat_t = COMBAT_HOLD
	if not act_turn:
		_check_hit(meta.upper[n])


## Быстрый старт: кадр отрезка, с которого до удара остаётся COMBO_WINDUP замаха.
func _fast_frame(u: Dictionary, from: int) -> int:
	var hit := -1
	var end := _segment_end(u, from)
	for h in u.get("hit", []):
		if int(h) >= from and int(h) < end:
			hit = int(h)
			break
	if hit < 0:
		return from
	var total := 0.0
	for f in range(from, hit):
		total += float(u.durations_ms[f])
	if hit == from:
		return from
	var left := float(u.durations_ms[hit - 1])
	var start := hit - 1               # хотя бы один кадр замаха: иначе удар без движения
	for f in range(hit - 2, from - 1, -1):
		left += float(u.durations_ms[f])
		if left > total * COMBO_WINDUP:
			break
		start = f
	return start


## Помощь прицеливания: ближайший к линии курсора враг в угле и в досягаемости удара (раунд 9).
func _assist_target() -> Variant:
	var best: Variant = null
	var best_a := ASSIST_ANGLE
	var reach: float = float(MELEE[action][1]) + ASSIST_REACH
	for e in enemies:
		var to: Vector3 = e.p - hero_pos
		to.y = 0.0
		if to.length() < 0.05 or to.length() > reach or not _height_reaches(e):
			continue
		var a := rad_to_deg(aim_vec.angle_to(to.normalized()))
		if a <= best_a:
			best = e
			best_a = a
	return best


## Каждый отрезок серии бьёт туда, где прицел сейчас.
func _aim_segment() -> void:
	act_dir = aim_dir
	act_end = _segment_end(meta.upper[action], act_frame)
	act_fwd = _dir_vector(act_dir)
	var target: Variant = _assist_target()
	if target != null:
		var to: Vector3 = target.p - hero_pos
		to.y = 0.0
		act_fwd = to.normalized()
		act_dir = _dir_index(to)
	# раунд 12, вариант Г: на бегу удар не дальше 90° от хода — корпус назад не разворачивается
	if loco == "run":
		var ang := _screen_ang(act_fwd)
		var rel := wrapf(ang - legs_tgt, -180.0, 180.0)
		if absf(rel) > ACT_RUN_LIMIT:
			ang = legs_tgt + signf(rel) * ACT_RUN_LIMIT
			act_fwd = _ang_vector(ang)
			act_dir = posmod(int(round(ang / 45.0)), 8)
	act_right = act_fwd.cross(Vector3.UP)   # корпус доворачивается в _process (раунд 11)
	# стоя: шаг-разворот всем телом, удар идёт после него
	act_turn = loco != "run" and not airborne and absf(wrapf(act_dir * 45.0 - upper_ang, -180.0, 180.0)) > 45.0


func _check_hit(d: Dictionary) -> void:
	for h in d.get("hit", []):
		if int(h) == act_frame:
			shake = maxf(shake, SHAKE.get(action, 1.0))
			pending.append("melee")
			act_since_hit = 0.0


func _update_action(delta: float) -> void:
	var u: Dictionary = meta.upper[action]
	if act_turn:
		# шаг-разворот (раунд 12): удар ждёт, пока корпус и ноги не повернутся к цели
		if absf(wrapf(upper_ang - act_dir * 45.0, -180.0, 180.0)) < 2.0:
			act_turn = false
			_check_hit(u)
		else:
			return
	if act_queued != "":
		act_q_t -= delta
		if act_q_t <= 0.0:
			act_queued = ""
	if act_since_hit >= 0.0:
		act_since_hit += delta
		if act_queued != "" and act_since_hit >= COMBO_CANCEL:
			_next_in_combo(u)            # хвост удара обрезается
			return
	act_ms += delta * 1000.0
	while act_ms >= float(u.durations_ms[act_frame]):
		act_ms -= float(u.durations_ms[act_frame])
		var nxt := act_frame + 1
		if nxt >= act_end:
			if act_queued != "":
				_next_in_combo(u)
			else:
				_end_action(u)
			return
		# смещение корпуса из записи: спрайт нарисован на месте; на бегу героя двигают ноги
		if loco == "idle" and not airborne and dash_t < 0.0 and meta.legs.has(action):
			var root: Array = meta.legs[action].root_m
			var r0: Array = root[act_frame]
			var r1: Array = root[nxt]
			hero_pos += act_right * (float(r1[0]) - float(r0[0])) + act_fwd * (float(r1[1]) - float(r0[1]))
		act_frame = nxt
		_check_hit(u)


func _remember_combo(u: Dictionary) -> void:
	combo_name = action
	combo_start = act_end if act_end < int(u.frames) else -1


func _end_action(u: Dictionary) -> void:
	_remember_combo(u)
	action = ""
	aim_free = AIM_FREE
	combat_t = COMBAT_HOLD
	combo_t = COMBO_WINDOW


func _next_in_combo(u: Dictionary) -> void:
	var q := act_queued
	act_queued = ""
	_remember_combo(u)
	action = ""
	_chain_to(q, true)

# ---------- обрез и револьвер ----------
## Выстрел; heavy — залп двумя стволами, 2 патрона. Патронов мало — перезарядка.
func _fire_shotgun(heavy: bool = false) -> void:
	if gun == "reload" or gun == "ult" or slam != "":
		return
	combat_t = COMBAT_HOLD
	var kind := "shoot2" if heavy else "shoot"
	if ammo.shotgun < (2 if heavy else 1):
		_gun_set("reload")
	elif gun == "aim":
		_gun_set(kind)
	elif gun == "" or gun == "lower":
		gun_queued = kind
		_gun_set("raise")
	else:
		gun_queued = kind


func _gun_set(s: String) -> void:
	gun = s
	gun_frame = 0
	gun_ms = 0.0
	if s == "shoot":
		ammo.shotgun -= 1
		shake = maxf(shake, SHAKE.gun_shoot)
		pending.append("shotgun")
	elif s == "shoot2":
		ammo.shotgun -= 2
		shake = maxf(shake, 5.0)
		pending.append("shotgun2")
	elif s == "reload":
		gun_queued = ""


func _update_gun(delta: float) -> void:
	if gun == "":
		return
	if gun == "aim":
		if ammo.shotgun <= 0:
			_gun_set("reload")        # магазин пуст: перезарядка сама
		elif gun_queued != "":
			var q := gun_queued
			gun_queued = ""
			if ammo.shotgun >= (2 if q == "shoot2" else 1):
				_gun_set(q)
		elif combat_t <= 0.0:
			_gun_set("lower")
		return
	var u: Dictionary = meta.upper["gun_" + gun]
	gun_ms += delta * 1000.0
	while gun != "" and gun != "aim" and gun_ms >= float(u.durations_ms[gun_frame]):
		gun_ms -= float(u.durations_ms[gun_frame])
		gun_frame += 1
		if gun == "reload":
			match gun_frame:
				2: pending.append("shotgun_eject")
				4: pending.append("shotgun_charge")
				6: shake = maxf(shake, 1.0)
		elif gun == "ult" and gun_frame == 3:
			pending.append("ult_fire")
			shake = maxf(shake, 6.0)
		if gun_frame >= int(u.frames):
			if gun == "lower":
				gun = ""
			else:
				if gun == "reload":
					ammo.shotgun = MAG.shotgun
					combat_t = COMBAT_HOLD
				_gun_set("aim")
				if gun_queued != "" and ammo.shotgun >= (2 if gun_queued == "shoot2" else 1):
					var q2 := gun_queued
					gun_queued = ""
					_gun_set(q2)


func _fire_pistol() -> void:
	if pistol != 0 or pr_i >= 0:
		return
	if ammo.pistol <= 0:
		sfx.play("dry_fire")
		_reload_pistol()
		return
	ammo.pistol -= 1
	pistol_aim_t = PISTOL_AIM_HOLD   # раунд 11: рука наводится сама, корпус на бегу не разворачивается
	combat_t = COMBAT_HOLD
	pistol = 1
	pistol_ms = 0.0
	shake = maxf(shake, SHAKE.pistol)
	pending.append("pistol")


func _update_pistol(delta: float) -> void:
	if pr_i >= 0:
		_update_pistol_reload(delta)
	if pistol == 0:
		return
	pistol_ms += delta * 1000.0
	var ms: Array = meta.pistol_ms
	while pistol != 0 and pistol_ms >= float(ms[pistol]):
		pistol_ms -= float(ms[pistol])
		pistol = (pistol + 1) % ms.size()
	if pistol == 0 and ammo.pistol <= 0:
		_reload_pistol()              # барабан пуст: перезарядка сама


# ---------- ульты (раунд 6) ----------
func _ult_press() -> void:
	if _busy() or dash_t >= 0.0:
		return
	match module:
		"blade":
			_start_spin()
		"sickle":
			if hook_cd <= 0.0 and not airborne and hook == "":
				hook = "aim"
				action = ""
				act_queued = ""
				combo_t = 0.0
		"shotgun":
			_fire_ult()


func _ult_release() -> void:
	if hook == "aim":
		_hook_fire()


func _start_spin() -> void:
	if spin_cd > 0.0 or airborne:
		return
	ult_t = 0.0
	ult_hit_t = 0.1
	spin_cd = SPIN_CD
	sfx.play("steam_long", -12.0)
	ult_start_dir = aim_dir
	invuln = true
	action = ""
	act_queued = ""
	combo_t = 0.0
	gore.steam(_anchor_world(_upper_anchor("vent" if module == "blade" else "hose_top")), 2)


func _update_spin(delta: float) -> void:
	spin_cd = maxf(spin_cd - delta, 0.0)
	if ult_t < 0.0:
		return
	ult_t += delta
	var d: int = (ult_start_dir + int(maxf(ult_t - SPIN_WIND, 0.0) / SPIN_DIR_T)) % 8
	upper_dir = d
	legs_dir = d
	upper_ang = d * 45.0
	legs_ang = upper_ang
	legs_tgt = upper_ang
	ult_hit_t -= delta
	if ult_hit_t <= 0.0 and ult_t < SPIN_T:
		ult_hit_t = SPIN_HITS
		sfx.play("swing_light", -10.0)
		_spin_hits()
	if ult_t >= SPIN_T:
		ult_t = -1.0
		invuln = false
		upper_ang = aim_dir * 45.0


func _spin_hits() -> void:
	var list: Array = OUTCOMES.spin
	var landed := false
	for e in enemies.duplicate():
		var to: Vector3 = e.p - hero_pos
		to.y = 0.0
		if to.length() <= SPIN_R and _height_reaches(e):
			var dir: Vector3 = to.normalized() if to.length() > 0.05 else aim_vec
			landed = true
			_damage(e, SPIN_DMG, list[rng.randi_range(0, list.size() - 1)], dir, "spin")
			if enemies.has(e) and e.get("kind", "") != "mech" and not _is_air_state(e):
				e.p += dir * SPIN_KNOCK    # задетый отлетает по радиусу
	gore.steam(hero_pos + Vector3.UP * 0.15, 1)    # пыль у ног
	if landed:
		shake = maxf(shake, 2.0)
		gore.flash("pistol", _anchor_world(_upper_anchor("blade_tip")), rng.randi_range(0, 7))   # искры у кончика


## Куда придёт хук: первый враг на линии, иначе точка прицела, не дальше 8 м.
func _hook_probe() -> Array:
	var dir := _hook_aim()
	var len0: float = minf(aim_dist, HOOK_RANGE)
	var best: Variant = null
	var best_d: float = HOOK_RANGE + 1.0
	for e in enemies:
		var to: Vector3 = e.p - hero_pos
		to.y = 0.0
		var along := to.dot(dir)
		if along > 0.0 and along <= HOOK_RANGE and (to - dir * along).length() <= HOOK_WIDTH and along < best_d:
			if along <= len0 + HOOK_WIDTH or e == aim_target or dir != aim_vec:
				best = e
				best_d = along
	return [best, best_d if best != null else len0]


## Ассист крюка (раунд 10): если на линии курсора никого, бросок доворачивает на ближайшего к линии
## врага не дальше HOOK_ASSIST от неё и в дальности крюка. Иначе летит прямо в курсор.
func _hook_aim() -> Vector3:
	var best: Variant = null
	var best_a := HOOK_ASSIST
	for e in enemies:
		var to: Vector3 = e.p - hero_pos
		to.y = 0.0
		if to.length() < 0.3 or to.length() > HOOK_RANGE or float(e.h) > AIR_REACH + 0.2:
			continue
		var along := to.dot(aim_vec)
		if along > 0.0 and (to - aim_vec * along).length() <= HOOK_WIDTH:
			return aim_vec              # кто-то уже на линии: доворот не нужен
		var a := rad_to_deg(aim_vec.angle_to(to.normalized()))
		if a <= best_a:
			best = e
			best_a = a
	if best == null:
		return aim_vec
	var t: Vector3 = best.p - hero_pos
	t.y = 0.0
	return t.normalized()


func _hook_cancel() -> void:
	hook = ""
	_hide_chain()


func _hook_fire() -> void:
	if airborne:
		_hook_cancel()
		return
	var probe := _hook_probe()
	hook = "fly"
	hook_t = 0.0
	hook_cd = HOOK_CD
	sfx.play("chain_throw", -4.0)
	hook_dir = _hook_aim()
	hook_len = minf(float(probe[1]) + HOOK_WIDTH, HOOK_RANGE)
	hook_dist = 0.0
	hook_target = null


func _update_hook(delta: float) -> void:
	hook_cd = maxf(hook_cd - delta, 0.0)
	if hook == "":
		return
	hook_t += delta
	match hook:
		"aim":
			if airborne:
				_hook_cancel()
				return
		"fly":
			hook_dist += HOOK_V * delta
			var tip := hero_pos + hook_dir * hook_dist
			for e in enemies.duplicate():
				var to: Vector3 = e.p - tip
				to.y = 0.0
				if to.length() <= HOOK_WIDTH:
					_hook_catch(e)
					return
			if hook_dist >= hook_len:
				hook = "back"
				hook_t = 0.0
		"pull":
			var e: Dictionary = hook_target
			if not enemies.has(e):
				hook = "back"
				hook_t = 0.0
				return
			var u := minf(hook_t / HOOK_PULL_T, 1.0)
			var to: Vector3 = e.p - hero_pos
			to.y = 0.0
			var dir := to.normalized() if to.length() > 0.05 else hook_dir
			# цепь натягивается: сперва медленно, потом рывком
			e.p = hero_pos + dir * lerpf(hook_from.x, 1.0, u * u)
			e.h = lerpf(hook_from.y, 0.0, u)
			hook_dist = (e.p - hero_pos).length()
			e.state = "hooked"
			e.hook_f = 1 if u > 0.65 else 0   # споткнулся на финише
			e.t = 0.0
			if u >= 1.0:
				e.h = 0.0
				e.vy = 0.0
				e.state = "flinch"
				e.t = FLINCH_T - HOOK_STUN
				hook_target = null
				hook = ""
				_hide_chain()
				shake = maxf(shake, 2.0)
				gore.steam(e.p + Vector3.UP * 0.2, 1)
				combo_t = HOOK_FREE       # первый удар по притянутому без замаха
				sfx.play("body_fall", -4.0)
				combo_name = ""
				combo_free = true
		"back":
			hook_dist -= HOOK_BACK_V * delta
			if hook_dist <= 0.0:
				hook = ""
				_hide_chain()


func _hook_catch(e: Dictionary) -> void:
	sfx.play("chain", -8.0)
	_damage(e, 1, "stab", hook_dir, "hook")
	shake = maxf(shake, 3.0)
	gore.flash("pistol", _snap(e.p + Vector3.UP * (float(e.h) + 1.0)), rng.randi_range(0, 7))   # искра от лезвия
	if not enemies.has(e) or e.get("kind", "") == "mech":
		hook = "back"             # цель умерла: цепь возвращается пустой
		hook_t = 0.0
		return
	hook = "pull"
	hook_t = 0.0
	hook_target = e
	var to: Vector3 = e.p - hero_pos
	to.y = 0.0
	hook_dist = to.length()
	hook_from = Vector3(hook_dist, float(e.h), 0.0)     # откуда тянем: расстояние и высота


func _hide_chain() -> void:
	chain.multimesh.visible_instance_count = 0
	hook_tip.visible = false
	hook_ghost.visible = false


## Цепь и лезвие. В прицеле — пунктир до точки, лезвие там, где окажется, и отметка на полу; красная, если на линии враг.
func _draw_chain() -> void:
	if hook == "":
		return
	var hand := _anchor_world(_upper_anchor("sickle_base"))
	var dir := hook_dir
	var dist := hook_dist
	var tip_h := 0.9
	var hit := false
	if hook == "aim":
		var probe := _hook_probe()
		dir = _hook_aim()           # пунктир сам доворачивает на цель ассиста и краснеет
		dist = float(probe[1])
		hit = probe[0] != null
	if hook == "pull" and enemies.has(hook_target):
		var to: Vector3 = hook_target.p - hero_pos
		to.y = 0.0
		dir = to.normalized() if to.length() > 0.05 else dir
		dist = to.length()
		hit = true
	var tip := hero_pos + dir * dist + Vector3.UP * tip_h
	var dotted := hook == "aim"
	var flying := hook == "fly" or hook == "back"
	var sag: float = HOOK_SAG * dist / HOOK_RANGE if flying else 0.0   # на притяжении натянута
	var mm := chain.multimesh
	var n: int = mini(int(hand.distance_to(tip) / HOOK_LINK), HOOK_MAX_LINKS)
	var dark := Color("4a4558")
	var light := Color("c4bfcc")
	var aim_col := Color("e02a3c") if hit else Color("e0b84a")
	var count := 0
	for i in n:
		if dotted and i % 3 != 0:
			continue
		var f: float = float(i) / maxi(n, 1)
		var p: Vector3 = hand.lerp(tip, f) + Vector3.DOWN * sag * sin(PI * f)
		mm.set_instance_transform(count, Transform3D(Basis(), _snap(p) + cam.global_basis.z * 0.4))
		var col := aim_col if dotted else (light if i % 2 == 0 else dark)
		if flying and n - i <= 6:
			col = Color("ece8ee")     # след у лезвия
		mm.set_instance_color(count, col)
		count += 1
	mm.visible_instance_count = count
	hook_tip.visible = true
	var ang := rad_to_deg(atan2(dir.dot(Basis(Vector3.UP, deg_to_rad(YAW)) * Vector3.BACK) * 0.5, dir.dot(Basis(Vector3.UP, deg_to_rad(YAW)) * Vector3.RIGHT)))
	hook_tip.frame = int(hook_t * 40.0) % 8 if flying else posmod(int(round(ang / 45.0)), 8)   # в полёте вращается
	hook_tip.global_position = _snap(tip) + cam.global_basis.z * 0.5
	hook_ghost.visible = dotted
	if dotted:
		hook_ghost.global_position = _snap(hero_pos + dir * dist) - cam.global_basis.z * 0.02


## Поджигающий выстрел: широкий конус без трат патронов, в воздухе тоже.
func _fire_ult() -> void:
	if fire_cd > 0.0 or gun == "reload":
		return
	fire_cd = FIRE_CD
	combat_t = COMBAT_HOLD
	gun_queued = ""
	_gun_set("ult")


func _fire_hits() -> void:
	for e in enemies.duplicate():
		if _in_cone(e, _shot_vec(), FIRE_R, FIRE_HALF):
			_damage(e, FIRE_DMG, "burn", _shot_vec(), "fire")
			if enemies.has(e):
				_ignite(e, BURN_T, true)


func _ignite(e: Dictionary, t: float, spreads: bool) -> void:
	if e.get("kind", "") == "mech":
		e.node.ignite()
		return
	if float(e.burn) < t:
		e.burn = t
		e.burn_spread = spreads
	e.burn_tick = BURN_TICK
	e.charred = true
	if e.flame == null:
		var f := gore.flame_sprite()
		e.flame = f


func _update_burn(e: Dictionary, delta: float) -> void:
	if float(e.burn) <= 0.0:
		return
	e.burn -= delta
	e.burn_tick -= delta
	if float(e.burn_tick) <= 0.0:
		e.burn_tick = BURN_TICK
		e.hp -= BURN_DMG                # огонь не вызывает реакции: враг продолжает идти
		if bool(e.burn_spread):
			for o in enemies:
				if o != e and float(o.burn) <= 0.0:
					var d: Vector3 = o.p - e.p
					d.y = 0.0
					if d.length() <= BURN_SPREAD_R:
						_ignite(o, BURN_T_SPREAD, false)
		if int(e.hp) <= 0:
			_kill(e, "burn", (e.p - hero_pos).normalized())
			return
	if float(e.burn) <= 0.0 and e.flame != null:
		e.flame.queue_free()
		e.flame = null


# ---------- перезарядка (правка 6, раунд 3): запас патронов пока бесконечный ----------
func _reload() -> void:
	_reload_pistol()
	if module == "shotgun" and gun != "reload" and ammo.shotgun < MAG.shotgun:
		_gun_set("reload")


func _reload_pistol() -> void:
	if pr_i < 0 and pistol == 0 and ammo.pistol < MAG.pistol:
		pr_i = 0
		pr_ms = 0.0
		sfx.play("revolver_reload", -2.0)


func _update_pistol_reload(delta: float) -> void:
	var r: Dictionary = meta.pistol_reload
	pr_ms += delta * 1000.0
	while pr_i >= 0 and pr_ms >= float(r.ms[pr_i]):
		pr_ms -= float(r.ms[pr_i])
		pr_i += 1
		if pr_i == 1:
			pending.append("pistol_eject")
		if pr_i >= r.ms.size():
			pr_i = -1
			ammo.pistol = MAG.pistol


# ---------- рывок и прыжок (правка 8, раунд 3) ----------
func _input_vec() -> Vector2:
	if inp_override != null:
		return inp_override
	if demo.has("move"):
		return Vector2(1, 1)
	return Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))


func _world_dir(inp: Vector2) -> Vector3:
	var yb := Basis(Vector3.UP, deg_to_rad(YAW))
	return ((yb * Vector3.RIGHT) * inp.x + (yb * Vector3.BACK) * inp.y).normalized()


## Рывок по направлению ввода, без ввода — к прицелу. Удар и стрельбу не прерывает: ноги в рывке, корпус своё.
## Два заряда подряд, потом откат 2 с; второй ждёт 0,8 с, потом откат начинается всё равно.
## Нажатие во время рывка запоминается. В воздухе рывок короче, на это время падение останавливается.
func _start_dash() -> void:
	if dash_t >= 0.0:
		dash_queued = dash_used == 1
		return
	if dash_cd > 0.0 or _busy():
		return
	if hook == "aim":
		_hook_cancel()
	if airborne:
		hero_vy = 0.0
	if dash_used == 1:
		dash_gap = 0.0 if dash_queued else DASH_WINDOW - dash_window
	dash_used += 1
	dash_spent = mini(dash_spent + 1, 2)
	dash_queued = false
	dash_speed = (DASH_DIST_AIR if airborne else DASH_DIST) / DASH_TIME
	var inp := _input_vec()
	dash_vec = aim_vec if inp == Vector2.ZERO else _world_dir(inp)
	dash_t = 0.0
	invuln = true
	var i := _dir_index(dash_vec)
	legs_ang = i * 45.0
	legs_tgt = legs_ang
	legs_dir = i
	if action == "" and gun == "":
		upper_ang = legs_ang
		upper_dir = i
	pending.append("dash")


func _update_dash(delta: float) -> void:
	dash_cd = maxf(dash_cd - delta, 0.0)
	if dash_cd <= 0.0 and dash_used == 0 and dash_t < 0.0:
		dash_spent = 0                # откат прошёл: тумблеры поднимаются
	if dash_t < 0.0:
		if dash_used == 1:
			dash_window -= delta
			if dash_window <= 0.0:
				dash_used = 0
				dash_cd = DASH_CD_MIN
		return
	var left := minf(delta, DASH_TIME - dash_t)
	hero_pos += dash_vec * dash_speed * left
	dash_t += delta
	if dash_t >= DASH_TIME:
		dash_t = -1.0
		invuln = false
		if dash_used >= 2:
			dash_used = 0
			dash_cd = _dash_cooldown(dash_gap)
		else:
			dash_window = DASH_WINDOW
			if dash_queued:
				_start_dash()

## Откат зависит от паузы между рывками: подряд — полный, чем дольше ждал, тем короче (раунд 8).
func _dash_cooldown(gap: float) -> float:
	if gap <= DASH_GAP_FAST:
		return DASH_CD
	return lerpf(DASH_CD, DASH_CD_MIN, (gap - DASH_GAP_FAST) / (DASH_WINDOW - DASH_GAP_FAST))


# ---------- удар о землю (правка 5, раунд 5) ----------
## Только после двойного прыжка: герой падает вниз и бьёт при приземлении. Откат 3 с, неуязвим на всё время удара.
func _start_slam() -> void:
	if not airborne or jumps_used < MAX_JUMPS or _busy() or slam_cd > 0.0 or dash_t >= 0.0:
		return
	slam = "fall"
	slam_frame = 0
	slam_ms = 0.0
	hero_vy = -SLAM_V
	invuln = true
	action = ""
	act_queued = ""
	combo_t = 0.0
	gun = ""
	_update_aim()
	var i := aim_dir
	legs_ang = i * 45.0
	legs_tgt = legs_ang
	legs_dir = i
	upper_ang = legs_ang
	upper_dir = i


func _slam_sheet() -> Dictionary:
	return meta.upper["slam_" + module]


func _update_slam(delta: float) -> void:
	slam_cd = maxf(slam_cd - delta, 0.0)
	if slam == "":
		return
	var u := _slam_sheet()
	slam_ms += delta * 1000.0
	var last_fall := int(u.impact) - 1
	while slam != "" and slam_ms >= float(u.durations_ms[slam_frame]):
		if slam == "fall" and slam_frame >= last_fall:
			slam_ms = 0.0                   # кадр падения держится до пола
			break
		slam_ms -= float(u.durations_ms[slam_frame])
		slam_frame += 1
		if slam_frame >= int(u.frames):
			slam = ""
			invuln = false


func _slam_impact() -> void:
	slam = "impact"
	slam_frame = int(_slam_sheet().impact)
	slam_ms = 0.0
	slam_cd = SLAM_CD
	shake = maxf(shake, 6.0)
	pending.append("slam")
	_hitstop(0.08)


func _slam_hits() -> void:
	if module == "shotgun":
		for e in enemies.duplicate():
			if _in_cone(e, aim_vec, SLAM_GUN[0], SLAM_GUN[1]):
				var d: float = Vector3(e.p.x - hero_pos.x, 0.0, e.p.z - hero_pos.z).length()
				for zone in SLAM_GUN_ZONES:
					if d <= float(zone[0]):
						_damage(e, int(zone[1]), zone[2], aim_vec, "slam")
						break
				_stun(e)
		return
	var w: Array = SLAM[module]
	for e in enemies.duplicate():
		var to: Vector3 = e.p - hero_pos
		to.y = 0.0
		var d := to.length()
		if d <= w[0]:
			var dmg := int(round(lerpf(w[1], w[2], d / w[0])))
			# раздавить можно только клинком и вплотную
			var o: String = "crush" if module == "blade" and d < 1.0 else w[3]
			_damage(e, dmg, o, to.normalized() if d > 0.05 else aim_vec, "slam")
			_stun(e)


## Стан: на земле стоит STUN секунд; висящего сбрасывает, стан он получает при падении.
func _stun(e: Dictionary) -> void:
	if e.get("kind", "") == "mech":
		return
	if not enemies.has(e):
		return
	if _is_air_state(e):
		e.state = "air_fall"
		e.vy = minf(e.vy, -SPIKE_V * 0.6)
		e.t = 0.0
	else:
		e.state = "flinch"
		e.t = FLINCH_T - STUN

## Прыжок: ноги в своей анимации, корпус продолжает целиться и бить; подъём задаёт движок.
## Второй нажатием в воздухе — ещё один толчок. Прыжок отменяет возврат наземного удара после попадания.
func _start_jump() -> void:
	if dash_t >= 0.0 or jumps_used >= MAX_JUMPS or _busy():
		return
	if hook == "aim":
		_hook_cancel()
	if airborne:
		pending.append("double_jump")
	elif action != "" and _past_last_hit():
		action = ""
		act_queued = ""
		combo_t = 0.0
	if not airborne:
		takeoff_t = 0.0
		sfx.play("jump", -8.0)
	jumps_used += 1
	airborne = true
	hero_vy = JUMP_V


func _past_last_hit() -> bool:
	var u: Dictionary = meta.upper[action]
	var last := -1
	for h in u.get("hit", []):
		if int(h) < act_end:
			last = int(h)
	return act_frame > last


func _update_jump(delta: float) -> void:
	if not airborne:
		hero_h = 0.0
		return
	if dash_t >= 0.0:
		return                         # в воздушном рывке падение остановлено
	hero_vy -= HERO_G * (AIR_ACT_G if _is_air_action() and hero_vy <= 0.0 else 1.0) * delta   # медленнее только снижение
	hero_h += hero_vy * delta
	if hero_h <= 0.0:
		hero_h = 0.0
		hero_vy = 0.0
		airborne = false
		jumps_used = 0
		shake = maxf(shake, 1.0)      # приземление
		if slam == "fall":
			_slam_impact()
		else:
			land_t = 0.0
			sfx.play("land", -3.0)
			gore.steam(hero_pos + Vector3.UP * 0.1, 1)   # пыль
		if _is_air_action():
			action = ""
			act_queued = ""
		combo_t = 0.0


## Кадр листа прыжка по вертикальной скорости: толчок, вершина, снижение. Второй прыжок играет его заново.
func _jump_frame() -> int:
	var n := int(meta.legs.jump.frames)
	return clampi(int((JUMP_V - hero_vy) / (2.0 * JUMP_V) * n), 0, n - 1)

# ---------- эффекты событий ----------
func _fx_events() -> void:
	for ev in pending:
		match ev:
			"shotgun":
				sfx.play("shotgun")
				sfx.play("shell", -4.0, 0.4)
				var m := _upper_anchor("muzzle")
				gore.flash("shotgun", _anchor_world(m), posmod(_angle_idx(m, _upper_anchor("breech")), 8))
				var right := aim_vec.cross(Vector3.UP)
				gore.shell(_anchor_world(_upper_anchor("eject")), _shell_v(right))
				gore.steam(_anchor_world(_upper_anchor("hose_top")), 2)
				_shotgun_hits()
			"pistol":
				sfx.play("revolver")
				var am: Dictionary = meta.arm[meta.upper[upper_now[0]].src]
				var a: Dictionary = am.anchors[meta.dirs[upper_now[2]]][upper_now[1]]
				if parm_col >= 0:       # раунд 11: дуло наведённой руки
					a = meta.aim_arm.pistol.anchors[meta.dirs[upper_now[2]]][parm_col]
				gore.flash("pistol", _anchor_world(a.pmuzzle), posmod(_angle_idx(a.pmuzzle, a.pbreech), 8))
				_pistol_hit()
			"shotgun2":
				sfx.play("shotgun_double")
				sfx.play("shell", -4.0, 0.4)
				sfx.play("shell", -6.0, 0.55)
				var m2 := _upper_anchor("muzzle")
				var mw := _anchor_world(m2)
				var ai := posmod(_angle_idx(m2, _upper_anchor("breech")), 8)
				gore.flash("shotgun", mw, ai)
				gore.flash("shotgun", mw + cam.global_basis.x * 6.0 * PX, ai)
				var right2 := aim_vec.cross(Vector3.UP)
				for i in 2:
					gore.shell(_anchor_world(_upper_anchor("eject")), _shell_v(right2))
				gore.steam(_anchor_world(_upper_anchor("hose_top")), 3)
				if not airborne:
					hero_pos -= _shot_vec() * 0.25       # отдача двух стволов
				_shotgun_hits(true)
			"ult_fire":
				sfx.play("shotgun", -4.0)       # ульты тише (раунд 14)
				sfx.play("fire_burst", -7.0)
				var m3 := _upper_anchor("muzzle")
				gore.flash("shotgun", _anchor_world(m3), posmod(_angle_idx(m3, _upper_anchor("breech")), 8))
				gore.fire(_snap(hero_pos), _dir_index(_shot_vec()))
				gore.steam(_anchor_world(_upper_anchor("hose_top")), 2)
				_fire_hits()
			"shotgun_eject":
				sfx.play("shotgun_reload")
				sfx.play("shell", -6.0, 0.35)
				var right := aim_vec.cross(Vector3.UP)
				for i in MAG.shotgun - ammo.shotgun:
					gore.shell(_anchor_world(_upper_anchor("eject")), _shell_v(right))
				gore.steam(_anchor_world(_upper_anchor("eject")), 2)
			"shotgun_charge":
				sfx.play("steam", -6.0)       # пар тише (раунд 15)
				gore.steam(_anchor_world(_upper_anchor("hose_top")), 3)
			"pistol_eject":
				sfx.play("shell", -8.0, 0.3)
				var am2: Dictionary = meta.arm[meta.upper[upper_now[0]].src]
				var a2: Dictionary = am2.anchors[meta.dirs[upper_now[2]]][upper_now[1]]
				for i in 3:
					gore.shell(_anchor_world(a2.pbreech), Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.4, 1.2), rng.randf_range(-0.5, 0.5)))
			"slam":
				sfx.play("slam")
				if module == "shotgun":
					sfx.play("shotgun_double", -2.0)
				_slam_fx()
				_slam_hits()
			"switch_steam":
				sfx.play("switch_module", -5.0)
				gore.steam(_anchor_world(_upper_anchor("hose_top")) + cam.global_basis.y * -22.0 * PX, 2)
			"double_jump":
				sfx.play("jump", -10.0)        # обычный толчок и лёгкий пар (раунд 16)
				sfx.play("steam_puff", -12.0)
				gore.steam(_snap(hero_pos + Vector3.UP * hero_h), 3)
			"dash":
				sfx.play("dash", -3.0)
				gore.steam(_anchor_world(_upper_anchor("hose_top")), 3)
				gore.steam(hero_pos + Vector3.UP * 0.2, 3)
			"melee":
				if action.ends_with("heavy"):
					if act_steam:
						gore.steam(_anchor_world(_upper_anchor("vent" if module == "blade" else "hose_top")), 3)
					if act_end >= int(meta.upper[action].frames) and meta.upper[action].chain.size() > 1:
						shake = maxf(shake, 5.0)     # завершающий удар серии
				_melee_hits()
	pending.clear()


## Гильзы падают рядом с героем (раунд 12): вбок 0,3–0,6 м/с, вверх 1,2–1,6 м/с.
func _shell_v(right: Vector3) -> Vector3:
	return right * rng.randf_range(0.3, 0.6) + Vector3.UP * rng.randf_range(1.2, 1.6) \
		+ Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))


## Волна, трещины, пар; у обреза вспышка и направленный залп, гильзы.
func _slam_fx() -> void:
	var at := _snap(hero_pos)
	if module == "shotgun":
		gore.blast(at, aim_dir)
		gore.crack(hero_pos + aim_vec * 0.8, "m")
		var m := _upper_anchor("muzzle")
		gore.flash("shotgun", _anchor_world(m), posmod(_angle_idx(m, _upper_anchor("breech")), 8))
		var right := aim_vec.cross(Vector3.UP)
		for i in 3:
			gore.shell(_anchor_world(_upper_anchor("eject")), _shell_v(right))
	else:
		gore.shock(at, module)
		gore.crack(hero_pos + aim_vec * 0.5, "l" if module == "blade" else "m")
	gore.steam(_anchor_world(_upper_anchor("hose_top")), 1)


# ---------- противники ----------
func _spawn_enemy(at: Variant = null) -> void:
	var p: Vector3
	if at == null:
		var ang := rng.randf() * TAU
		p = hero_pos + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(5.0, 8.5)
	else:
		p = at
	var s := _make_sprite()
	add_child(s)
	var sh := _make_shadow()
	add_child(sh)
	enemies.append({"node": s, "shadow": sh, "p": p, "h": 0.0, "vy": 0.0, "hp": ENEMY_HP, "dir": _dir_index(hero_pos - p),
		"state": "walk", "t": 0.0, "hits": 0, "spiked": false, "immune": 0.0, "burn": 0.0, "burn_tick": 0.0, "burn_spread": false,
		"charred": false, "flame": null, "hook_f": 0})


func _is_air_state(e: Dictionary) -> bool:
	return e.state.begins_with("air_")


## Подброс: удар наносит полный урон; выживший летит по дуге, удары подбивают его снова.
func _launch(e: Dictionary, dmg: int, dir: Vector3, outcome: String = "intact") -> void:
	if e.get("kind", "") == "mech":
		_damage(e, dmg, outcome, dir, action)
		return
	if dmg > 0:
		sfx.play("slash")             # подброс тоже попадание (раунд 13)
	e.hp -= dmg
	if int(e.hp) <= 0:
		_kill(e, outcome, dir)
		return
	e.state = "air_rise"
	e.t = 0.0
	e.vy = LAUNCH_V
	e.hits = 0
	gore.spray(e.p + Vector3.UP * 1.1, dir + Vector3.UP, 40, 4.0)
	gore.spray(e.p + Vector3.UP * 0.8, Vector3.UP, 20, 3.0)
	gore.decal(e.p, "m")


## Попадание по врагу в воздухе: короткий толчок вверх, но не больше HANG_HITS ударов.
func _air_hit(e: Dictionary, dir: Vector3) -> void:
	e.hits += 1
	e.p += dir * 0.05
	e.t = 0.0
	if int(e.hits) >= HANG_HITS:
		e.vy = minf(e.vy, 0.0)
		e.state = "air_fall"
		return
	e.vy = JUGGLE_V if e.h < JUGGLE_MAX_H else 0.0
	e.state = "air_hit"


## Настоящая дуга: состояние только выбирает кадры по скорости; плоского зависания нет.
func _update_air_enemy(e: Dictionary, delta: float) -> void:
	e.vy -= (ENEMY_G if e.vy > 0.0 else ENEMY_FALL_G) * delta
	e.h += e.vy * delta
	if e.h <= 0.0 and e.vy <= 0.0:
		_land_enemy(e)
		return
	if e.state == "air_hit" and e.t <= 0.19:
		return
	if e.vy > AIR_V_HANG:
		e.state = "air_rise"
	elif e.vy < -AIR_V_HANG:
		e.state = "air_fall"
	else:
		e.state = "air_hang"

func _land_enemy(e: Dictionary) -> void:
	e.h = 0.0
	e.vy = 0.0
	e.immune = LAUNCH_IMMUNE    # иначе подбрасывать можно бесконечно
	e.state = "flinch"
	e.t = -0.35                 # дольше обычной реакции: лежал и поднимается
	gore.spray(e.p + Vector3.UP * 0.4, Vector3.UP, 16, 2.5)
	shake = maxf(shake, 1.0)
	if e.spiked:
		e.spiked = false
		shake = maxf(shake, 3.0)
		gore.decal(e.p, "m")
		e.hp -= SPIKE_DMG
		if e.hp <= 0:
			_kill(e, "gut", Vector3.DOWN)


## Шаги NPC слышны только у ближайших идущих в пределах NPC_STEP_RANGE (раунд 15).
func _step_listeners() -> Array:
	var near := []
	for e in enemies:
		if e.get("kind", "") != "mech" and e.state == "walk" and float(e.h) < 0.05:
			var d: float = (e.p - hero_pos).length()
			if d <= NPC_STEP_RANGE:
				near.append([d, e])
	near.sort_custom(func(a, b): return a[0] < b[0])
	return near.slice(0, NPC_STEP_MAX).map(func(x): return x[1])


func _update_enemies(delta: float) -> void:
	var hear := _step_listeners()
	for e in enemies.duplicate():
		if e.get("kind", "") == "mech":
			continue
		var to: Vector3 = hero_pos - e.p
		to.y = 0
		e.t += delta
		e.immune = maxf(float(e.immune) - delta, 0.0)
		_update_burn(e, delta)
		if not enemies.has(e):
			continue
		if _is_air_state(e):
			_update_air_enemy(e, delta)
			if not enemies.has(e):
				continue
		e.dir = _dir_index(to)
		if _is_air_state(e):
			pass                    # в воздухе беспомощен: не идёт и не толкается
		elif e.state == "hooked":
			pass                    # его волочит цепь
		elif e.state == "flinch":
			if e.t > 0.21:
				e.state = "walk"
				e.t = 0.0
		elif to.length() > 1.3:
			e.state = "walk"
			e.p += to.normalized() * float(emeta.walk_speed) * delta
		else:
			e.state = "idle"
		if not _is_air_state(e) and e.state != "hooked":
			for o in enemies:                               # не стоять друг в друге
				if o != e and not _is_air_state(o):
					var d: Vector3 = e.p - o.p
					if d.length() < 0.6 and d.length() > 0.001:
						e.p += d.normalized() * (0.6 - d.length()) * 0.5
		var air := _is_air_state(e)
		var lm: Dictionary = emeta.air[e.state] if air else emeta.live[e.state]
		var frames := int(lm.frames)
		var f := 0
		if e.state == "walk":
			f = int(e.t * 10.0) % 8
		elif e.state == "flinch":
			f = 0 if e.t < 0.09 else 1
		elif e.state == "hooked":
			f = int(e.hook_f)
		elif air:
			var total := 0.0
			for ms in lm.durations_ms:
				total += float(ms)
			var ms_now: float = e.t * 1000.0
			if e.state == "air_rise" or e.state == "air_hit":
				ms_now = minf(ms_now, total - 1.0)     # реакция держит последний кадр
			else:
				ms_now = fposmod(ms_now, total)
			for i in frames:
				if ms_now < float(lm.durations_ms[i]):
					f = i
					break
				ms_now -= float(lm.durations_ms[i])
		# шаг NPC: нога встаёт на кадрах 0 и 4 цикла ходьбы; глуше героя и тише с расстоянием
		var sf := f if e.state == "walk" else -1
		if sf != int(e.get("step_f", -1)) and (sf == 0 or sf == 4) and hear.has(e):
			var d: float = (e.p - hero_pos).length()
			sfx.play("npc_step", NPC_STEP_DB - 12.0 * d / NPC_STEP_RANGE)
		e["step_f"] = sf
		_show(e.node, "res://assets/enemy/E_%s%s.png" % [e.state, "_s" if bool(e.charred) else ""], frames, e.dir, f)
		e.node.offset = Vector2(0, ENEMY_AIR_FEET if air else SPRITE_FEET)
		e.node.global_position = _snap(e.p + Vector3.UP * e.h)
		e.shadow.visible = e.h > 0.05
		e.shadow.global_position = _snap(e.p) - cam.global_basis.z * 0.02
		if e.flame != null:
			e.flame.frame = int(Time.get_ticks_msec() / 70) % 6
			e.flame.global_position = _snap(e.p + Vector3.UP * e.h) + cam.global_basis.z * 0.05
	for i in range(respawn.size() - 1, -1, -1):
		respawn[i] -= delta
		if respawn[i] <= 0.0:
			respawn.remove_at(i)
			_spawn_enemy()


func _in_cone(e: Dictionary, fwd: Vector3, rng_m: float, half: float) -> bool:
	var to: Vector3 = e.p - hero_pos
	to.y = 0
	return to.length() <= rng_m and (to.length() < 0.3 or rad_to_deg(fwd.angle_to(to.normalized())) <= half)


func _melee_hits() -> void:
	if action == "":
		return                     # удар сбросили в том же кадре: прыжок, удар о землю
	var w: Array = MELEE[action]
	var launch := act_launch
	act_launch = false
	# сбрасывает последний удар воздушной тяжёлой серии: у клинка единственный, у серпа второй
	var spike: bool = action in SPIKE_ACTIONS and act_end >= int(meta.upper[action].frames)
	var landed := false
	for e in enemies.duplicate():
		if _in_cone(e, act_fwd, w[1], w[2]) and _height_reaches(e):
			landed = true
			var list: Array = OUTCOMES[action]
			var outcome: String = list[rng.randi_range(0, list.size() - 1)]
			if launch and not _is_air_state(e) and float(e.immune) <= 0.0:
				_launch(e, int(w[0]), act_fwd, outcome)
				continue
			_damage(e, int(w[0]), outcome, act_fwd, action)
			if spike and enemies.has(e) and _is_air_state(e):
				e.state = "air_fall"
				e.vy = -SPIKE_V
				e.spiked = true
	if landed and airborne:
		hero_vy = maxf(hero_vy, AIR_HIT_VY)     # попадание подхватывает героя


## Дробь веером: урон по зонам дальности, толчок назад, отдельные дробины (раунд 10).
func _shotgun_hits(double: bool = false, sv: Vector3 = Vector3.ZERO) -> void:
	if sv == Vector3.ZERO:
		sv = _shot_vec()
	var half: float = SHOOT2_CONE if double else SHOTGUN_CONE
	var rng_m: float = SHOOT2_RANGE if double else SHOTGUN_RANGE
	for e in enemies.duplicate():
		if _in_cone(e, sv, rng_m, half):
			var to := Vector3(e.p.x - hero_pos.x, 0.0, e.p.z - hero_pos.z)
			var dist: float = to.length()
			var zone: int = 0 if dist <= SHOTGUN_CLOSE else (1 if dist <= SHOTGUN_MID else 2)
			var table: Array = SHOOT2_DMG if double else SHOTGUN_DMG
			var push: Vector3 = to.normalized() if dist > 0.05 else sv
			_damage(e, int(table[zone]), "blast" if zone == 0 else "intact", push, "shotgun_double" if double else "shotgun")
			gore.smoke(_snap(e.p + Vector3.UP * (1.2 + float(e.h))), Vector3.ZERO, 1)   # дымок на задетом
			if enemies.has(e) and e.get("kind", "") != "mech" and not _is_air_state(e):
				e.p += push * float(SHOTGUN_KNOCK[zone]) * (1.5 if double else 1.0)   # дробь отталкивает
	# раунд 12: дроби и трассеров нет — пороховой дым перед дулом
	gore.smoke(_anchor_world(_upper_anchor("muzzle")), sv, 4 if double else 3)


func _pistol_hit(sv: Vector3 = Vector3.ZERO) -> void:
	if sv == Vector3.ZERO:
		sv = _shot_vec()
	var best: Variant = null
	# враг под курсором получает пулю сам, если достаёт дальность и выстрел не прижат пределом
	if aim_target != null and enemies.has(aim_target) and (aim_target.p - hero_pos).length() <= PISTOL_RANGE and sv.angle_to(aim_vec) < 0.02:
		_damage(aim_target, 1, "decap", sv, "pistol")
		return
	for e in enemies:
		if _in_cone(e, sv, PISTOL_RANGE, PISTOL_CONE):
			if best == null or (e.p - hero_pos).length() < (best.p - hero_pos).length():
				best = e
	if best != null:
		_damage(best, 1, "decap", sv, "pistol")


func _damage(e: Dictionary, dmg: int, outcome: String, dir: Vector3, kind: String = "") -> void:
	if e.get("kind", "") == "mech":
		e.node.hurt(dmg, outcome, dir, kind)
		return
	e.hp -= dmg
	var chest: Vector3 = e.p + Vector3.UP * (1.25 + float(e.h))
	if outcome != "burn":
		sfx.play("slash" if outcome in ["decap", "split", "waist", "stab", "gut", "arm_off_r", "arm_off_l", "leg_off"] else "hit")
	if e.hp > 0:
		if _is_air_state(e):
			_air_hit(e, dir)
		else:
			e.state = "flinch"
			e.t = 0.0
			e.p += dir * 0.15
		gore.spray(chest, dir, 18, 3.0)
		if rng.randf() < 0.5:
			gore.decal(e.p + dir * 0.4, "s")
		return
	_kill(e, outcome, dir)


## Смерть: труп по исходу, отлетающие куски, кровь по линии удара, хит-стоп.
func _kill(e: Dictionary, outcome: String, dir: Vector3) -> void:
	if e.get("kind", "") == "mech":
		e.node.die(outcome == "decap", dir, true)
		return
	sfx.play("gore")
	if outcome in ["split", "waist", "decap", "blast", "leg_off"]:
		sfx.play("bone", -3.0)
	sfx.play("body_fall", -4.0, 0.45 if float(e.h) < 0.05 else 0.7)
	enemies.erase(e)
	e.node.queue_free()
	e.shadow.queue_free()
	if e.flame != null:
		e.flame.queue_free()
	if hook_target == e:
		hook_target = null
	respawn.append(3.0)
	var air: bool = float(e.h) > 0.05
	var p: Vector3 = e.p + Vector3.UP * float(e.h)
	# обгоревший остаётся обгоревшим, чем бы его ни добили (правка 1, раунд 7)
	var scorched: bool = bool(e.charred) or outcome == "burn"
	var burning: bool = float(e.burn) > 0.0 or outcome == "burn"
	var body_outcome: String = "intact" if outcome == "burn" else outcome
	gore.scorched = scorched
	var right := dir.cross(Vector3.UP)
	var up := Vector3.UP
	var knock := dir * 0.25
	# смерть в воздухе: тело кувыркается и падает, фонтаны бьют из него на лету, куски летят отдельно
	var body: Dictionary = {}
	if air:
		var fly := Vector3(dir.x, 0.0, dir.z) * 1.8 + up * (2.0 if float(e.vy) > -1.0 else float(e.vy))
		body = gore.falling_body(body_outcome, e.dir, p + up * 0.9, fly, burning)
		gore.spray(p + up * 1.0, dir + up * 0.5, 60, 5.0, 0.9)
		gore.chunks(p + up * 1.0, dir + up * 0.4, 3, 3.5)
	match outcome:
		"decap":
			gore.piece("head", p + up * 1.55, dir * 2.5 + up * 3.5 + right * rng.randf_range(-1, 1))
			gore.spray(p + up * 1.45, dir + up * 0.6, 70, 4.0)
			gore.spurt(p + up * 0.5 - dir * 0.6, up + dir * 0.3, 1.6, 90.0, body)
			gore.chunks(p + up * 1.5, dir, 2, 3.0)
		"arm_off_r":
			gore.piece("arm_r", p + up * 1.1 - right * 0.25, dir * 2.0 + up * 2.5 - right * 1.5)
			gore.spray(p + up * 1.3, dir - right * 0.5, 60, 3.5)
			gore.spurt(p + up * 0.4 - right * 0.3, up - right * 0.4, 1.4, 70.0, body)
		"split":
			gore.piece("upper_half", p + up * 1.3, dir * 2.2 + up * 2.6)
			gore.spray(p + up * 1.1, dir + up * 0.3, 110, 4.5, 0.9)
			gore.chunks(p + up * 1.1, dir, 4, 3.5)
			gore.spurt(p + up * 0.5, up, 1.8, 120.0, body)
		"gut":
			gore.piece("arm_l", p + up * 1.1 + right * 0.25, dir * 1.6 + up * 2.2 + right * 1.2)
			gore.spray(p + up * 0.9, dir, 80, 3.5)
			gore.chunks(p + up * 0.9, dir, 5, 2.5)
			gore.spurt(p + up * 0.35, up + dir * 0.4, 1.8, 80.0, body)
		"blast":
			gore.piece("head", p + up * 1.55, dir * 6.0 + up * 4.0 + right * rng.randf_range(-1, 1))
			gore.piece("arm_r", p + up * 1.2, dir * 5.0 + up * 3.0 - right * 2.0)
			gore.spray(p + up * 1.2, dir, 150, 7.0, 0.5)
			gore.chunks(p + up * 1.2, dir, 9, 7.0)
			gore.spurt(p + up * 0.5, up, 1.6, 100.0, body)
			knock = dir * 0.9
		"intact":
			gore.spray(p + up * 1.2, dir, 50, 4.0, 0.4)
			knock = dir * 0.5
		"arm_off_l":
			gore.piece("arm_l", p + up * 1.1 + right * 0.25, dir * 2.0 + up * 2.5 + right * 1.5)
			gore.spray(p + up * 1.3, dir + right * 0.5, 60, 3.5)
			gore.spurt(p + up * 0.4 + right * 0.3, up + right * 0.4, 1.4, 70.0, body)
		"leg_off":
			gore.piece("leg_r", p + up * 0.4 - right * 0.1, dir * 1.6 + up * 2.0 - right * 1.0)
			gore.spray(p + up * 0.6, dir, 70, 3.2)
			gore.chunks(p + up * 0.6, dir, 2, 2.5)
			gore.spurt(p + up * 0.3, up * 0.5 + dir * 0.4, 2.0, 90.0, body)
		"waist":
			gore.piece("torso_top", p + up * 1.3, dir * 2.0 + up * 3.2)
			gore.spray(p + up * 1.0, dir + up * 0.5, 130, 4.5, 0.9)
			gore.chunks(p + up * 1.0, dir, 6, 3.5)
			gore.spurt(p + up * 0.9, up, 2.2, 130.0, body)
		"crush":
			gore.spray(p + up * 1.3, up + dir * 0.3, 140, 5.0, 1.0)
			gore.chunks(p + up * 1.3, up, 7, 4.0)
			gore.spurt(p + up * 0.4, up, 1.6, 90.0, body)
			gore.decal(p, "m")
		"stab":
			gore.spray(p + up * 1.1, dir, 55, 4.0, 0.3)
			gore.spray(p + up * 1.1, -dir, 25, 2.5, 0.5)
			gore.spurt(p + up * 0.5 + dir * 0.2, dir + up * 0.5, 1.8, 70.0, body)
		"burn":
			gore.steam(p + up * 1.2, 3)
			gore.chunks(p + up * 1.0, up, 2, 2.0)
	if not air:
		gore.corpse(body_outcome, e.dir, p, knock, false, scorched, burning)
	gore.scorched = false
	shake = maxf(shake, 4.0 if outcome in ["blast", "split"] else 2.5)
	_hitstop(0.14 if outcome in ["blast", "split"] else 0.09)


func _hitstop(t: float) -> void:
	if demo.has("shot"):
		return
	Engine.time_scale = 0.0
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------- кадр ----------
func _process(delta: float) -> void:
	# сигнал size_changed у корневого окна при stretch=viewport не приходит, поэтому следим за размером сами
	if get_window().size != last_win:
		_apply_resolution()
	combat_t = maxf(combat_t - delta, 0.0)
	if combo_t > 0.0:
		combo_t -= delta
	fire_cd = maxf(fire_cd - delta, 0.0)
	aim_free = maxf(aim_free - delta, 0.0)
	pistol_aim_t = maxf(pistol_aim_t - delta, 0.0)
	_update_timers(delta)
	_update_pistol(delta)
	_update_gun(delta)
	if slam == "":
		_update_aim()
	if action:
		_update_action(delta)
	_update_dash(delta)
	_update_slam(delta)
	_update_spin(delta)
	_update_hook(delta)
	_update_jump(delta)
	_update_locomotion(delta)

	# ноги: рывок, прыжок, удар на месте или бег; корпус: рывок, удар, обрез или цикл по ногам
	var loco_frame := int(leg_phase * int(meta.legs[loco].frames)) % int(meta.legs[loco].frames)
	var legs_sheet := loco
	var legs_frame := loco_frame
	if slam != "":
		legs_sheet = "slam_gun" if module == "shotgun" else "slam"
		legs_frame = slam_frame
	elif ult_t >= 0.0:
		legs_sheet = "ult_spin"
		legs_frame = _spin_frame()
	elif dash_t >= 0.0:
		legs_sheet = "dash"
		legs_frame = mini(int(dash_t / DASH_TIME * int(meta.legs.dash.frames)), int(meta.legs.dash.frames) - 1)
	elif airborne:
		legs_sheet = "jump"
		legs_frame = _jump_frame()
		if takeoff_t >= 0.0:
			legs_sheet = "land"           # присед на взлёте
			legs_frame = 1
	elif action and loco == "idle":
		legs_sheet = action
		legs_frame = act_frame
	elif land_t >= 0.0:
		legs_sheet = "land"
		legs_frame = mini(int(land_t / LAND_T * 3.0), 2)
	elif run_stop_t >= 0.0:
		legs_sheet = "run_stop"
		legs_frame = mini(int(run_stop_t / RUN_STOP_T * 3.0), 2)
	elif run_start_t >= 0.0:
		legs_sheet = "run_start"
		legs_frame = mini(int(run_start_t / RUN_START_T * 3.0), 2)

	var upper_name: String
	var upper_frame: int
	if slam != "":
		upper_name = "slam_" + module
		upper_frame = slam_frame
	elif ult_t >= 0.0:
		upper_name = "ult_spin"
		upper_frame = legs_frame
	elif hook != "":
		upper_name = "hook_aim" if hook == "aim" else "hook"
		upper_frame = {"aim": 0, "fly": 1 if hook_t < 0.06 else 2, "pull": 3, "back": 2}[hook]
	elif action:
		upper_name = action
		upper_frame = act_frame
	elif module == "shotgun" and gun != "":
		# правка 4: на ходу и на бегу у обреза свой корпус — с наклоном и в такт шагу
		if gun in ["reload", "shoot2", "ult"]:
			upper_name = "gun_%s_run" % gun if loco == "run" else "gun_" + gun
			upper_frame = gun_frame
		elif loco != "idle" and (gun == "aim" or gun == "shoot"):
			upper_name = "gun_%s_%s" % [gun, loco]
			upper_frame = loco_frame if gun == "aim" else gun_frame
		else:
			upper_name = "gun_" + gun
			upper_frame = gun_frame
	elif dash_t >= 0.0:
		upper_name = "dash_" + module
		upper_frame = legs_frame
	elif switch_t >= 0.0:
		# смена оружия: первая половина прежний модуль, с середины новый, стык за клубом пара
		var sf := mini(int(switch_t / SWITCH_T * 5.0), 4)
		upper_name = "switch_" + (switch_from if sf < 2 else module)
		upper_frame = sf
		if sf >= 2 and not switch_steamed:
			switch_steamed = true
			pending.append("switch_steam")
	elif airborne:
		upper_name = ("land_" + module) if takeoff_t >= 0.0 else ("jump_" + module)
		upper_frame = legs_frame
	elif legs_sheet in ["land", "run_stop", "run_start"]:
		upper_name = "%s_%s" % [legs_sheet, module]
		upper_frame = legs_frame
	else:
		upper_name = "%s_%s" % [loco, module]
		upper_frame = loco_frame

	# корпус поворачивается за мышью через промежуточные направления
	if action and slam == "" and ult_t < 0.0:
		# раунд 11: удар разворачивает корпус не мгновенно, а через промежуточные направления (≈0,06 с на 180°)
		upper_ang = _turn(upper_ang, act_dir * 45.0, TURN_ACT, delta)
		upper_dir = _shown(upper_ang, upper_dir)
	elif not action and slam == "" and ult_t < 0.0 and (dash_t < 0.0 or gun != ""):
		var look := hook_dir if hook in ["fly", "pull", "back"] else aim_vec
		upper_ang = _turn(upper_ang, _torso_target(_screen_ang(look)), TURN_UPPER, delta)
		upper_dir = _shown(upper_ang, upper_dir)

	# раунд 11: в прицеле и выстреле обреза правая рука — отдельный наведённый слой, корпус без неё
	garm_col = -1
	if upper_name.begins_with("gun_") and gun in ["aim", "shoot", "shoot2"] and meta.upper.has(upper_name + "_noarm"):
		upper_name += "_noarm"
		var states: Array = meta.aim_arm.shotgun.frame_state["gun_" + gun]
		var st: int = int(states[mini(gun_frame, states.size() - 1)]) if gun != "aim" else 0
		garm_col = _arm_off_idx() * int(meta.aim_arm.shotgun.states) + st
	parm_col = -1
	if (pistol != 0 or pistol_aim_t > 0.0) and pr_i < 0 and action == "" and ult_t < 0.0 and slam == "" and dash_t < 0.0:
		parm_col = _arm_off_idx() * int(meta.aim_arm.pistol.states) + pistol

	# раунд 12: голова слегка поворачивается в сторону наведённой руки
	var arm_yaw := 0.0
	var arm_side := 0
	if parm_col >= 0:
		arm_yaw = float(meta.aim_arm.offsets[parm_col / int(meta.aim_arm.pistol.states)])
		arm_side = -1
	elif garm_col >= 0:
		arm_yaw = float(meta.aim_arm.offsets[garm_col / int(meta.aim_arm.shotgun.states)])
		arm_side = 1
	if arm_side != 0 and absf(arm_yaw) >= 45.0:
		var sgn: float = signf(arm_yaw) if absf(arm_yaw) < 179.0 else float(arm_side)
		var hk: String = ("hr" if sgn > 0.0 else "hl") + ("1" if absf(arm_yaw) <= 112.5 else "2")
		if meta.upper.has(upper_name + "_" + hk):
			upper_name += "_" + hk

	var lm: Dictionary = meta.legs[legs_sheet]
	var um: Dictionary = meta.upper[upper_name]
	var off: Array = lm.offsets_px[meta.dirs[legs_dir]][legs_frame]
	_show(legs, _layer("L_" + legs_sheet), int(lm.frames), legs_dir, legs_frame)
	_show(upper, _layer("U_" + upper_name), int(um.frames), upper_dir, upper_frame)
	var pr: Dictionary = meta.pistol_reload
	var n_off: int = meta.aim_arm.offsets.size()
	if pr_i >= 0 and pr.src.has(um.src):
		_show(arm, _layer("R_" + um.src), int(meta.arm[um.src].frames) * int(pr.states), upper_dir,
			upper_frame * int(pr.states) + int(pr.seq[pr_i]))
	elif parm_col >= 0:
		_show(arm, _layer("A_aim"), n_off * int(meta.aim_arm.pistol.states), upper_dir, parm_col)
	else:
		_show(arm, _layer("A_" + um.src), int(meta.arm[um.src].frames) * 4, upper_dir, upper_frame * 4 + pistol)
	garm.visible = garm_col >= 0
	if garm.visible:
		_show(garm, _layer("S_aim"), n_off * int(meta.aim_arm.shotgun.states), upper_dir, garm_col)
	lift = Vector2(float(off[0]), HERO_FEET + float(off[1]))
	upper.offset = lift
	arm.offset = lift
	garm.offset = lift
	upper_now = [upper_name, upper_frame, upper_dir]
	trail.visible = (action != "" or ult_t >= 0.0) and bool(um.get("trail", false))
	if trail.visible:
		_show(trail, _layer("X_" + upper_name), int(um.frames), upper_dir, upper_frame)
		trail.offset = lift

	var ground := _snap(hero_pos)
	var p := _snap(hero_pos + Vector3.UP * hero_h)
	var toward_cam := cam.global_basis.z
	shadow.visible = airborne
	shadow.global_position = ground - toward_cam * 0.02
	legs.global_position = p
	upper.global_position = p + toward_cam * LAYER_BIAS
	garm.global_position = p + toward_cam * LAYER_BIAS * 1.5
	arm.global_position = p + toward_cam * LAYER_BIAS * 2.0
	trail.global_position = p + toward_cam * LAYER_BIAS * 3.0

	_fx_events()
	_draw_chain()
	_update_ghosts(delta)
	steam_t += delta
	if steam_t > 3.0:
		steam_t = 0.0
		gore.steam(_anchor_world(_upper_anchor("vent" if module == "blade" else "hose_top")), 1)
	_update_enemies(delta)
	gore.update(delta)

	var cam_off := Vector3.ZERO
	if shake > 0.0:
		var a := ceili(shake)
		cam_off = cam.global_basis.x * rng.randi_range(-a, a) * PX + cam.global_basis.y * rng.randi_range(-a, a) * PX
		shake = maxf(shake - delta * 20.0, 0.0)
	cam.global_position = ground + cam_off + _mech_camera_offset(delta) + cam.global_basis.z * 30.0
	hud_g.set_state(_hud_state(), delta)
	hud.text = "Модуль: %s (Q)   Обрез: %s   Револьвер: %s   Ульта (Ctrl): %s   ЛКМ — %s   ПКМ — %s   Alt — револьвер   R — перезарядка   Shift — рывок   Space — прыжок   F11 — экран\nF2 — добавить меха (до 4)   F10 — восстановить здоровье" % [
		MODULE_NAMES[module], "заряжается" if gun == "reload" else "%d/%d" % [ammo.shotgun, MAG.shotgun],
		"заряжается" if pr_i >= 0 else "%d/%d" % [ammo.pistol, MAG.pistol], _ult_text(),
		"выстрел" if module == "shotgun" else "удар",
		"удар о землю" if airborne and jumps_used >= MAX_JUMPS and slam_cd <= 0.0 else ("залп" if module == "shotgun" else "тяжёлый")]


## На бегу корпус за курсором, но не дальше TORSO_LIMIT от ног (раунды 9–10).
## Раунд 11: с оружием в руке корпус в этих пределах выбирает сторону, с которой рука достаёт цель
## своей стороной (через грудь не дальше ARM_CROSS): правая рука с обрезом тянется назад через правое плечо.
func _torso_target(ang: float) -> float:
	if loco == "idle" or aim_free > 0.0 or hook in ["fly", "pull", "back"]:
		return ang
	var base := legs_tgt + clampf(wrapf(ang - legs_tgt, -180.0, 180.0), -TORSO_LIMIT, TORSO_LIMIT)
	var side := _gun_arm_side()
	if side == 0 or _arm_reach_ok(ang, base, side):
		return base
	var best := base
	var best_d := INF
	for k in range(-9, 10):
		var t := legs_tgt + k * TORSO_LIMIT / 9.0
		var d := absf(wrapf(ang - t, -180.0, 180.0))
		if _arm_reach_ok(ang, t, side) and d < best_d:
			best = t
			best_d = d
	return best


## Какая рука держит оружие наведённым: 1 — правая с обрезом, -1 — левая с револьвером, 0 — никакая.
func _gun_arm_side() -> int:
	if pistol != 0 or pistol_aim_t > 0.0:
		return -1
	if module == "shotgun" and gun in ["aim", "shoot", "shoot2"]:
		return 1
	return 0


## Наклон руки к цели от корпуса t: плюс — вправо героя (экранный угол растёт влево героя).
func _arm_reach_ok(ang: float, t: float, side: int) -> bool:
	var yaw := -wrapf(ang - t, -180.0, 180.0)
	return yaw * side >= -ARM_CROSS or absf(yaw) >= 179.0


## Кадр направления наведённой руки: отклонение мыши от показанного корпуса с шагом AIM_STEP.
func _arm_off_idx() -> int:
	var yaw := -wrapf(_screen_ang(aim_vec) - upper_dir * 45.0, -180.0, 180.0)
	return posmod(int(round(yaw / AIM_STEP)), int(meta.aim_arm.offsets.size()))


## Куда уходит выстрел: всегда туда, куда смотрит мышь (раунд 11); рука наводится сама.
func _shot_vec() -> Vector3:
	return aim_vec


func _ang_vector(deg: float) -> Vector3:
	var yb := Basis(Vector3.UP, deg_to_rad(YAW))
	var a := deg_to_rad(deg)
	return ((yb * Vector3.RIGHT) * sin(a) + (yb * Vector3.BACK) * cos(a)).normalized()


func _update_timers(delta: float) -> void:
	if land_t >= 0.0:
		land_t += delta
		if land_t >= LAND_T:
			land_t = -1.0
	if takeoff_t >= 0.0:
		takeoff_t += delta
		if takeoff_t >= TAKEOFF_T:
			takeoff_t = -1.0
	if switch_t >= 0.0:
		switch_t += delta
		if switch_t >= SWITCH_T or action or gun != "":
			switch_t = -1.0


## Остаточные силуэты рывка: дизер одним цветом палитры, живут 0,15 с.
func _update_ghosts(delta: float) -> void:
	for i in range(ghosts.size() - 1, -1, -1):
		var g: Dictionary = ghosts[i]
		g.t += delta
		if g.t >= GHOST_LIFE:
			g.node.queue_free()
			ghosts.remove_at(i)
	if dash_t < 0.0:
		ghost_t = 0.0
		return
	ghost_t -= delta
	if ghost_t <= 0.0:
		ghost_t = GHOST_EVERY
		var s := _make_sprite()
		add_child(s)
		s.offset = Vector2(0, HERO_FEET)
		var fr := int(meta.legs.dash.frames)
		_show(s, _layer("G_dash_" + module), fr, legs_dir, mini(int(dash_t / DASH_TIME * fr), fr - 1))
		s.global_position = _snap(hero_pos + Vector3.UP * hero_h) - cam.global_basis.z * 0.03
		ghosts.append({"node": s, "t": 0.0})


## Длина шага бега, м: два шага за цикл ног.
func _step_len() -> float:
	var lm: Dictionary = meta.legs.run
	return float(SPEED.run) * float(lm.frames) * float(lm.durations_ms[0]) / 1000.0 / 2.0


## Звуки, которые зависят от состояния, а не от события: шаги по пройденному пути, готовность ульты,
## подъём тумблеров рывка, сердце при малом здоровье.
func _sfx_tick() -> void:
	var dt := get_process_delta_time()
	# шаги (раунд 16): по пройденному пути, а не по фазе ног — смена клавиш на бегу не сбивает такт
	var running := loco == "run" and not airborne and dash_t < 0.0 and slam == ""
	step_since += dt
	if running:
		step_gap = 0.0
		step_dist += Vector2(hero_pos.x - step_last.x, hero_pos.z - step_last.z).length()
		var sl := _step_len()
		if step_dist >= sl and step_since >= STEP_MIN:
			sfx.play("step", -12.0)
			step_dist = minf(step_dist - sl, sl * 0.5)
			step_since = 0.0
	else:
		step_gap += dt
		if step_gap > STEP_GAP:
			step_dist = _step_len()      # с места первый шаг сразу
	step_last = hero_pos
	# ульта серпа: цепь звенит, пока летит, тянет и возвращается; потом плавно затихает (раунд 15)
	sfx.hold("chain_loop", hook in ["fly", "pull", "back"], -10.0, 0.06, CHAIN_FADE)
	_update_crosshair()
	var cd: float = {"blade": spin_cd, "sickle": hook_cd, "shotgun": fire_cd}[module]
	var ready := cd <= 0.0
	if ready and not ult_was_ready:
		sfx.play("ult_ready", -14.0)
	ult_was_ready = ready
	if hud_g.shown_down[0] and dash_spent == 0:
		sfx.play("switch", -16.0)
	if hero_hp > 0.0 and hero_hp <= 0.25:
		heart_t -= dt
		if heart_t <= 0.0:
			heart_t = 0.9
			sfx.play("heartbeat", -6.0)


## Прицел вместо курсора (раунд 15): центр круга — точка, куда целится мышь.
func _update_crosshair() -> void:
	if crosshair == null:
		return
	var mp: Vector2 = mouse_override if mouse_override != null else get_viewport().get_mouse_position()
	crosshair.position = (mp - crosshair.size / 2.0).round()


## Состояние для датчика: доли колец, патроны, тумблеры рывка.
func _hud_state() -> Dictionary:
	_sfx_tick()
	var cd: float = {"blade": spin_cd, "sickle": hook_cd, "shotgun": fire_cd}[module]
	var full: float = {"blade": SPIN_CD, "sickle": HOOK_CD, "shotgun": FIRE_CD}[module]
	var ult_use := ult_t >= 0.0 or hook != ""
	# раунд 17: после ульты кольцо заполняется с нуля за оставшийся откат (откат не меняется, только картинка):
	# иначе у серпа кольцо прыгало сразу на 90 % — откат шёл, пока летела цепь
	var fill := 1.0 - cd / full
	if ult_use:
		ult_cd_end[module] = -1.0
	elif float(ult_cd_end.get(module, 0.0)) < 0.0:
		ult_cd_end[module] = cd
	var ce: float = ult_cd_end.get(module, 0.0)
	if ce > 0.0 and cd > 0.0:
		fill = 1.0 - cd / ce
	elif cd <= 0.0:
		ult_cd_end[module] = 0.0
	return {"hp": hero_hp, "ult": 0.0 if ult_use else fill,
		"shotgun": [ammo.shotgun, MAG.shotgun], "pistol": [ammo.pistol, MAG.pistol],
		"shotgun_reload": gun == "reload", "pistol_reload": pr_i >= 0, "dash_down": dash_spent}


func _ult_text() -> String:
	var cd: float = {"blade": spin_cd, "sickle": hook_cd, "shotgun": fire_cd}[module]
	return "готова" if cd <= 0.0 else "%.0f с" % ceilf(cd)


## Кадр вращения: замах, четыре шага по кругу, возврат.
func _spin_frame() -> int:
	if ult_t < SPIN_WIND:
		return 0
	if ult_t > SPIN_T - SPIN_END:
		return 5
	return 1 + int((ult_t - SPIN_WIND) / 0.047) % 4    # вращение быстрее на 40 % (раунд 10)

## Бег по умолчанию. Ноги всегда смотрят по ходу и бегут вперёд, корпус поворачивается за курсором (раунд 8).
## Стоя ноги разворачиваются, только когда прицел ушёл за плечо. Удар бега не останавливает.
func _update_locomotion(delta: float) -> void:
	var inp := _input_vec()
	if dash_t >= 0.0:
		return                         # рывок сам ведёт героя и ноги
	if ult_t >= 0.0:
		loco = "idle"
		leg_phase = 0.0
		if inp != Vector2.ZERO:
			hero_pos += _world_dir(inp) * float(SPEED.run) * SPIN_SPEED * delta
		else:
			hero_pos += aim_vec * SPIN_DRIFT * delta
		return
	if slam == "impact":
		loco = "idle"
		leg_phase = 0.0
		return
	if slam == "fall":
		if inp != Vector2.ZERO:        # в падении можно немного поправить точку удара
			hero_pos += _world_dir(inp) * float(SPEED.run) * 0.5 * delta
		return
	var aim_ang := _screen_ang(aim_vec)
	if inp == Vector2.ZERO:
		# торможение: только из бега на земле; удар и прыжок его отменяют
		if loco == "run" and not action and not airborne:
			run_stop_t = 0.0
			run_stop_vec = _dir_vector(legs_dir)
		loco = "idle"
		run_start_t = -1.0
		idle_t = fposmod(idle_t + delta, IDLE_CYCLE)
		leg_phase = idle_t / IDLE_CYCLE
		if run_stop_t >= 0.0:
			if action or airborne:
				run_stop_t = -1.0
			else:
				hero_pos += run_stop_vec * float(SPEED.run) * RUN_STOP_SLIDE * (1.0 - run_stop_t / RUN_STOP_T) * delta
				run_stop_t += delta
				if run_stop_t >= RUN_STOP_T:
					run_stop_t = -1.0
				legs_ang = _turn(legs_ang, legs_tgt, TURN_LEGS, delta)
				legs_dir = _shown(legs_ang, legs_dir)
				return
		if action:
			legs_tgt = act_dir * 45.0
			legs_ang = upper_ang       # ноги удара нарисованы под направление удара и идут за корпусом (раунд 11)
		elif absf(wrapf(aim_ang - legs_tgt, -180.0, 180.0)) > LEGS_TURN_ON:
			legs_tgt = aim_ang
	else:
		# разгон: только из покоя на земле, без удара
		if loco == "idle":
			leg_phase = 0.0
			if not action and not airborne:
				run_start_t = 0.0
		run_stop_t = -1.0
		loco = "walk" if demo.get("move", "") == "walk" else "run"
		var dir := _world_dir(inp)
		var slow := HEAVY_RUN_SLOW if action != "" and action == HEAVY.get(module, "") else 1.0
		if _is_air_action():
			slow = AIR_ACT_SPEED
		if run_start_t >= 0.0:
			slow *= RUN_START_SPEED
			run_start_t += delta
			if run_start_t >= RUN_START_T:
				run_start_t = -1.0
		hero_pos += dir * float(SPEED[loco]) * slow * delta
		legs_tgt = _screen_ang(dir)
		var lm: Dictionary = meta.legs[loco]
		var fps := 1000.0 / float(lm.durations_ms[0])
		leg_phase = fposmod(leg_phase + delta * slow * fps / float(lm.frames), 1.0)
	legs_ang = _turn(legs_ang, legs_tgt, TURN_LEGS, delta)
	legs_dir = _shown(legs_ang, legs_dir)


func _shot(path: String, wait: int) -> void:
	for i in wait:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _height_reaches(e: Dictionary) -> bool:
	return hero_h <= 3.4 if e.get("kind", "") == "mech" else absf(float(e.h)-hero_h) <= AIR_REACH


func _spawn_mech(pos: Vector3) -> Dictionary:
	# F2 is a sandbox control; keep accidental key repeats bounded.
	var count := 0
	for e in enemies:
		if e.get("kind", "") == "mech": count += 1
	if count >= 4: return {}
	var mech := Mech.new()
	add_child(mech)
	return mech.setup(self,pos)


func _hurt_hero(amount: float, _dir: Vector3) -> void:
	if invuln or hero_hp <= 0.0: return
	hero_hp = maxf(0.0,hero_hp-amount)
	shake = maxf(shake,2.0)
	sfx.play("hit",-5.0)


func _mech_camera_offset(delta: float) -> Vector3:
	# Keep both the hero and a tall opponent visible without changing the pixel scale.
	var nearest: Variant = null
	var distance := 12.0
	for e in enemies:
		if e.get("kind", "") != "mech": continue
		var d: float = e.p.distance_to(hero_pos)
		if d < distance:
			distance = d
			nearest = e
	var target := Vector2.ZERO
	if nearest != null:
		var to: Vector3 = (nearest.p + Vector3.UP*2.0-hero_pos)*0.35
		target = Vector2(clampf(to.dot(cam.global_basis.x)/PX,-120,120),clampf(to.dot(cam.global_basis.y)/PX,-140,140))
	mech_camera = mech_camera.move_toward(target,220.0*delta)
	var px := mech_camera.round()
	return (cam.global_basis.x*px.x+cam.global_basis.y*px.y)*PX
