// 炫彩霸王龙优香 · **彩虹流光**
//
// 用户 2026-11-11：「炫彩要动态的，像洛克王国一样」，选的是「彩虹流光
// （颜色随时间流转）」。所以这不是"换个颜色"，而是**颜色沿身体跑起来**。
//
// ── 做法 ──
// 用一个 **object space 的空间坐标**当相位，让色相随时间推进：
//   色相 = (物体空间位置在流动方向上的投影 / 波长) + 时间 × 速度
// 这样：
//   · 颜色是**连续渐变**的条带，从红→黄→绿→青→蓝→紫→红 循环；
//   · 条带会**沿身体移动**（+时间项），看起来像彩光在皮上流；
//   · 用物体空间而不是屏幕空间 ⇒ 相机怎么转，条带都贴着身体，不会"贴脸"。
//
// ── 为什么用三个方向叠加，而不是一条直线 ──
// 一条直线从头流到尾太"机械"，像一块斜纹布。这里把三个不同频率/方向的
// 波叠加（沿 Z 主流动 + 沿 Y 轻微扫动 + 一点噪声扰动），
// 色相带就会**弯曲、错开**，更接近"炫彩"而不是"条纹"。
//
// ── 贴图怎么办 ──
// 原贴图的明暗细节**保留**（albedo_texture 的灰度当调制），否则恐龙会变成
// 一个没有体积感的彩色气球。所以：最终颜色 = 彩虹色 × (原贴图亮度 × 2)。
//
// ── 用法（`boss.gd` 里按名字认出这只 Boss 后套用）──
//   var m := ShaderMaterial.new()
//   m.shader = load("res://shaders/rainbow_flow.gdshader")
//   m.set_shader_parameter("source_albedo", 原贴图)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// 原贴图（取它的亮度做明暗调制；不给就纯彩虹）
uniform sampler2D source_albedo : source_color, filter_linear_mipmap, hint_default_white;
// 有没有原贴图（0 = 没有，直接用纯彩虹）
uniform bool use_source_albedo = true;

// 流动速度（色相每秒前进多少个周期）
uniform float flow_speed = 0.45;
// 主流动波长（米）。越小条带越密
uniform float wave_length = 2.2;
// 主流动方向（物体空间）。默认沿身体长轴 Z
uniform vec3 flow_axis = vec3(0.0, 0.0, 1.0);
// 第二条波的强度/频率（让条带弯曲，不呆板）
uniform float warp_strength = 0.35;
uniform float warp_freq = 5.5;
// 色相偏移（整体调色，0 = 从红开始）
uniform float hue_offset = 0.0;
// 饱和度 / 亮度
uniform float saturation = 0.95;
uniform float brightness = 1.15;
// 自发光强度：让它在暗处也"彩色发亮"，这是彩虹流光的关键
uniform float glow_strength = 0.55;
// 起伏（色相带的对比，1 = 全彩虹，0 = 单色）
uniform float rainbow_mix = 1.0;

varying vec3 obj_pos;

void vertex() {
	// 物体空间坐标：相机怎么转，条带都贴在身上
	obj_pos = VERTEX;
}

// HSV → RGB（标准公式，不依赖内置函数，跨版本稳）
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	// ── 相位：三条波叠加 ──
	vec3 ax = normalize(flow_axis);
	float base = dot(obj_pos, ax) / max(wave_length, 0.01);
	// 侧向扫动：让条带弯曲
	float warp = sin(obj_pos.y * warp_freq + TIME * 0.7) * warp_strength
		+ sin(obj_pos.x * warp_freq * 0.7 - TIME * 0.5) * warp_strength * 0.6;
	float phase = base + warp + TIME * flow_speed + hue_offset;

	// ── 色相 ──
	float h = fract(phase);
	vec3 rainbow = hsv2rgb(vec3(h, saturation, 1.0));

	// ── 原贴图明暗调制 ──
	vec3 tint = vec3(brightness);
	if (use_source_albedo) {
		vec3 src = texture(source_albedo, UV).rgb;
		// 用亮度调制（保留细节），并稍微提对比免得糊成一片
		float lum = dot(src, vec3(0.2126, 0.7152, 0.0722));
		tint *= mix(1.0, lum * 2.0, 0.85);
	}

	vec3 col = mix(vec3(brightness), rainbow * tint, rainbow_mix);

	ALBEDO = col * 0.55;          // 受光部分压一点，靠自发光提亮
	ROUGHNESS = 0.42;
	METALLIC = 0.15;
	// 自发光：让彩光本身亮起来（否则暗处就是一片脏）
	EMISSION = col * glow_strength;
}
