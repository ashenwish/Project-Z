extends SceneTree
## Actual arena weapon routes, mech AI, damage and death contract. Exit 1 on failure.
var arena
var fails := 0
var checks := 0

func check(label: String, ok: bool, info: Variant = "") -> void:
    checks += 1
    print(("ok   " if ok else "FAIL ")+label+" "+str(info))
    if not ok: fails += 1

func _initialize() -> void:
    create_timer(60.0,true,false,true).timeout.connect(func(): print("FAIL timeout");quit(1))
    arena = load("res://scripts/test_arena.gd").new()
    root.add_child(arena)
    run.call_deferred()

func fresh() -> void:
    arena.set_process(false)
    arena.action = ""
    arena.hero_pos = Vector3.ZERO
    arena.hero_h = 0.0
    arena.hero_hp = 1.0
    arena.invuln = false
    arena.aim_vec = arena._dir_vector(0)
    arena.mouse_override = Vector2(950,530)
    arena.aim_target = null
    for e in arena.enemies.duplicate():
        e.node.queue_free()
        if e.get("kind", "") != "mech": e.shadow.queue_free()
    arena.enemies.clear()
    arena.respawn.clear()
    arena.sfx.muted = true

func mech(distance := 2.0):
    var e: Dictionary = arena._spawn_mech(arena.aim_vec*distance)
    var m = e.node
    m.set_process(false)
    e.dir = 4 # Face the hero; keep the cursor off the pilot for armor tests.
    m._draw_frame()
    return m

func pilot_pixel(m) -> Vector2:
    var img: Image = m._image(m.anim+"_pilot")
    for y in range(40,150):
        for x in range(60,200):
            if img.get_pixel(x+m.anim_frame*256,y+int(m.data.dir)*256).r > 0.5:
                return arena.cam.unproject_position(arena._snap(m.data.p))+Vector2(x-128,y-218)+Vector2(.5,.5)
    return Vector2(-100,-100)

func pistol_seed(headshot: bool) -> void:
    var probe := RandomNumberGenerator.new()
    for value in 1000:
        probe.seed=value
        if (probe.randf()<arena.Mech.PILOT_HEADSHOT_CHANCE)==headshot:
            arena.rng.seed=value
            return
    check("can find deterministic pistol roll",false)

func assert_explodes(m, label: String) -> void:
    check(label+" destroys body",m.dead and not arena.enemies.has(m.data))
    if not m.dead:return
    check(label+" waits before explosion",not m.exploded)
    m.clock=.9;m._death_tick()
    check(label+" explodes",m.exploded)

