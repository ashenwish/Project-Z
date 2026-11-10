extends Sprite3D
## Mech scout. The enemy dictionary stays compatible with the arena's weapons.
## Native sprite rows are asymmetric: never mirror. Coordinates come from render metadata.

const DIRS := ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
const ROOT := "res://assets/mech/"
const HP := 48
const PILOT_HEADSHOT_CHANCE := 0.10
const WALK_SPEED := 0.833
const EXPLOSION_R := 3.5
const WRECK_LIMIT := 40
const FX := {
    "sparks_metal": [6, 3, [35,40,45,50,55,60], Vector2(24,24)],
    "flash_maxim": [2, 8, [25,35], Vector2(16,16)],
    "stomp_dust": [6, 1, [40,45,50,55,60,70], Vector2(32,22)],
    "smoke_mech": [8, 1, [80,80,80,80,80,80,80,80], Vector2(32,86)],
    "blast_mech": [8, 1, [40,50,60,70,80,100,120,150], Vector2(64,68)],
    "pilot_blood": [6, 1, [45,50,55,60,70,80], Vector2(32,32)]
}
static var metas := {}
static var images := {}
var arena
var data: Dictionary
var anim := "idle"
var anim_frame := 0
var clock := 0.0
var cooldown := 1.0
var steam_t := 0.0
var step_index := -1
var fired := 0
var stomped := false
var exploded := false
var smoked := false
var death_cut := false
var fade := -1.0
var dead := false
var broken := Vector3.ZERO
var mat := ShaderMaterial.new()
var bullets: Array = []
var flame: Sprite3D
var burn_elapsed := 0.0
var burst_target := Vector3.ZERO


func setup(owner_arena, pos: Vector3) -> Dictionary:
    arena = owner_arena
    if metas.is_empty():
        for name in ["idle","walk","hit","shoot","stomp","die","die_decap","shatter","wreck"]:
            metas[name] = JSON.parse_string(FileAccess.get_file_as_string(ROOT + name + ".json"))
    pixel_size = arena.PX
    texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    billboard = BaseMaterial3D.BILLBOARD_DISABLED
    shaded = false
    alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    mat.shader = load("res://scripts/mech_parts.gdshader")
    material_override = mat
    var sh: Sprite3D = arena._make_shadow()
    add_child(sh)
    sh.visible = true
    sh.scale = Vector3(3.5, 2.0, 1.0)
    data = {"kind":"mech", "node":self, "shadow":sh, "p":pos, "h":0.0,
        "vy":0.0, "hp":HP, "dir":0, "state":"idle", "t":0.0, "hits":0,
        "spiked":false, "immune":0.0, "burn":0.0, "burn_tick":0.5,
        "burn_spread":0.0, "charred":false, "flame":null, "hook_f":0.0}
    arena.enemies.append(data)
    _draw_frame()
    return data


func _set_state(state: String) -> void:
    data.state = state
    data.t = 0.0
    clock = 0.0
    step_index = -1
    fired = 0
    stomped = false


func _process(delta: float) -> void:
    if data.is_empty():
        return
    _update_bullets(delta)
    if fade >= 0.0:
        fade -= delta
        # Dithered alpha cut preserves crisp pixel edges while the oldest wreck fades.
        mat.set_shader_parameter("opacity",maxf(fade, 0.0))
        if fade <= 0.0:
            queue_free()
        return
    clock += delta
    data.t = clock
    if dead:
        _death_tick()
    else:
        _burn_tick(delta)
        if not dead:
            _ai(delta)
    _draw_frame()
    if flame != null:
        flame.frame = int(burn_elapsed * 12.5) % 8
        flame.global_position = arena._snap(anchor("body")) + arena.cam.global_basis.z * 0.08
        burn_elapsed += delta


