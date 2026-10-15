@tool
@icon("res://addons/gdgs/editor/icons/gaussian_splat_node.svg")
extends VisualInstance3D
class_name GaussianSplatNode

const SELECTOR_SCRIPT := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")
# Guarded load, not preload: runtime/lighting/ is deletable, and losing it must
# only cost the shadow caster. GaussianLightingResource itself lives in
# runtime/resources/ (the data-contract layer) precisely so the export below
# keeps parsing when runtime/lighting/ is gone.
const PROXY_SHADOW_CASTER_PATH := "res://addons/gdgs/runtime/lighting/proxy_shadow_caster.gd"

@export var gaussian: GaussianResource:
	set(value):
		_set_gaussian(value)
	get:
		return _gaussian

@export_group("Relighting")
## Baked lighting proxy: per-splat surface normals plus the proxy mesh used as
## a shadow caster. Bake it from the GDGS Lighting inspector panel.
@export var lighting: GaussianLightingResource:
	set(value):
		_set_lighting(value)
	get:
		return _lighting

## Mounts the baked proxy mesh as a SHADOWS_ONLY MeshInstance3D so this
## Gaussian scene casts shadows onto ordinary Godot geometry.
@export var relight_cast_shadows: bool = true:
	set(value):
		_set_relight_cast_shadows(value)
	get:
		return _relight_cast_shadows

## Light the splats from the scene's Light3D nodes using the baked proxy
## normals. Needs a `lighting` resource; ignored without one.
@export var relight_enabled: bool = false
## Colour floor where no light reaches. This is the "darken everything, let
## only lit regions climb back" control: 1.0 leaves the splats at their
## original brightness and only adds light on top.
@export_range(0.0, 1.0, 0.01) var relight_unlit_level: float = 0.25
## How strongly gathered light brightens the splats.
@export_range(0.0, 4.0, 0.01) var relight_light_gain: float = 1.0
## Ambient term, modulated by the baked ambient occlusion.
@export var relight_ambient: Color = Color(0.25, 0.25, 0.25, 1.0)
## Use only the spherical-harmonics DC term as the base colour. Baked
## view-dependent specular fights new lighting; this is the closest thing the
## data has to an albedo.
@export var relight_dc_only: bool = false

@export_group("Dynamic")
## 逐高斯动态：错峰坍缩 + 布朗漂移。
##
## 这组只是**数据**，本节点不跑任何逻辑 —— raster_render_backend.gd 每帧轮询
## 它们并推入材质，所以脚本赋值、检测器拖动、AnimationPlayer/Sequencer 驱动
## 都会被同一条路径接住。
##
## ⚠️ 仅 Raster 后端实现（project.godot 的 gdgs/rendering/backend 必须是 "Raster"）。
##    Compute 侧没有对应着色器逻辑，设了也不会有反应。
@export var dynamic_active := false
## 全局进度：0 = 原样，1 = 全部塌完。
@export_range(0.0, 1.0, 0.001) var dynamic_t := 0.0
## 收敛点。坐标系与高斯位置相同（源/局部坐标），不是世界坐标。
@export var dynamic_center := Vector3.ZERO
## 错峰：0 = 所有高斯同时动；0.6 = 起播时刻在 [0, 0.6] 内随机铺开，
## 但所有高斯仍在 dynamic_t = 1 处收齐。上限 0.95 以免尾部拖太长。
@export_range(0.0, 0.95, 0.01) var dynamic_stagger := 0.6
@export_enum("linear", "in_cubic", "in_quad", "smoothstep") var dynamic_ease := "in_cubic"
## 塌到底时保留的缩放。不取 0：全 0 的协方差会让椭球退化。
@export_range(0.0, 0.1, 0.0001) var dynamic_min_scale := 0.0004
## 随坍缩淡出：0 = 亮度不变，1 = 塌到底时完全透明。
@export_range(0.0, 1.0, 0.01) var dynamic_fade := 0.0
## 换一批随机相位/频率（错峰顺序与漂移方向都会变）。
@export var dynamic_seed := 0
## 布朗漂移幅度，单位是源坐标。位移以原位置为中心，硬上界 = 1.5 × 本值
## （两段八度：amp + 0.5×amp）。建议取场景尺寸的千分之几。
@export_range(0.0, 5.0, 0.0001) var dynamic_brownian_amp := 0.0
## 漂移频率（Hz），越大抖得越快。
@export_range(0.0, 20.0, 0.01) var dynamic_brownian_freq := 1.0
## 漂移用的时间（秒），由外部驱动，便于暂停/变速/定格。
@export var dynamic_brownian_time := 0.0