func run() -> void:
    await process_frame
    # The headless window is 64x64; use the game's logical viewport for aim checks.
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(960,540)
    arena.cam.size=540.0/56.0
    arena._process(0.0)
    fresh()
    var m = mech()
    arena.mouse_override=null
    arena.pending=["shotgun2"]
    arena._fx_events()
    check("real mouse: powerful blast applies damage through FX event",m.data.hp==32,m.data.hp)
    arena.pending=["shotgun2"];arena._fx_events()
    arena.pending=["shotgun2"];arena._fx_events()
    assert_explodes(m,"real mouse third powerful blast")
    fresh();m=mech(5);arena.mouse_override=null
    pistol_seed(false)
    arena.pending=["pistol"];arena._fx_events()
    check("real mouse: pistol applies armor damage through FX event",m.data.hp==47,m.data.hp)
    fresh();m=mech(5);arena.mouse_override=null
    pistol_seed(true)
    arena.pending=["pistol"];arena._fx_events()
    check("real mouse: lucky pistol headshot kills pilot",m.dead)
    fresh();m=mech(2);arena.mouse_override=null
    arena._fire_hits()
    check("real mouse: flame hits and ignites mech",m.data.hp<48 and m.data.charred)
    fresh();m=mech(2);arena.mouse_override=null
    arena.hook_dir=arena.aim_vec
    arena._hook_catch(m.data)
    check("real mouse: hook hits mech",m.data.hp==47)
    fresh();m=mech()
    check("48 armor HP",m.data.hp == 48)
    for i in 3: arena._shotgun_hits(false,arena.aim_vec)
    check("survives 3 close shells",not m.dead and m.data.hp == 12,m.data.hp)
    arena._shotgun_hits(false,arena.aim_vec)
    check("4th close shell destroys armor",m.dead and not arena.enemies.has(m.data))
    for distance in [2.0,4.0,6.5]:
        fresh();m=mech(distance)
        for i in 2:arena._shotgun_hits(true,arena.aim_vec)
        check("survives 2 powerful blasts at %sm"%distance,not m.dead and m.data.hp==16)
        arena._shotgun_hits(true,arena.aim_vec)
        assert_explodes(m,"third powerful blast at %sm"%distance)
    fresh();m=mech(7.1)
    arena._shotgun_hits(true,arena.aim_vec)
    check("powerful blast still respects weapon range",m.data.hp==48)
    # All normal attacks drain the same persistent body HP, including the sickle.
    for attack in ["blade_quick","sickle_quick","sickle_heavy","blade_air_quick","sickle_air_quick","sickle_air_heavy"]:
        fresh();m=mech(1.5)
        arena.action=attack;arena.act_fwd=arena.aim_vec
        var hits:=ceili(48.0/float(arena.MELEE[attack][0]))
        for i in hits-1:arena._melee_hits()
        check(attack+" accumulates body damage",not m.dead and m.data.hp>0 and m.data.hp<48)
        arena._melee_hits()
        assert_explodes(m,attack)
    # A normal revolver hit can kill the exposed pilot without pixel-perfect aiming.
    fresh();m=mech(5)
    pistol_seed(true)
    arena._pistol_hit(arena.aim_vec)
    check("revolver lucky headshot kills pilot without precise cursor",m.dead and not m.death_cut)
    m.clock=.9;m._death_tick()
    check("lucky headshot triggers explosion",m.exploded)
    fresh();m=mech(5)
    pistol_seed(false)
    arena._pistol_hit(arena.aim_vec)
    check("ordinary revolver round damages armor",not m.dead and m.data.hp==47)
    fresh();m=mech(5);m.data.dir=0;m._draw_frame()
    pistol_seed(true)
    arena._pistol_hit(arena.aim_vec)
    check("rear cabin blocks random headshot",not m.dead and m.data.hp==47)
    for i in 47:arena._pistol_hit(arena.aim_vec)
    assert_explodes(m,"revolver through armor")
    fresh();m=mech(5);m.data.dir=2;m._draw_frame()
    pistol_seed(true)
    arena._pistol_hit(arena.aim_vec)
    check("side allows random pilot headshot",m.dead)
    fresh();m=mech(1.6)
    arena.action="blade_heavy";arena.act_fwd=arena.aim_vec
    for i in 2: arena._melee_hits()
    check("survives 2 heavy blade hits",not m.dead and m.data.hp==16,m.data.hp)
    arena._melee_hits()
    check("3rd heavy blade hit kills",m.dead)
    check("three distinct parts detached",m.broken==Vector3.ONE)
    fresh();m=mech()
    var p: Vector3=m.data.p
    arena._shotgun_hits(false,arena.aim_vec)
    check("shotgun does not slide the mech",m.data.p==p)
    arena._launch(m.data,2,arena.aim_vec)
    check("cannot launch a heavy mech",m.data.h==0.0 and not arena._is_air_state(m.data))
    arena._hook_catch(m.data)
    check("hook returns without dragging mech",arena.hook=="back" and m.data.p==p)
    fresh();m=mech()
    # Pilot front, sides, rear. Pixel mask includes only depth-visible pilot geometry.
    m.data.dir=0;m._draw_frame()
    check("rear armor blocks pilot",not m.pilot_exposed(arena.hero_pos))
    m.data.dir=4;m._draw_frame()
    check("front exposes pilot",m.pilot_exposed(arena.hero_pos))
    m.data.dir=2;m._draw_frame()
    check("side exposes pilot",m.pilot_exposed(arena.hero_pos))
    # Use a direction visible to the camera and move the attacker to its front.
    m.data.dir=0;m._draw_frame()
    arena.hero_pos=m.data.p+arena._dir_vector(0)*2.0
    var mp:=pilot_pixel(m)
    check("visible pilot pixels found inside viewport",mp.x>=0 and mp.y>=0 and mp.x<960 and mp.y<540,mp)
    check("pilot pixel is an actual aim target",m.pilot_under_mouse(mp) and arena._enemy_under(mp)==m.data)
    check("transparent canvas rejects target",not m.under_mouse(arena.cam.unproject_position(m.data.p)+Vector2(120,-200)))
    arena.mouse_override=mp;arena.aim_target=m.data;arena.aim_vec=(m.data.p-arena.hero_pos).normalized()
    arena._pistol_hit(arena.aim_vec)
    check("one aimed revolver hit kills pilot",m.dead and not m.death_cut)
    fresh();m=mech()
    m.data.dir=0;m._draw_frame();arena.hero_pos=m.data.p+arena._dir_vector(0)*1.5
    arena.hero_h=.9
    arena._damage(m.data,2,"decap",arena.aim_vec,"blade_air_quick")
    check("single jump cannot reach pilot",not m.dead)
    arena.hero_h=1.3
    arena._damage(m.data,2,"decap",arena.aim_vec,"blade_air_quick")
    check("double jump blade kills pilot",m.dead and m.death_cut)
    check("head is physical debris",arena.gore.debris.any(func(d):return d.kind=="pilot_part"))
    fresh();m=mech()
    arena.hero_h=1.5
    arena._damage(m.data,2,"decap",arena.aim_vec,"blade_air_quick")
    # dir4 faces hero; reverse to put the hero behind, then hit again.
    fresh();m=mech();m.data.dir=0;m._draw_frame();arena.hero_h=1.5
    arena._damage(m.data,2,"decap",arena.aim_vec,"sickle_air_quick")
    check("rear cabin shields pilot even in air",not m.dead)
    m._draw_frame();arena.mouse_override=pilot_pixel(m)
    arena._damage(m.data,1,"decap",arena.aim_vec,"pistol")
    check("aimed shot from rear hits cabin armor",not m.dead and m.data.hp==45)
    fresh();m=mech(6)
    arena._ignite(m.data,4.0,true)
    check("ignition changes material and adds flame",m.data.charred and m.flame!=null)
    for i in 8:m._burn_tick(.5)
    check("four seconds of burn apply 8 armor damage",m.data.hp==40,m.data.hp)
    check("fire expires, scorch remains",m.flame==null and m.data.charred)
    fresh();m=mech(6)
    m.data.dir=4;m._draw_frame();m.burst_target=arena.hero_pos+Vector3.UP*.8
    m._set_state("shoot");m._ai(.01)
    check("Maxim spawns moving tracer and shell",m.bullets.size()==1 and m.fired==1)
    m.clock=.51;m._ai(.01)
    check("six rounds per burst",m.fired==6 and m.bullets.size()==6)
    m._update_bullets(.2)
    check("swept bullets hit hero",arena.hero_hp<1.0,arena.hero_hp)
    fresh();m=mech(6)
    m.burst_target=Vector3(0,.8,0);m._fire_round();arena.hero_pos=Vector3(3,0,0)
    m._update_bullets(.2)
    check("sideways dodge avoids a locked bullet",arena.hero_hp==1.0)
    fresh();m=mech(1)
    m.anim="stomp";m.anim_frame=3
    arena.hero_pos=m.anchor("foot_r");arena.hero_pos.y=0
    m._stomp()
    check("grounded hero takes stomp damage",arena.hero_hp<1.0)
    arena.hero_hp=1.0;arena.hero_h=0.7;m._stomp()
    check("jump avoids stomp",arena.hero_hp==1.0)
    fresh();m=mech(1)
    arena.invuln=true;arena._hurt_hero(.4,Vector3.UP)
    check("dash and ultimate invulnerability respected",arena.hero_hp==1.0)
    arena.invuln=false
    arena._spawn_enemy(m.data.p+Vector3.RIGHT)
    var human: Dictionary=arena.enemies[-1];human.hp=100
    var other: Dictionary=arena._spawn_mech(m.data.p+Vector3.LEFT*2)
    other.node.set_process(false)
    m.die(true,Vector3.UP,true)
    m.clock=.23;m._death_tick()
    check("no early smoke or blast",not m.smoked and not m.exploded)
    m.clock=.24;m._death_tick()
    check("smoke at 240 ms",m.smoked and not m.exploded)
    m.clock=.9;m._death_tick()
    check("blast at 900 ms damages hero and both enemy types",m.exploded and arena.hero_hp<1 and human.hp<100 and other.hp<48)
    var hp:float=arena.hero_hp;m._death_tick()
    check("blast applies only once",arena.hero_hp==hp)
    m.clock=1.07;m._death_tick();m._draw_frame()
    check("shatter starts at 1060 ms",m.data.state=="shatter" and m.anim=="shatter")
    m.clock=1.25;m._death_tick();m._draw_frame()
    check("wreck lies flat on floor",m.data.state=="wreck" and absf(m.global_basis.z.normalized().y)>.99 and m.global_position.y<.04)
    for i in 240: arena.gore.update(1.0/60.0)
    var metal: Array=arena.gore.debris.filter(func(d):return d.kind=="metal")
    check("metal debris really comes to rest",metal.size()>0 and metal.all(func(d):return d.rest))
    check("metal debris lands flat",metal.all(func(d):return absf(d.node.global_basis.z.normalized().y)>.99 and d.node.global_position.y<.04))
    fresh();m=mech(6)
    m.cooldown=0.0;m._ai(.01)
    check("gun has a visible windup",m.data.state=="windup" and m.bullets.is_empty())
    m.clock=.44;m._ai(.01)
    check("does not shoot before windup ends",m.bullets.is_empty())
    m.clock=.45;m._ai(.01)
    check("first round after 450 ms windup",m.data.state=="shoot" and m.bullets.size()==1)
    m.clock=.61;m._ai(.01)
    check("burst ends with cooldown",m.data.state=="idle" and m.cooldown>1.7)
    m._set_state("stomp");m.clock=.28;m._ai(.01)
    check("stomp waits for foot contact",not m.stomped)
    m.clock=.29;m._ai(.01)
    check("stomp impact occurs once at 290 ms",m.stomped)
    for wreck in get_nodes_in_group("mech_wreck"): wreck.remove_from_group("mech_wreck")
    fresh()
    var oldest
    for i in 41:
        var w=mech(5)
        w.die()
        w.exploded=true;w.smoked=true;w.clock=1.25;w._death_tick()
        if i==0:oldest=w
    check("40 wrecks retained",get_nodes_in_group("mech_wreck").size()==40)
    check("oldest wreck fades for one second",oldest.fade==1.0)
    oldest._process(.5)
    check("fade progresses",is_equal_approx(oldest.mat.get_shader_parameter("opacity"),.5))
    for name in ["mech_maxim","mech_step","mech_stomp","mech_steam","mech_metal_hit","mech_explosion"]:
        check("sound exists: "+name,arena.sfx.has(name))
    check("gun, hit, steam and blast emitted",["mech_maxim","mech_metal_hit","mech_steam","mech_explosion"].all(func(n):return n in arena.sfx.played))
    arena.queue_free()
    await process_frame
    change_scene_to_file("res://scenes/test_arena.tscn")
    await process_frame
    await process_frame
    arena=current_scene
    check("main scene spawns one mech and six humans",arena.enemies.size()==7 and arena.enemies.filter(func(e):return e.get("kind", "")=="mech").size()==1)
    for i in 3:arena._spawn_mech(Vector3(i+2,0,3))
    check("sandbox limits active mechs to four",arena._spawn_mech(Vector3(5,0,5)).is_empty())
    for player in arena.sfx.players:player.stop()
    arena.queue_free()
    await process_frame
    await create_timer(.1).timeout
    print("ROUND18: %d checks, %d failures"%[checks,fails])
    quit(1 if fails else 0)
