extends SceneTree
## Rendered resource-lifetime regression. Run through the private desktop launcher.
const OffWin := preload("res://scripts/offscreen_window.gd")
const FX := preload("res://scripts/vfx.gd")

class TestGun extends "res://scripts/companion_gun.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class TestWeapon extends "res://scripts/weapon.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var _world: Node3D
var _gun: TestGun
var _weapon: TestWeapon
var _passed := 0
var _failed := 0

func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[combat-fx] ", "PASS " if ok else "FAIL ", label)

func _pipelines() -> Vector2i:
	return Vector2i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))

func _effects() -> void:
	FX.impact(_world, Vector3.ZERO, Color(1, .3, .2))
	_gun.call("_beam", Vector3(-2, 1, 0), Vector3(2, 1, 0), .03, Color(.6, .8, 1), .08)
	_gun.call("_glow_quad", Vector3.ZERO, Color(1, .7, .3), .5, .1)
	_weapon.call("_muzzle_flash", Vector3.ZERO, Vector3.FORWARD)
	_weapon.call("_spawn_impact", Vector3.ZERO, Vector3.UP)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	await OffWin.apply(self, Vector2i(960, 540))
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_world = Node3D.new()
	root.add_child(_world)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(0, 5, 12)
	camera.look_at(Vector3.ZERO)
	_gun = TestGun.new()
	_world.add_child(_gun)
	_gun.set("_fx_root", _world)
	_weapon = TestWeapon.new()
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	_weapon.add_child(muzzle)
	_world.add_child(_weapon)
	_weapon.set("_fx_root", _world)

	var red := Color(1, .2, .1, .8)
	var blue := Color(.1, .3, 1, .9)
	_gun.call("_beam", Vector3.ZERO, Vector3(0, 0, -4), .02, red, .6, 2.0)
	var first := _world.get_child(_world.get_child_count() - 1) as MeshInstance3D
	_gun.call("_beam", Vector3.ZERO, Vector3(0, 0, -8), .05, blue, .6, 3.0)
	var second := _world.get_child(_world.get_child_count() - 1) as MeshInstance3D
	_check(first.mesh == second.mesh, "different beam widths share geometry")
	_check(first.scale.is_equal_approx(Vector3(.02, .02, 4)), "first beam dimensions preserved")
	_check(second.scale.is_equal_approx(Vector3(.05, .05, 8)), "second beam dimensions preserved")
	var red_material := first.material_override as StandardMaterial3D
	var blue_material := second.material_override as StandardMaterial3D
	_check(red_material != blue_material and red_material.albedo_color == red and blue_material.albedo_color == blue,
		"simultaneous colors remain independent")
	_check(is_equal_approx(red_material.emission_energy_multiplier, 2) and is_equal_approx(blue_material.emission_energy_multiplier, 3),
		"per-style emission preserved")
	await create_timer(.2).timeout
	_gun.call("_beam", Vector3.ZERO, Vector3(0, 0, -4), .02, red, .6, 2.0)
	var later := _world.get_child(_world.get_child_count() - 1) as MeshInstance3D
	_check(later.material_override == red_material, "repeated shots retain their compiled material")
	_check(first.transparency > .1 and later.transparency < .01 and red_material.albedo_color == red,
		"fading one instance never dims a new shot")
	await create_timer(.7).timeout

	var p1 := FX.burst(_world, Vector3.ZERO, red, 12, 1.0, 10.0, .3)
	var p2 := FX.burst(_world, Vector3.ZERO, red, 24, 1.0, 10.0, .6)
	var p3 := FX.burst(_world, Vector3.ZERO, blue, 12, 1.0, 10.0, .3)
	_check(p1.process_material == p2.process_material and p1.draw_pass_1 == p2.draw_pass_1,
		"particle count and lifetime use independent emitters with shared immutable resources")
	_check(p1.amount == 12 and p2.amount == 24 and is_equal_approx(p1.lifetime, .3) and is_equal_approx(p2.lifetime, .6),
		"particle counts and lifetimes preserved")
	_check(p1.process_material != p3.process_material and (p3.process_material as ParticleProcessMaterial).color == blue,
		"different particle colors never overwrite each other")
	var particle_ref := weakref(p1)
	await create_timer(1.3).timeout
	_check(particle_ref.get_ref() == null, "finished emitters are freed")

	# Let effects finish between replays: the original implementation rebuilt
	# pipelines after their last mesh/material owner disappeared.
	for i in 2:
		_effects()
		await create_timer(1.6).timeout
	var before := _pipelines()
	for i in 4:
		_effects()
		await create_timer(1.6).timeout
	_check(_pipelines() == before, "replaying finished effects adds zero compiled pipelines")
	_check(_world.get_child_count() == 3, "effects clean up all transient nodes")
	_check(bool(OffWin.is_safe()[0]), "offscreen and uncaptured mouse")
	var bosses_before := get_nodes_in_group("bosses").size()
	var targets_before := get_nodes_in_group("targets").size()
	# Construct the real normal-shot resources without processing gameplay.
	var source_weapon := preload("res://scripts/weapon.gd").new()
	source_weapon.process_mode = Node.PROCESS_MODE_DISABLED
	var source_muzzle := Marker3D.new()
	source_muzzle.name = "Muzzle"
	source_weapon.add_child(source_muzzle)
	_world.add_child(source_weapon)
	_weapon.set("_bolt_mesh", source_weapon.get("_bolt_mesh"))
	_weapon.set("_bolt_mat", source_weapon.get("_bolt_mat"))
	_check(_weapon.get("_bolt_mesh") != null and _weapon.get("_bolt_mat") != null,
		"normal-shot regression uses the production weapon mesh and material")
	var warmer := preload("res://scripts/combat_fx_warmup.gd").new()
	_world.add_child(warmer)
	root.use_taa = true
	warmer.start(_world.get_world_3d(), root, source_weapon)
	var preview := warmer.get_child(0) as SubViewport
	_check(preview.use_taa == root.use_taa and preview.msaa_3d == root.msaa_3d
		and preview.screen_space_aa == root.screen_space_aa and preview.use_debanding == root.use_debanding,
		"private warmup inherits the production antialiasing and motion-vector variants")
	var deadline := Time.get_ticks_msec() + 15000
	while not warmer.finished and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(warmer.finished, "private effect viewport completes warmup")
	var warmed_pipelines := _pipelines()
	# Use the actual party palette here. Arbitrary styles in _effects() have
	# their own replay/cache test above and are not promised arena prewarm.
	for col in [Color(1, .62, .78), Color(.45, 1, .78), Color(1, .82, .45), Color(.72, .4, 1)]:
		_gun.call("_beam", Vector3(-2, 1, 0), Vector3(2, 1, 0), .03, col, .08, 1.8)
		_gun.call("_glow_quad", Vector3.ZERO, col, .5, .1)
	_weapon.call("_spawn_laser_bolt", Vector3(-1, 1, 0), Vector3(1, 1, 0))
	_weapon.call("_muzzle_flash", Vector3.ZERO, Vector3.FORWARD)
	_weapon.call("_spawn_impact", Vector3.ZERO, Vector3.UP)
	await RenderingServer.frame_post_draw
	await create_timer(1.6).timeout
	_check(_pipelines() == warmed_pipelines, "first TAA gameplay effects reuse the warmed material pipelines")
	_weapon.call("_advance_tracers", 10.0)
	_check(get_nodes_in_group("bosses").size() == bosses_before and get_nodes_in_group("targets").size() == targets_before,
		"warmup registers no combat targets")
	var warmer_ref := weakref(warmer)
	_world.queue_free()
	await process_frame
	await create_timer(.2).timeout
	_check(warmer_ref.get_ref() == null, "scene exit releases preview models and private viewport")
	print("[combat-fx] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)
