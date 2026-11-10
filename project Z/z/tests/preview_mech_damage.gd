extends SceneTree
## Actual weapon hit routes, followed through death, blast and wreck in the renderer.
var arena
var m
var out := ""

func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
    if out.is_empty():quit(1);return
    DirAccess.make_dir_recursive_absolute(out)
    arena=load("res://scripts/test_arena.gd").new()
    root.add_child(arena)
    run.call_deferred()

func shot(label: String) -> void:
    m._draw_frame()
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(out+"/"+label+".png")

func advance(seconds: float) -> void:
    for i in ceili(seconds*60):
        m._process(1.0/60)
        arena.gore.update(1.0/60)
        await process_frame

func run() -> void:
    await create_timer(.1).timeout
    for e in arena.enemies:
        e.node.queue_free();e.shadow.queue_free()
    arena.enemies.clear();arena.respawn.clear();arena.sfx.muted=true
    var e:Dictionary=arena._spawn_mech(arena._dir_vector(4)*4+arena._dir_vector(2))
    m=e.node;m.set_process(false)
    arena.mouse_override=Vector2(940,520)
    for i in 45:arena._process(1.0/60)
    arena.set_process(false)
    m.data.dir=0;m._draw_frame()
    arena.aim_vec=m.data.p.normalized()
    await shot("00_before")
    for i in 2:arena._shotgun_hits(true,arena.aim_vec)
    assert(m.data.hp==16 and not m.dead)
    await shot("01_two_powerful_shots")
    arena._shotgun_hits(true,arena.aim_vec)
    assert(m.dead)
    await shot("02_third_shot_dead")
    await advance(.95)
    assert(m.exploded)
    await shot("03_shotgun_explosion")
    await advance(1)
    await shot("04_shotgun_wreck")
    var pos:Vector3=m.data.p
    m.queue_free()
    e=arena._spawn_mech(pos);m=e.node;m.set_process(false)
    m.data.dir=0;m._draw_frame()
    var rng:=RandomNumberGenerator.new()
    for seed_value in 1000:
        rng.seed=seed_value
        if rng.randf()<arena.Mech.PILOT_HEADSHOT_CHANCE:
            arena.rng.seed=seed_value
            break
    arena.hero_hp=1.0
    arena._pistol_hit(arena.aim_vec)
    assert(m.dead)
    await shot("05_revolver_headshot")
    await advance(.95)
    assert(m.exploded)
    await shot("06_revolver_explosion")
    print("PASS shotgun and revolver visual routes")
    arena.queue_free()
    await process_frame
    quit()
