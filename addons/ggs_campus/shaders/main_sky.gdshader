shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_opaque;

uniform sampler2D render_texture : source_color, filter_linear;
uniform sampler2D panorama : source_color, filter_linear;
uniform vec3 fallback_sky = vec3(0.62, 0.48, 0.55);

vec3 srgb_to_linear(vec3 x) {
	vec3 higher = pow((x + 0.055) / 1.055, vec3(2.4));
	vec3 lower = x / 12.92;
	return mix(higher, lower, lessThanEqual(x, vec3(0.04045)));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 campus = texture(render_texture, SCREEN_UV);
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	v.xyz /= v.w;
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(v.xyz, 0.0)).xyz);
	vec2 uv = vec2(atan(d.z, d.x) * 0.15915494 + 0.5,
		asin(clamp(d.y, -1.0, 1.0)) * 0.31830989 + 0.5);
	vec3 sky = texture(panorama, uv).rgb;
	if (sky == vec3(0.0)) {
		sky = fallback_sky;
	}
	ALBEDO = mix(sky, srgb_to_linear(campus.rgb), campus.a);
}
