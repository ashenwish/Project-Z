extends SceneTree
## Run with the real renderer: normal mouse, button handler, gun animation and FX damage.
var arena
var mech
var fails := 0
var folder := ""

func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):folder=arg.trim_prefix("--out=")
    if not folder.is_empty():DirAccess.make_dir_recursive_absolute(folder)
    arena=load("res://scripts/test_arena.gd").new()
    root.add_child(arena)
    run.call_deferred()

func check(label: String, ok: bool) -> void:
    print(("ok " if ok else "FAIL ")+label)
    if not ok:fails+=1

func advance(frames: int, dying := false) -> void:
    for i in frames:
        arena._process(1.0/60)
        if dying:mech._process(1.0/60)
        await process_frame

func shot(name: String) -> void:
    if folder.is_empty():return
    mech._draw_frame()
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(folder+"/"+name+".png")

func run() -> void:
    await create_timer(.1).timeout
    arena.set_process(false);arena.sfx.muted=true
    for e in arena.enemies:
        e.node.queue_free();e.shadow.queue_free()
    arena.enemies.clear();arena.respawn.clear()
    arena.module="shotgun"
    var e:Dictionary=arena._spawn_mech(arena._dir_vector(4)*3.0)
    mech=e.node;mech.set_process(false);e.dir=0
    await advance(45)
    check("normal mouse has no test override",arena.mouse_override==null)
    for i in 3:
        var cursor:Vector2=arena.cam.unproject_position(e.p+Vector3.UP*1.4)
        Input.warp_mouse(cursor)
        await advance(2)
        var event:=InputEventMouseButton.new()
        event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true
        arena._unhandled_input(event)
        await advance(60)
        check("normal right click %d applies 16 damage"%(i+1),e.hp==48-16*(i+1))
        await shot("shot_%d"%(i+1))
    check("three real clicks consumed six shells",arena.ammo.shotgun==2)
    check("normal clicks kill the mech",mech.dead)
    if mech.dead:
        await advance(58,true)
        check("normal clicks lead to explosion",mech.exploded)
        await shot("explosion")
        await advance(40,true)
        check("normal clicks leave floor wreck",e.state=="wreck")
        await shot("wreck")
    arena.queue_free()
    await process_frame
    await create_timer(.1).timeout
    print("LIVE MOUSE failures: %d"%fails)
    quit(1 if fails else 0)
