extends SceneTree
## Render the actual game at native resolution through the full mech lifecycle.
## godot --path . -s res://tests/preview_mech.gd -- --out=absolute/directory
var arena
var folder := ""
var m

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--out="): folder=a.trim_prefix("--out=")
    if folder.is_empty(): quit(1);return
    DirAccess.make_dir_recursive_absolute(folder)
    arena=load("res://scripts/test_arena.gd").new()
    root.add_child(arena)
    run.call_deferred()

func shot(label: String) -> void:
    m._draw_frame()
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(folder+"/"+label+".png")

func tick(seconds: float) -> void:
    var n:=ceili(seconds*60)
    for i in n:
        m._process(1.0/60)
        arena.gore.update(1.0/60)
        await process_frame

func run() -> void:
    await create_timer(.15).timeout
    for e in arena.enemies:
        e.node.queue_free();e.shadow.queue_free()
    arena.enemies.clear();arena.respawn.clear()
    arena.sfx.muted=true
    arena.hero_hp=1.0
    var e:Dictionary=arena._spawn_mech(arena._dir_vector(4)*4.0+arena._dir_vector(2)*1.0)
    m=e.node;m.set_process(false)
    for i in 45:arena._process(1.0/60)
    arena.set_process(false)
    m.data.dir=0;m._set_state("idle")
    await shot("00_idle")
    m.data.shadow.visible=false
    await shot("01_no_shadow")
    m.data.shadow.visible=true
    for d in 8:
        m.data.dir=d
        await shot("direction_%d"%d)
    m.data.dir=0;m._set_state("walk");m.clock=.375
    await shot("02_walk")
    m._set_state("shoot");m.burst_target=arena.hero_pos+Vector3.UP*.8
    m._fire_round();arena.gore.update(.016)
    await shot("03_shoot")
    await tick(.13)
    await shot("04_burst")
    m._set_state("stomp");m.clock=.29;m._stomp()
    await shot("05_stomp")
    m.hurt(5,"split",Vector3.RIGHT,"blade_heavy")
    m.clock=.08
    await shot("06_hit_part")
    m.ignite();m._draw_frame()
    await tick(.1)
    await shot("07_burning")
    m.die(true,Vector3.RIGHT,true)
    await shot("08_pilot_dead")
    await tick(.3)
    await shot("09_cabin_smoke")
    await tick(.616667)
    await shot("10_blast")
    await tick(.183333)
    await shot("11_shatter")
    await tick(.2)
    await shot("12_wreck")
    await tick(2)
    await shot("13_debris_floor")
    m.fade=1.0
    m._process(.5)
    await shot("14_wreck_fading")
    print("MECH VISUAL CAPTURE COMPLETE")
    arena.queue_free()
    await process_frame
    quit()
