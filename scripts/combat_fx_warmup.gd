extends Node
## Render the production effects in a tiny private world during arena setup.
## These visual-only drivers never register targets, fire damage rays or play SFX.
const FX := preload("res://scripts/vfx.gd")

class VisualGun extends "res://scripts/companion_gun.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class VisualWeapon extends "res://scripts/weapon.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class VisualBoss extends "res://scripts/yuuka_horror_boss.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

class VisualClone extends "res://scripts/horror_clone.gd":
	func _ready() -> void:
		# Reuse imported geometry, but never run Boss._build_model(), which tints
		# source materials. Only this preview instance receives ghost overrides.
		if not ResourceLoader.exists(model_path): return
		model = (load(model_path) as PackedScene).instantiate()
		add_child(model)
		_apply_ghost_skin()
	func _physics_process(_delta: float) -> void: pass

var finished := false

func start(source_world: World3D) -> void:
	if DisplayServer.get_name() == "headless":
		finished = true
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.world_3d = World3D.new()
	viewport.world_3d.environment = source_world.environment
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 5, 12)
	camera.look_at(Vector3(0, 1, 0))
	var weapon := VisualWeapon.new()
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	weapon.add_child(muzzle)
	world.add_child(weapon)
	weapon.set("_fx_root", world)
	weapon.call("_muzzle_flash", Vector3.ZERO, Vector3.FORWARD)
	weapon.call("_spawn_impact", Vector3.ZERO, Vector3.UP)
	await RenderingServer.frame_post_draw
	weapon.call("_muzzle_flash_beam", Vector3.ZERO)
	weapon.call("_spawn_beam_impact", Vector3.ZERO, Vector3.UP)
	var gun := VisualGun.new()
	world.add_child(gun)
	gun.set("_fx_root", world)
	for col in [Color(1, .62, .78), Color(.45, 1, .78), Color(1, .82, .45), Color(.72, .4, 1)]:
		gun.call("_beam", Vector3(-2, 1, 0), Vector3(2, 1, 0), .03, col, .1, 1.8)
		gun.call("_glow_quad", Vector3.ZERO, col, .5, .1)
	await RenderingServer.frame_post_draw
	var boss := VisualBoss.new()
	world.add_child(boss)
	boss.call("_spawn_orb", Vector3(0, 1, -3), "rapid")
	boss.call("_blast_fx", Vector3.ZERO, false)
	boss.call("_make_disc", Vector3.ZERO, 4.5, Color(1, .3, .1, .4))
	FX.burst(world, Vector3.ZERO, Color(1, .18, .25), 26, 1.4, 12, .5, -3)
	FX.ring(world, Vector3.ZERO, Color(1, .2, .3, .9), 7, .55)
	await RenderingServer.frame_post_draw
	var clone := VisualClone.new()
	world.add_child(clone)
	clone.position.x = 2
	await RenderingServer.frame_post_draw
	# Keep skin variants alive without animation or repeated rendering. The
	# entire private world is freed with the arena's resource warmup owner.
	clone.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(1.3).timeout
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	finished = true