func _ai(delta: float) -> void:
    cooldown = maxf(0.0, cooldown - delta)
    steam_t -= delta
    if steam_t <= 0.0:
        steam_t = 0.7
        for key in ["steam_r","steam_l"]:
            arena.gore.steam(anchor(key), 1)
        sound("mech_steam", -19.0)
    if arena.hero_hp <= 0.0:
        if data.state != "idle": _set_state("idle")
        return
    var to: Vector3 = arena.hero_pos - data.p
    to.y = 0.0
    var dist := to.length()
    match data.state:
        "flinch":
            if clock >= 0.28: _set_state("idle")
        "windup":
            if clock >= 0.45:
                burst_target = arena.hero_pos + Vector3.UP * (arena.hero_h + 0.8)
                _set_state("shoot")
                _fire_round()
        "shoot":
            while fired < 6 and clock >= float(fired) * 0.1:
                _fire_round()
            if clock >= 0.6:
                cooldown = 1.8
                _set_state("idle")
        "stomp":
            if not stomped and clock >= 0.29:
                _stomp()
            if clock >= 0.6:
                cooldown = 1.2
                _set_state("idle")
        _:
            data.dir = arena._dir_index(to)
            if cooldown <= 0.0 and dist <= 1.6:
                _set_state("stomp")
                sound("mech_steam", -10.0)
            elif cooldown <= 0.0 and dist <= 10.0:
                _set_state("windup")
                sound("mech_steam", -7.0)
            elif dist > 5.5:
                if data.state != "walk": _set_state("walk")
                # Keep the heavy body clear of other enemies and the hero.
                var velocity := to.normalized() * WALK_SPEED
                for e in arena.enemies:
                    if e == data: continue
                    var away: Vector3 = data.p - e.p
                    away.y = 0.0
                    if away.length() < 1.2 and away.length() > 0.01:
                        velocity += away.normalized() * (1.2 - away.length())
                data.p += velocity.limit_length(WALK_SPEED) * delta
                var si := int(clock * 2.0)
                if si != step_index:
                    step_index = si
                    sound("mech_step", -6.0)
            elif data.state != "idle":
                _set_state("idle")


func _fire_round() -> void:
    # Two native muzzle frames per 200 ms cycle; the burst direction is locked.
    fired += 1
    anim = "shoot"
    anim_frame = 0 if fired % 2 == 1 else 2
    var p := anchor("muzzle")
    fx("flash_maxim", p, int(data.dir))
    sound("mech_maxim", -6.0)
    var f: Vector3 = arena._dir_vector(int(data.dir))
    var r := f.cross(Vector3.UP)
    arena.gore.throw(load(ROOT+"shell_maxim.png"), 8, 0, anchor("eject"), r * 2.0 + Vector3.UP * 1.8, "metal", 0.0, 0.02)
    var s := Sprite3D.new()
    s.texture = load(ROOT+"tracer_maxim.png")
    s.hframes = 1
    s.vframes = 8
    s.frame = int(data.dir)
    s.pixel_size = arena.PX
    s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    s.shaded = false
    s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    add_child(s)
    s.global_position = p
    bullets.append({"node":s,"p":p,"v":(burst_target-p).normalized()*48.0,"life":0.4})


func _update_bullets(delta: float) -> void:
    for i in range(bullets.size()-1,-1,-1):
        var b: Dictionary = bullets[i]
        var end: Vector3 = b.p + b.v * delta
        var center: Vector3 = arena.hero_pos + Vector3.UP * (arena.hero_h + 0.8)
        var nearest := Geometry3D.get_closest_point_to_segment(center,b.p,end)
        var hit := nearest.distance_to(center) <= 0.34
        b.p = end
        b.life -= delta
        if hit:
            arena._hurt_hero(0.08, b.v.normalized())
        if hit or b.life <= 0.0 or end.y <= 0.05:
            b.node.queue_free()
            bullets.remove_at(i)
        else:
            b.node.global_position = arena._snap(end)


