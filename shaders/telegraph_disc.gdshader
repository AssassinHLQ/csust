shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// 砸击地面预警圈。
//
// 为什么不用 StandardMaterial3D：
//   那边 `emission` **不吃 alpha**（自发光是加色，透明度管不着），
//   不开自发光又会在暗场里几乎看不见；实测第一版画出来是一块**实心红饼**
//   （出图 `_final_phase/9_telegraph.png`），根本不是"预警范围"。
// 这里：ALBEDO 直接 >1 让辉光接住，ALPHA 自己压，边上再亮一圈当边界。

uniform vec4 color : source_color = vec4(1.0, 0.16, 0.10, 1.0);
uniform float alpha = 0.30;
uniform float edge_width = 0.10;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	// 边上一圈亮线，里面是一层淡红
	float rim = smoothstep(1.0 - edge_width, 1.0, r);
	float fill = alpha * (0.65 + 0.35 * pulse);
	ALBEDO = color.rgb * (1.0 + rim * 2.2) * (0.9 + 0.2 * pulse);
	ALPHA = clamp(fill + rim * 0.85, 0.0, 1.0);
}