var _gaussian: GaussianResource
var _lighting: GaussianLightingResource
var _relight_cast_shadows := true
var _local_aabb: AABB = AABB()
var _aabb_valid := false

static func get_model_orientation_correction() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -PI)), Vector3.ZERO)

func _enter_tree() -> void:
	_apply_default_orientation_if_needed()
	set_notify_transform(true)
	call_deferred("_register_with_backend")

func _ready() -> void:
	_connect_gaussian()
	if not _aabb_valid:
		_rebuild_aabb()
	_sync_lighting_proxy()

func _exit_tree() -> void:
	_unregister_from_backend()
	_disconnect_gaussian()

func _get_aabb() -> AABB:
	if _aabb_valid:
		return _local_aabb
	return AABB()

func _set_gaussian(value: GaussianResource) -> void:
	if _gaussian == value:
		return
	_disconnect_gaussian()
	_gaussian = value
	_connect_gaussian()
	_rebuild_aabb()
	if is_inside_tree():
		_mark_backend_resource_dirty()
	if Engine.is_editor_hint():
		update_gizmos()

func _set_lighting(value: GaussianLightingResource) -> void:
	if _lighting == value:
		return
	_lighting = value
	_sync_lighting_proxy()
	# Backends that cache the bake (Compute uploads it into a storage buffer at
	# registration time) will otherwise keep rendering the state this node had
	# when it entered the tree — which is `null` for the common order of adding
	# the node first and assigning the resource afterwards.
	_mark_backend_lighting_dirty()

func _set_relight_cast_shadows(value: bool) -> void:
	if _relight_cast_shadows == value:
		return
	_relight_cast_shadows = value
	_sync_lighting_proxy()

# Mounting the proxy is the one piece of relighting that is free: a
# SHADOWS_ONLY MeshInstance3D is invisible to the camera but still writes into
# every light's shadow map, so the splat scene shadows ordinary geometry under
# both backends. Lighting the splats themselves is the light rig's job.
func _sync_lighting_proxy() -> void:
	if not is_inside_tree():
		return
	var caster_script := _load_proxy_shadow_caster()
	if caster_script == null:
		return
	caster_script.sync(self, _lighting, _relight_cast_shadows)

func _load_proxy_shadow_caster() -> GDScript:
	if not ResourceLoader.exists(PROXY_SHADOW_CASTER_PATH, "Script"):
		return null
	var script: Variant = load(PROXY_SHADOW_CASTER_PATH)
	if script == null or not (script is GDScript):
		return null
	return script as GDScript

func _connect_gaussian() -> void:
	if _gaussian == null:
		return
	var callable := Callable(self, "_on_gaussian_changed")
	if not _gaussian.changed.is_connected(callable):
		_gaussian.changed.connect(callable)

func _disconnect_gaussian() -> void:
	if _gaussian == null:
		return
	var callable := Callable(self, "_on_gaussian_changed")
	if _gaussian.changed.is_connected(callable):
		_gaussian.changed.disconnect(callable)

func _on_gaussian_changed() -> void:
	_rebuild_aabb()
	if is_inside_tree():
		_mark_backend_resource_dirty()
	if Engine.is_editor_hint():
		update_gizmos()

func _rebuild_aabb() -> void:
	_aabb_valid = false
	if _gaussian == null:
		_local_aabb = AABB()
		return
	_local_aabb = _gaussian.aabb
	_aabb_valid = true

func _apply_default_orientation_if_needed() -> void:
	if not transform.basis.orthonormalized().is_equal_approx(Basis.IDENTITY):
		return
	transform = transform * get_model_orientation_correction()

# The node never talks to a concrete backend: the selector resolves the active
# one (Compute or Raster) once per session and every node shares that instance.
func _register_with_backend() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.attach_node(self)

func _unregister_from_backend() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.detach_node(self)

func _mark_backend_resource_dirty() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.notify_resource_changed(self)

func _mark_backend_transform_dirty() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null:
		backend.notify_transform_changed(self)

func _mark_backend_lighting_dirty() -> void:
	if not is_inside_tree():
		return
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null and backend.has_method("notify_lighting_changed"):
		backend.notify_lighting_changed(self)

func _notification(what: int) -> void:
	if (what == NOTIFICATION_TRANSFORM_CHANGED
		or what == NOTIFICATION_VISIBILITY_CHANGED) and is_inside_tree():
		_mark_backend_transform_dirty()