func _stomp() -> void:
    stomped = true
    anim = "stomp"
    anim_frame = 3
    var p := anchor("foot_r")
    p.y = 0.02
    fx("stomp_dust", p)
    sound("mech_stomp", -3.0)
    if p.distance_to(arena.hero_pos) <= 1.6 and arena.hero_h < 0.45:
        arena._hurt_hero(0.2, (arena.hero_pos-p).normalized())
    arena.shake = maxf(arena.shake, 3.0)


func anchor(key: String) -> Vector3:
    var m: Dictionary = metas[anim]
    var local: Array
    var tracks: Dictionary = m.get("anchors_frames_m", {})
    if tracks.has(key):
        local = tracks[key][mini(anim_frame,tracks[key].size()-1)]
    else:
        local = m.get("anchors_m", {}).get(key, metas.shoot.anchors_m.get(key, [0,0,2.1]))
        local = local.duplicate()
        if m.has("body_dz_px") and key not in ["muzzle","eject","foot_r"]:
            local[2] += float(m.body_dz_px[mini(anim_frame,m.body_dz_px.size()-1)]) / 56.0
    var f: Vector3 = arena._dir_vector(int(data.dir))
    return data.p + f.cross(Vector3.UP)*float(local[0]) + f*float(local[1]) + Vector3.UP*float(local[2])


func _frame_at(ms: float, durations: Array) -> int:
    var t := 0.0
    for i in durations.size():
        t += float(durations[i])
        if ms < t: return i
    return durations.size()-1


func _draw_frame() -> void:
    var state: String = data.state
    anim = {"flinch":"hit","windup":"idle","die":"die_decap" if death_cut else "die"}.get(state,state)
    var m: Dictionary = metas[anim]
    var durs: Array = m.durations_ms
    var duration := 0.0
    for d in durs: duration += float(d)
    var ms := clock*1000.0
    if anim in ["idle","walk","shoot"]: ms = fmod(ms,duration)
    if anim == "shatter": ms = (clock-1.06)*1000.0
    anim_frame = _frame_at(ms,durs)
    var tex_name := anim + ("_charred" if data.charred and anim not in ["shatter","wreck"] else "")
    texture = load(ROOT+tex_name+".png")
    hframes = int(m.frames)
    vframes = 8
    frame = int(data.dir)*hframes + anim_frame
    offset = Vector2(128-float(m.pivot[0]), float(m.pivot[1])-128)
    mat.set_shader_parameter("image", texture)
    mat.set_shader_parameter("parts", load(ROOT+anim+"_parts.png"))
    mat.set_shader_parameter("broken", broken)
    if state == "wreck":
        global_basis = Basis(Vector3.UP,deg_to_rad(arena.YAW))*Basis(Vector3.RIGHT,-PI/2)*Basis.from_scale(Vector3(1,2,1))
        global_position = arena.gore.ground_snap(data.p,0.018)
        data.shadow.visible = false
    else:
        global_basis = arena.cam.global_basis
        global_position = arena._snap(data.p)
        data.shadow.global_position = arena.gore.ground_snap(data.p,0.012)


func _local_pixel(mp: Vector2) -> Vector2i:
    var root: Vector2 = arena.cam.unproject_position(arena._snap(data.p))
    # The camera uses exactly 56 native pixels per metre at the logical viewport.
    return Vector2i((mp-root+Vector2(128,218)).floor())


func _image(name: String) -> Image:
    if not images.has(name):
        images[name] = load(ROOT+name+".png").get_image()
    return images[name]


func under_mouse(mp: Vector2) -> bool:
    var px := _local_pixel(mp)
    if px.x < 0 or px.y < 0 or px.x >= 256 or px.y >= 256: return false
    var at := px+Vector2i(anim_frame*256,int(data.dir)*256)
    if _image(anim).get_pixelv(at).a < 0.5: return false
    var mask := _image(anim+"_parts").get_pixelv(at)
    return Vector3(mask.r,mask.g,mask.b).dot(broken) < 0.5


