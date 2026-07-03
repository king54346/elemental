// Water ripples overlay — ported from Three.js water chunks.
// Transparent plane above the ground water area. Draws animated ripple rings
// (non-winter), rain splashes, and winter ice. The blue water body itself comes
// from the ground shader; this only adds the animated white overlay.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled;

uniform sampler2D density_map : filter_linear, repeat_disable;
uniform sampler2D perlin_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D water_depth_texture : filter_linear_mipmap, repeat_enable;

uniform float ground_size = 33.0;
uniform float time_speed = 0.06;   // original uTime += 0.001/frame ≈ 0.06/s @60fps

// density orientation — kept in sync with ground.gdshader by GroundMat.gd
uniform float uv_rotation : hint_range(-180.0, 180.0, 1.0) = -90.0;
uniform bool flip_u = false;
uniform bool flip_v = true;

uniform float ripples_ratio = 1.0; // spring/summer -> 1
uniform float density_mask_min = 0.05;
uniform float density_mask_max = 0.15;
uniform float shore_mask_threshold = 0.4;
uniform float noise_scale1 = 3.0;
uniform float noise_scale2 = 5.0;
uniform float noise_speed1 = 0.5;
uniform float noise_speed2 = 0.3;
uniform float noise_mix1 = 0.6;
uniform float noise_mix2 = 0.4;
uniform float noise_depth_influence = 0.3;
uniform float ripple_frequency = 12.0;
uniform float ripple_inner_edge = 0.05;
uniform float ripple_outer_edge = 0.4;
uniform float breakup_min = 0.2;
uniform float breakup_max = 0.75;
uniform float water_depth_fade = 0.1;
uniform float discard_threshold = 0.45;
uniform float ripple_opacity = 2.5;

uniform float splashes_ratio = 0.0;
uniform float splashes_noise_frequency = 0.33;
uniform float splashes_time_frequency = 6.0;
uniform float splashes_thickness = 0.3;
uniform float splashes_edge_low = 0.14;
uniform float splashes_edge_high = 1.0;
uniform float splashes_center_min = 0.0;
uniform float splashes_center_max = 0.5;

uniform float ice_ratio = 0.0;
uniform float ice_noise_frequency = 0.3;
uniform vec3 ice_color = vec3(0.9, 0.95, 1.0);

varying vec2 v_uv;
varying vec3 v_world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}
// returns (minDist, edge, cellHash)
vec3 voronoi(vec2 uv, float repeat) {
	uv *= repeat;
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float min_dist = 1.0;
	float min_edge = 1.0;
	vec2 best_id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 cell = mod(i + neighbor, repeat);
			vec2 pt = hash22(cell);
			vec2 diff = neighbor + pt - f;
			float dist = length(diff);
			if (dist < min_dist) {
				min_edge = min_dist;
				min_dist = dist;
				best_id = i + neighbor;
			} else if (dist < min_edge) {
				min_edge = dist;
			}
		}
	}
	vec2 cell_id = fract(best_id / repeat);
	return vec3(min_dist, min_edge - min_dist, hash22(cell_id).x);
}

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

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = rot_density((world_pos.xz + vec2(ground_size) * 0.5) / vec2(ground_size));
	v_world_pos = world_pos;
}

void fragment() {
	float u_time = TIME * time_speed;

	vec4 density = texture(density_map, v_uv);
	vec4 water_depth_map = texture(water_depth_texture, v_uv);

	float water_density_mask = smoothstep(density_mask_min, density_mask_max, density.b);
	float water_depth = water_depth_map.b;

	float final_alpha = 0.0;
	vec3 final_color = vec3(1.0);

	float shore_mask = smoothstep(shore_mask_threshold, 0.0, water_depth);
	float center_mask = smoothstep(splashes_center_min, splashes_center_max, water_depth);

	if (ripples_ratio > 0.001) {
		float noise1 = texture(perlin_noise, v_uv * noise_scale1 + u_time * noise_speed1).r;
		float noise2 = texture(perlin_noise, v_uv * noise_scale2 - u_time * noise_speed2).g;
		float combined = noise1 * noise_mix1 + noise2 * noise_mix2;
		float noisy_depth = water_depth + combined * noise_depth_influence;
		float ripple_pattern = fract((noisy_depth + u_time) * ripple_frequency);
		float ripple_ring = smoothstep(0.0, ripple_inner_edge, ripple_pattern) *
			smoothstep(ripple_outer_edge, ripple_inner_edge, ripple_pattern);
		float breakup = smoothstep(breakup_min, breakup_max, combined);
		ripple_ring *= shore_mask * breakup;
		ripple_ring *= smoothstep(0.0, water_depth_fade, water_depth);
		final_alpha = max(final_alpha, ripple_ring * water_density_mask * ripple_opacity * ripples_ratio);
	}

	if (splashes_ratio > 0.001) {
		vec2 splash_uv = v_world_pos.xz * splashes_noise_frequency;
		vec3 sv = voronoi(splash_uv, 8.0);
		float splash_perlin = texture(perlin_noise, splash_uv * 0.25).r;
		float splash = sv.r;
		float splash_time_rand = hash2(vec2(sv.b * 123456.0)) + splash_perlin;
		float splash_time = u_time * splashes_time_frequency + splash_time_rand;
		splash = fract(splash - splash_time);
		float edge_mult = smoothstep(splashes_edge_low, splashes_edge_high, sv.g);
		float thickness = splashes_thickness * edge_mult;
		splash = 1.0 - step(thickness, splash);
		float vis_rand = hash2(vec2(sv.b * 654321.0));
		float visible = fract(vis_rand + splash_perlin);
		visible = step(visible, splashes_ratio);
		splash *= visible;
		splash *= center_mask;
		final_alpha = max(final_alpha, splash * water_density_mask);
		if (splash > 0.01) {
			final_color = mix(final_color, vec3(1.0), splash * 0.8);
		}
	}

	if (ice_ratio > 0.001) {
		vec2 ice_uv = v_world_pos.xz * ice_noise_frequency;
		float ice_voronoi = voronoi(ice_uv, 8.0).g;
		float ice_mask = smoothstep(0.0, ice_ratio, water_depth);
		float ice = step(ice_mask, ice_voronoi);
		final_alpha = max(final_alpha, ice * water_density_mask * 0.9);
		if (ice > 0.01) {
			final_color = mix(final_color, ice_color, ice * 0.7);
		}
	}

	if (final_alpha < discard_threshold) {
		discard;
	}

	ALBEDO = final_color;
	ALPHA = final_alpha;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
