shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_opaque;

// 两层合成：细层（分块窗口）+ 粗层（全校园降采样常驻），按优先级
//   天空（全景） → 粗层 → 细层
// 粗层不随窗口更换，所以换窗口时画面**不会空**：细层没传完就只剩粗层。
uniform sampler2D render_texture : source_color, filter_linear;
uniform sampler2D coarse_texture : source_color, filter_linear;
uniform sampler2D panorama : source_color, filter_linear;
uniform vec3 fallback_sky = vec3(0.62, 0.48, 0.55);
// 调试：0 = 两层合成（正常），1 = 只看粗层，2 = 只看细层
uniform int debug_layer = 0;

vec3 srgb_to_linear(vec3 x) {
	vec3 higher = pow((x + 0.055) / 1.055, vec3(2.4));
	vec3 lower = x / 12.92;
	return mix(higher, lower, lessThanEqual(x, vec3(0.04045)));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 fine = texture(render_texture, SCREEN_UV);
	vec4 coarse = texture(coarse_texture, SCREEN_UV);

	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	v.xyz /= v.w;
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(v.xyz, 0.0)).xyz);
	vec2 uv = vec2(atan(d.z, d.x) * 0.15915494 + 0.5,
		asin(clamp(d.y, -1.0, 1.0)) * 0.31830989 + 0.5);
	vec3 sky = texture(panorama, uv).rgb;
	if (sky == vec3(0.0)) {
		sky = fallback_sky;
	}

	// 粗层先盖到天空上，细层再盖到粗层上（两层都按 alpha 加权）
	vec3 base = mix(sky, srgb_to_linear(coarse.rgb), coarse.a);
	vec3 col = mix(base, srgb_to_linear(fine.rgb), fine.a);
	if (debug_layer == 1) {
		col = mix(sky, srgb_to_linear(coarse.rgb), coarse.a);
	} else if (debug_layer == 2) {
		col = mix(sky, srgb_to_linear(fine.rgb), fine.a);
	}
	ALBEDO = col;
}