func pilot_under_mouse(mp: Vector2) -> bool:
    var px := _local_pixel(mp)
    if not under_mouse(mp): return false
    return _image(anim+"_pilot").get_pixelv(px+Vector2i(anim_frame*256,int(data.dir)*256)).r > 0.5


func pilot_exposed(attacker: Vector3) -> bool:
    var to: Vector3 = attacker-data.p
    to.y = 0.0
    return to.length() > 0.01 and to.normalized().dot(arena._dir_vector(int(data.dir))) >= -0.25


func hurt(damage: int, _outcome: String, dir: Vector3, kind: String) -> void:
    if dead: return
    var cut := kind.begins_with("blade") or kind.begins_with("sickle") or kind == "spin"
    var aimed := false
    if kind in ["pistol","shotgun","shotgun_double","fire","hook"]:
        var mp: Vector2 = arena.mouse_override if arena.mouse_override != null else arena.get_viewport().get_mouse_position()
        aimed = arena._enemy_under(mp) == data and pilot_under_mouse(mp)
    var exposed := pilot_exposed(arena.hero_pos)
    var lucky_headshot: bool = kind == "pistol" and exposed and not aimed and arena.rng.randf() < PILOT_HEADSHOT_CHANCE
    var pilot: bool = exposed and ((cut and arena.hero_h >= 1.25) or aimed or lucky_headshot)
    if pilot:
        die(cut or kind == "hook", dir, true, lucky_headshot)
        return
    var dealt := damage
    # Three heavy blade hits or double-barrel blasts break the body, at any valid hit distance.
    if kind == "blade_heavy": dealt = 16
    elif kind == "blade_air_heavy": dealt = 16
    elif kind == "shotgun_double": dealt = 16
    data.hp -= dealt
    if kind != "burn_tick":
        fx("sparks_metal",anchor("body"),arena.rng.randi_range(0,2))
        sound("mech_metal_hit",-5.0)
        if kind.begins_with("blade"):
            detach_next(dir)
    if data.hp <= 0:
        die(false,dir,false)
    elif kind != "burn_tick":
        _set_state("flinch")


func detach_next(dir: Vector3) -> void:
    var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"mech_damage.json"))
    for i in 3:
        if broken[i] > 0.5: continue
        broken[i] = 1.0
        var name: String = ["cover","shield","cap"][i]
        var pt: Array = contract.pieces[name].source_center_px
        var f: Vector3 = arena._dir_vector(int(data.dir))
        var p: Vector3 = data.p + (f.cross(Vector3.UP)*float(pt[0])+f*float(pt[1])+Vector3.UP*float(pt[2]))/56.0
        arena.gore.throw(load(ROOT+"mech_piece_"+name+".png"),8,0,p,dir*2.4+Vector3.UP*3.5,"metal",0.0,0.02)
        return


func ignite() -> void:
    if dead: return
    data.burn = 4.0
    data.charred = true
    if flame == null:
        flame = Sprite3D.new()
        flame.texture = load(ROOT+"flame_mech.png")
        flame.hframes = 8
        flame.pixel_size = arena.PX
        flame.offset = Vector2(0,38)
        flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        flame.shaded = false
        flame.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
        add_child(flame)


func _burn_tick(delta: float) -> void:
    if data.burn <= 0.0: return
    data.burn -= delta
    data.burn_tick -= delta
    data.burn_spread -= delta
    while data.burn_tick <= 0.0:
        data.burn_tick += 0.5
        hurt(1,"burn",Vector3.UP,"burn_tick")
    if data.burn_spread <= 0.0:
        data.burn_spread = 0.4
        for e in arena.enemies.duplicate():
            if e != data and e.p.distance_to(data.p) <= 1.0 and float(e.burn) <= 0.0: arena._ignite(e, 4.0, true)
    if data.burn <= 0.0 and flame != null:
        flame.queue_free()
        flame = null


