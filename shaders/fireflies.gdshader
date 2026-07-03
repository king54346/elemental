// Fireflies — ported from the Three.js fireflies material, simplified for a Godot
// MultiMesh of billboard quads. Each instance drifts gently and flickers, glowing
// warm orange. INSTANCE_CUSTOM = (phase, colorMix, driftSeed, 0).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float flicker_speed = 20.0;
uniform float flicker_sharpness = 4.0;
uniform float drift_magnitude = 0.6;
uniform vec3 color1 = vec3(1.0, 0.67, 0.21);
uniform vec3 color2 = vec3(0.99, 0.43, 0.0);

varying float v_bright;
varying vec3 v_col;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float color_mix = INSTANCE_CUSTOM.y;
	float seed = INSTANCE_CUSTOM.z;

	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);

	vec3 drift = vec3(
		sin(TIME * 0.30 + phase),
		sin(TIME * 0.23 + phase * 1.3) * 0.5,
		cos(TIME * 0.27 + phase + seed)
	) * drift_magnitude;

	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 pos = world_pos + drift + cam_right * VERTEX.x * s + cam_up * VERTEX.y * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(pos, 1.0);

	float flicker = 0.5 + 0.5 * sin(TIME * flicker_speed + phase * 6.28318);
	v_bright = mix(0.7, 1.0, pow(flicker, flicker_sharpness)) * 1.8;
	v_col = mix(color1, color2, color_mix);
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	ALBEDO = v_col * v_bright;
	ALPHA = a;
}
