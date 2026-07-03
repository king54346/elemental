// Flowers — ported from the Three.js flowers material. Camera-facing quads sampling
// a 2-flower atlas (INSTANCE_CUSTOM.xy = atlas offset, .z = size), gentle wind sway,
// alpha-cutout, and a per-season `visibility` fade.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : filter_linear;
uniform float wind_speed = 1.5;
uniform float wind_amplitude = 0.3;
uniform float visibility = 1.0;

varying vec2 v_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec2 tex_off = INSTANCE_CUSTOM.xy;
	float size = INSTANCE_CUSTOM.z;
	v_uv = UV * vec2(0.5, 1.0) + tex_off;

	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;

	float phase = hash(world.xz) * 6.28318;
	float wind = sin(TIME * wind_speed + phase) * wind_amplitude;
	float height_factor = VERTEX.y + 0.5;
	vec3 wind_offset = cam_right * wind * height_factor * 0.5;

	vec3 pos = world + cam_right * VERTEX.x * size + cam_up * VERTEX.y * size + wind_offset;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(pos, 1.0);
}

void fragment() {
	vec4 tex = texture(atlas, v_uv);
	if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = tex.rgb;
	ALPHA = tex.a * visibility;
}
