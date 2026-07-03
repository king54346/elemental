// Bush/leaf shader — ported from Three.js bush material for a Godot MultiMesh.
// Each instance is a camera-facing leaf quad with wind sway, alpha-cutout via a
// leaf mask, colored by a shadow->mid->highlight ramp (flat/unshaded toon look).
// Per-instance normal is passed through INSTANCE_CUSTOM.xyz.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D alpha_map : filter_linear;
uniform vec3 light_direction = vec3(-0.721, 0.577, 0.385);
uniform vec3 shadow_color = vec3(0.003, 0.074, 0.003);
uniform vec3 mid_color = vec3(0.06, 0.23, 0.0);
uniform vec3 highlight_color = vec3(0.44, 0.5, 0.0);
uniform vec3 color_multiplier = vec3(0.46, 0.65, 0.3);

uniform float time_scale = 0.06;   // original uTime += 0.001/frame ≈ 0.06/s
uniform float breeze_speed = 16.25;
uniform float breeze_scale = 6.2;
uniform float breeze_strength = 2.5;
uniform float squall_speed = 4.02;
uniform float squall_scale = 4.3;
uniform float squall_strength = 0.5;

varying vec3 v_normal;
varying vec2 v_uv;
varying float v_world_y;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	float u_time = TIME * time_scale;

	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);

	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;

	float height_mask = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	height_mask = pow(height_mask, 1.5);

	vec2 wind_pos = world_pos.xz + VERTEX.xz;
	float breeze = noise(wind_pos * breeze_scale + u_time * breeze_speed) - 0.5;
	float squall = noise(wind_pos * squall_scale * 0.5 + u_time * squall_speed) - 0.5;
	float wind = (breeze * breeze_strength + squall * squall_strength) * height_mask;
	vec3 wind_offset = cam_right * wind * 0.25 + cam_up * wind * 0.1;

	vec3 billboard_pos = world_pos
		+ cam_right * VERTEX.x * sx
		+ cam_up * VERTEX.y * sy
		+ wind_offset;

	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(billboard_pos, 1.0);

	v_normal = INSTANCE_CUSTOM.xyz;
	v_uv = UV;
	v_world_y = billboard_pos.y;
}

vec3 color_ramp(float t, vec3 s, vec3 m, vec3 h) {
	if (t < 0.5) {
		return mix(s, m, t * 2.0);
	}
	return mix(m, h, (t - 0.5) * 2.0);
}

void fragment() {
	float alpha = texture(alpha_map, v_uv).a;
	float a = smoothstep(0.4, 0.6, alpha);
	if (a < 0.01) {
		discard;
	}

	vec3 n = normalize(v_normal);
	float ndl = dot(n, normalize(light_direction));
	ndl = ndl * 0.6 + 0.4;

	float t = clamp(v_world_y * 0.1 + ndl, 0.0, 1.0);
	vec3 color = color_ramp(t, shadow_color, mid_color, highlight_color);
	color *= color_multiplier;

	ALBEDO = color;
}