func die(cut := false, dir := Vector3.UP, pilot := false, headshot := false) -> void:
    if dead: return
    dead = true
    death_cut = cut
    data.hp = 0
    arena.enemies.erase(data)
    _set_state("die")
    if flame != null:
        flame.queue_free()
        flame = null
    if pilot:
        var p := anchor("pilot") + Vector3.UP*0.25
        if headshot: p += Vector3.UP*0.35
        fx("pilot_blood",p)
        arena.gore.spray(p,dir,45,4.0)
        arena.gore.spurt(p,dir,0.5,85.0)
        arena.gore.decal(data.p,"m")
        sound("gore",-6.0)
        if cut:
            var head: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"mech_pilot_head.json"))
            var center: Array = head.source_center_px
            var f: Vector3 = arena._dir_vector(int(data.dir))
            var head_p: Vector3 = data.p+(f.cross(Vector3.UP)*float(center[0])+f*float(center[1])+Vector3.UP*float(center[2]))/56.0
            arena.gore.throw(load(ROOT+"mech_pilot_head.png"),8,0,head_p,dir*3.0+Vector3.UP*4.5,"pilot_part",1.0,0.02)


func _death_tick() -> void:
    if not smoked and clock >= 0.24:
        smoked = true
        fx("smoke_mech",anchor("body"),0,0.5)
        sound("mech_steam",-5.0)
    if not exploded and clock >= 0.9:
        explode()
    if clock >= 1.24 and data.state != "wreck":
        data.state = "wreck"
        add_to_group("mech_wreck")
        var wrecks := get_tree().get_nodes_in_group("mech_wreck")
        if wrecks.size() > WRECK_LIMIT:
            var oldest = wrecks[0]
            oldest.remove_from_group("mech_wreck")
            oldest.fade = 1.0
    elif clock >= 1.06 and clock < 1.24:
        data.state = "shatter"


func explode() -> void:
    if exploded: return
    exploded = true
    fx("blast_mech",data.p+Vector3.UP*1.25)
    sound("mech_explosion",-2.0)
    for i in 3: detach_next(arena._dir_vector((int(data.dir)+i*3)%8))
    arena.gore.decal(data.p,"pool1")
    arena.shake = maxf(arena.shake,6.0)
    var d: float = (arena.hero_pos+Vector3.UP*arena.hero_h).distance_to(data.p)
    if d <= EXPLOSION_R:
        arena._hurt_hero(0.45*(1.0-d/EXPLOSION_R*0.6),(arena.hero_pos-data.p).normalized())
    for e in arena.enemies.duplicate():
        var dist: float = e.p.distance_to(data.p)
        if dist <= EXPLOSION_R:
            var dir: Vector3 = (e.p-data.p).normalized()
            arena._damage(e,roundi(12.0*(1.0-dist/EXPLOSION_R*0.6)),"blast",dir,"explosion")


func fx(name: String, p: Vector3, row := 0, rise := 0.0) -> void:
    var spec: Array = FX[name]
    var tex: Texture2D = load(ROOT+name+".png")
    arena.gore.oneshot(tex,int(spec[0]),row,int(spec[1]),p,float(spec[2][0]),rise)
    var shot: Dictionary = arena.gore.oneshots[-1]
    shot["durs"] = spec[2]
    shot.node.offset = Vector2(float(tex.get_width())/int(spec[0])/2,float(tex.get_height())/int(spec[1])/2) * Vector2(1,-1) + Vector2(-spec[3].x,spec[3].y)


func sound(name: String, gain := 0.0) -> void:
    var dist: float = data.p.distance_to(arena.hero_pos)
    if dist < 18.0:
        arena.sfx.play(name,gain-20.0*log(maxf(dist,2.0)/2.0)/log(10.0))
