shader_type spatial;
// 「封锁罩」——半透明红色能量墙 + 上下密集红色扫描线。
//
// 用途：第二关（长理校园）打完三只霸王龙，`scripts/arena_lock.gd` 把它套在
// 校园围墙同一圈 footprint 上，墙从地里升起来锁住玩家（用户 2026-11-13 要求）。
//
// 为什么用 shader 画线条、而不是几百个细长盒子：
//   · 「密集线条」要的是一屏上百条，做成几何体就是上百个 draw call；
//   · 线条必须**滚动**（静态线看着像贴纸），shader 里 `TIME` 一句话的事；
//   · 一个 BoxMesh 的每个侧面 UV 都是 0~1，`UV.y * line_count` 天然就是
//     「这一面从上到下排 N 条」，不用管墙有多长。
//
// 关键取舍：
//   · `unshaded` —— 场景里的 glow 只有 0.12~0.25（`next_level.tscn`），
//     走受光路径的话红墙会被压成脏褐；unshaded + 超过 1.0 的颜色值
//     能自己吃到辉光。
//   · `cull_disabled` —— 玩家在墙内侧看，法线朝外的那面会被剔掉，
//     必须双面。
//   · `blend_mix` —— 半透明。⚠️ 不要开 `depth_draw_always`，
//     否则墙会把身后的泼溅整片挡掉（透明物体不该写深度）。
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled;

// 底色（大片红雾）。alpha 决定「半透明」到什么程度。
uniform vec4 fill_color : source_color = vec4(0.85, 0.04, 0.05, 0.20);
// 线条颜色。用超过 1.0 的亮度让辉光吃进去。
uniform vec4 line_color : source_color = vec4(1.0, 0.16, 0.10, 0.85);

// 一面墙上排多少条线。越大越密。
uniform float line_count = 14.0;
// 单条线占一个周期的比例（0.05 = 很细，0.5 = 线比缝还宽）。
uniform float line_width = 0.30;
// 每秒滚动几个周期。0 = 不动。
uniform float scroll_speed = 0.0;
// 呼吸：整面墙的亮度按这个速度起伏（0 = 不呼吸）。
uniform float pulse_speed = 2.2;
uniform float pulse_depth = 0.22;
// 竖向边缘的亮线强度 / 宽度（把墙的四角勾出来，看着像"罩子"）。
uniform float edge_glow = 1.1;
uniform float edge_width = 0.06;
// 顶盖独立淡入/解除，侧墙保持默认不透明度。
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// ── 横向扫描线 ──
	float f = fract(UV.y * line_count + TIME * scroll_speed);
	float half_w = line_width * 0.5;
	// f 落在 0.5 附近算作线；两端各留 55% 做抗锯齿过渡
	float line = 1.0 - smoothstep(half_w * 0.55, half_w, abs(f - 0.5));

	// ── 呼吸 ──
	float pulse = 1.0 - pulse_depth
		+ pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed));

	// ── 竖向边缘 ──
	float e = smoothstep(1.0 - edge_width, 1.0, abs(UV.x * 2.0 - 1.0));

	vec3 col = mix(fill_color.rgb, line_color.rgb * 2.2, line * pulse);
	col += line_color.rgb * e * edge_glow;

	float a = mix(fill_color.a, line_color.a, line);
	a = max(a, e * 0.90);

	ALBEDO = col;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
