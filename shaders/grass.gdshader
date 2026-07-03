// Grass shader — procedural 3D blades on a Godot MultiMesh (approach C).
// Blades are real tapered geometry placed with a fixed random yaw + scale in their
// instance transform (no billboard, so they read as volume from any angle incl.
// top-down). INSTANCE_CUSTOM = (worldX, worldZ, rand, 0). Vertex: density-cull +
// world-space wind shear of the tip. Fragment: height-based color + per-blade variation.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D density_map : filter_linear, repeat_disable;      // path_data (green = grass density)
uniform sampler2D displacement_map : filter_linear_mipmap, repeat_enable;

uniform float ground_size = 33.0;
uniform float density_threshold = 0.9;
uniform float terrain_normal_scale = 1.0;
uniform float blade_height = 1.0;

// density orientation — kept in sync with ground.gdshader by GroundMat.gd
uniform float uv_rotation : hint_range(-180.0, 180.0, 1.0) = -90.0;
uniform bool flip_u = false;
uniform bool flip_v = true;

uniform float wind_time_scale = 0.72;   // original uTime += 0.012/frame ≈ 0.72/s @60fps
uniform float wind_speed = 1.5;
uniform float wind_amplitude = 1.5;
uniform float wind_wave_tiling = 1.0;
uniform float wind_wave_strength = -0.5;
uniform float wind_base_tiling = 0.3;
uniform float wind_base_strength = 1.0;

uniform vec3 grass_color_dark = vec3(0.0, 0.29, 0.02);
uniform vec3 grass_color_light = vec3(0.48, 0.68, 0.007);
uniform vec3 shadow_color = vec3(0.01, 0.16, 0.0);

varying vec2 v_grass_uv;
varying float v_blade_mask;
varying float v_rand;

vec2 rot_density(vec2 uv) {
	float a = radians(uv_rotation);
	float s = sin(a);
	float c = cos(a);
	vec2 p = uv - vec2(0.5);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	vec2 r = p + vec2(0.5);
	if (flip_u) { r.x = 1.0 - r.x; }
	if (flip_v) { r.y = 1.0 - r.y; }
	return r;
}
float noise2d(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
float smooth_noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = noise2d(i);
	float b = noise2d(i + vec2(1.0, 0.0));
	float c = noise2d(i + vec2(0.0, 1.0));
	float d = noise2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	// original loops once -> single octave at amplitude 0.5
	return 0.5 * smooth_noise2d(p);
}
vec2 calc_wind(vec3 world_pos, float u_time) {
	vec2 wave_pos = world_pos.xz * wind_wave_tiling;
	float wave_time = u_time * wind_speed;
	float wave1 = fbm(wave_pos - vec2(wave_time * 0.35, wave_time));
	float wave2 = fbm(wave_pos - vec2(0.0, wave_time * 0.35));
	float primary = (wave1 + wave2) * 0.5 * wind_wave_strength;

	vec2 base_pos = world_pos.xz * wind_base_tiling;
	float base_time = u_time * (wind_speed * 0.93);
	float base_wave = fbm(base_pos - vec2(base_time, 0.0)) * wind_base_strength;

	float strength = (primary + base_wave) * wind_amplitude;
	return vec2(strength, strength * 0.3 * sin(wave_time * 0.5));
}
void vertex() {
	float u_time = TIME * wind_time_scale;

	vec3 base_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 world_uv = rot_density(INSTANCE_CUSTOM.xy / ground_size + 0.5);
	v_grass_uv = world_uv;
	float density = textureLod(density_map, world_uv, 0.0).g;
	float density_cull = step(density_threshold, density);
	v_rand = INSTANCE_CUSTOM.z;

	// blade height fraction (0 base .. 1 tip), object space before instance scale
	float h = clamp(VERTEX.y / max(blade_height, 1e-4), 0.0, 1.0);
	v_blade_mask = h;

	// place the real blade via its instance transform (random yaw + scale), then
	// bend the tip in world space along the wind (a shear that keeps the base
	// rooted). Culled blades collapse to their base so they vanish.
	vec3 world_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wind = calc_wind(base_world, u_time);
	world_v.x += wind.x * h * h;
	world_v.z += wind.y * h * h;
	world_v = mix(base_world, world_v, density_cull);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_v, 1.0);

	// up-biased normal keeps stylized grass bright from any angle
	NORMAL = normalize(NORMAL * 0.4 + vec3(0.0, 1.0, 0.0));
}

void fragment() {
	// large-scale patch variation from the displacement map
	float patch = texture(displacement_map, v_grass_uv * terrain_normal_scale).r;
	vec3 base_col = mix(grass_color_dark, grass_color_light, patch);

	// vertical shading along the blade: darker/AO near the ground -> lit mid
	float ao = smoothstep(0.0, 0.35, v_blade_mask);
	vec3 col = mix(shadow_color, base_col, ao);

	// tip highlight — slightly brighter & warmer toward the tip
	vec3 tip = base_col * 1.22 + vec3(0.05, 0.06, 0.0);
	col = mix(col, tip, smoothstep(0.55, 1.0, v_blade_mask) * 0.7);

	// subtle per-blade variation (narrow range = more natural, cohesive)
	col *= 0.86 + 0.28 * v_rand;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
