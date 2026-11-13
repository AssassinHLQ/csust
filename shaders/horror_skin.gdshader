shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// 最终 BOSS「优香-恐怖」的皮肤：把原贴图压暗，靠**菲涅尔边缘光**把轮廓烧红。
//
// 为什么不用 StandardMaterial3D 的 tint + 自发光：
//   上一版就是这么做的（tint 近黑红 + 全身 emission 1.15 + 红光 12），
//   三层一叠，人物直接变成**一坨纯红剪影**，头发/脸/制服全糊掉
//   （出图 `_final_phase/6_boss.png`）。恐怖感来自「暗处一张看得清的脸」，
//   不是红色剪纸。所以这里保留贴图明暗（ALBEDO 只乘一个偏暗的 tint），
//   红色只出现在掠射角（边缘）和一点点呼吸自发光上。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = true;
// 贴图乘色。偏冷的灰红，保留布料/皮肤的明暗层次
uniform vec4 tint : source_color = vec4(0.62, 0.42, 0.44, 1.0);
// 边缘光
uniform vec3 rim_color : source_color = vec3(1.0, 0.13, 0.07);
uniform float rim_power = 2.4;
uniform float rim_amount = 1.35;
// 呼吸（0~1，由脚本每帧写）：二阶段更强
uniform float pulse = 0.0;
// 全身的一层微弱暗红，避免"完全不发光"时在暗景里彻底看不见
uniform vec3 glow_color : source_color = vec3(0.42, 0.02, 0.02);
uniform float glow_amount = 0.20;
// 受击闪白（脚本写）
uniform vec3 flash_color : source_color = vec3(1.0, 0.45, 0.40);
uniform float flash = 0.0;
// 眼睛/嘴这类 MASK 材质要走 alpha scissor，否则会变成方块
uniform bool use_alpha = false;
// 眼睛自发光白光：只给眼嘴那一面开（脚本写），其余面保持 0。
// 用贴图亮度当遮罩 —— 眼白越白越亮，瞳孔那条暗缝不会被烧平。
uniform vec3 eye_emit_color : source_color = vec3(1.0, 0.97, 0.93);
uniform float eye_emit = 0.0;

void fragment() {
	vec4 tex = use_texture ? texture(albedo_tex, UV) : vec4(1.0);
	vec3 base = tex.rgb * tint.rgb;
	float fres = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec3 rim = rim_color * fres * (rim_amount + pulse * 1.4);
	ALBEDO = mix(base, flash_color, clamp(flash, 0.0, 1.0));
	float eye_lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 eye_glow = eye_emit_color * (eye_emit * smoothstep(0.15, 0.85, eye_lum));
	EMISSION = rim + glow_color * (glow_amount + pulse * 0.35) + eye_glow;
	ROUGHNESS = 0.72;
	SPECULAR = 0.25;
	if (use_alpha) {
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = 0.35;
	}
}
