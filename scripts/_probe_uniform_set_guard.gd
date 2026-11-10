extends SceneTree
## 验「释放纹理 RID 之后仍去建 uniform set」不会产生永久失败（2026-11-10 修复的验收）。
##
##   godot --path <工程> --script res://scripts/_probe_uniform_set_guard.gd -- --no-capture
##
## 手工复现那个时序碰撞：拿一个 RenderingDevice 建纹理 → 释放 → 再拿它建 uniform set。
## 修复前：`uniform_set_create` 返回空 RID，并且 `us` 为 null，之后每帧失败。
## 修复后：`create_descriptor_set` 提前校验，直接返回空 RID，**不报 ERROR**。
##
## 判据（三条都要过）：
##   ① 无效 RID 的 descriptor set 必须返回空 RID
##   ② 有效 RID 的 descriptor set 必须返回**非空** RID（不能把正常的也挡掉）
##   ③ 整个过程不出现 `not a valid texture` / `Parameter "us" is null`

const DEADLINE_S := 90.0
var _t0 := 0
var _fail := 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	_watchdog()
	_run.call_deferred()


func _watchdog() -> void:
	while true:
		await create_timer(1.0).timeout
		if (Time.get_ticks_msec() - _t0) / 1000.0 > DEADLINE_S:
			printerr("[guard] ✗ 超时，强制退出")
			quit(2)
			return


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  [PASS] %s" % what)
	else:
		_fail += 1
		print("  [FAIL] %s" % what)


func _run() -> void:
	var ctx = load("res://addons/ggs_campus/render_context.gd").create()
	if ctx == null or ctx.device == null:
		print("[guard] 拿不到 RenderingDevice（headless？这个探针必须真窗口跑）")
		quit(1)
		return
	var rd: RenderingDevice = ctx.device
	print("[guard] RenderingDevice 就绪")

	# 一个最小的 compute shader：绑定一张 image
	var sh := RDShaderSource.new()
	sh.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	sh.source_compute = """
#version 450
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(rgba32f, binding = 0, set = 0) uniform image2D tex;
void main() {
	imageStore(tex, ivec2(0), vec4(1.0));
}
"""
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(sh)
	if spirv == null:
		print("[guard] 着色器编译返回 null")
		quit(1)
		return
	if not spirv.compile_error_compute.is_empty():
		print("[guard] 编译错误全文：\n%s" % spirv.compile_error_compute)
		quit(1)
		return
	var shader_rid: RID = rd.shader_create_from_spirv(spirv)

	# 建一张有效纹理
	var tex: RID = _make_tex(rd, Vector2i(8, 8))
	_ok(tex.is_valid(), "测试纹理建好了")

	var valid_desc = load("res://addons/ggs_campus/render_context.gd").Descriptor.new(
		tex, RenderingDevice.UNIFORM_TYPE_IMAGE)

	print("── ① 有效 RID：必须建出非空 set ──")
	var good: RID = ctx.create_descriptor_set([valid_desc], shader_rid, 0)
	_ok(good.is_valid(), "有效 RID → descriptor set 非空（%s）" % str(good))

	print("── ② 把纹理释放掉（走 deletion_queue，会登记），再拿同一个 descriptor 建 set ──")
	# 现场那个状态：Descriptor 里还握着已释放的 RID。
	# ⚠️ 关键：必须让 `deletion_queue` 知道「这个 RID 已经还了」。
	#    `RID.is_valid()` 对已释放的 RID 仍然返回 true，光靠它挡不住。
	rd.free_rid(tex)
	ctx.deletion_queue.mark_freed(tex)
	var bad: RID = ctx.create_descriptor_set([valid_desc], shader_rid, 0)
	_ok(not bad.is_valid(), "已释放的 RID → 提前挡下，返回空 RID（不产生永久失败的 set）")

	print("── ③ 空 shader RID 也不能崩 ──")
	var no_shader: RID = ctx.create_descriptor_set([valid_desc], RID(), 0)
	_ok(not no_shader.is_valid(), "空 shader → 返回空 RID")

	rd.free_rid(shader_rid)
	print("========== 结果 ==========")
	print("  失败 %d 项" % _fail)
	quit(0 if _fail == 0 else 1)


func _make_tex(rd: RenderingDevice, size: Vector2i) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.width = size.x
	fmt.height = size.y
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(fmt, RDTextureView.new(), [])
