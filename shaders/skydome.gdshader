// Skydome — ported from Three.js procedural skydome (BackSide sphere) to a Godot
// sky shader. EYEDIR replaces the original normalized world direction. Renders a
// gradient sky plus an "anime" sun, or moon + stars at night.
shader_type sky;

uniform vec3 zenith_color = vec3(0.0, 0.35, 0.82);
uniform vec3 horizon_color = vec3(0.46, 0.74, 0.93);
uniform vec3 ground_color = vec3(0.04, 0.55, 0.65);

uniform vec3 sun_position = vec3(-0.846, -0.085, -1.0);
uniform vec3 sun_color = vec3(0.639, 0.494, 0.058);
uniform vec3 sun_glow_color = vec3(1.0, 0.635, 0.0);
uniform float sun_size = 0.005;
uniform float sun_glow_size = 0.03386;
uniform float sun_ray_count = 12.0;
uniform float sun_ray_length = 0.0352;
uniform float sun_ray_sharpness = 8.0;

uniform vec3 moon_position = vec3(-0.5, -0.085, -1.0);
uniform vec3 moon_color = vec3(0.95, 0.95, 1.0);
uniform vec3 moon_glow_color = vec3(0.7, 0.8, 1.0);
uniform float moon_size = 0.0268665;
uniform float moon_glow_size = 0.0266345;

uniform vec3 star_color = vec3(1.0, 1.0, 1.0);
uniform float star_density = 10.0;
uniform float star_brightness = 2.5;

uniform float is_night = 0.0;
uniform float season = 0.0;              // 0 spring, 1 winter, 2 autumn, 3 rainy
uniform float atmosphere_intensity = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}
float snoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 anime_sun(vec3 direction, vec3 sun_dir, vec3 s_color, vec3 glow_color,
		float s_size, float glow_size, float ray_count, float ray_length, float ray_sharpness) {
	float sun_dot = dot(direction, sun_dir);
	if (sun_dot < 0.85) {
		float d = acos(clamp(sun_dot, -1.0, 1.0));
		float outer = smoothstep(glow_size * 2.0, 0.0, d);
		return glow_color * (outer * outer * 0.3) * vec3(1.0, 0.8, 0.6);
	}
	float dist_from_sun = acos(sun_dot);
	vec3 result = vec3(0.0);
	vec3 sun_right = normalize(cross(sun_dir, vec3(0.0, 1.0, 0.0)));
	vec3 sun_up = normalize(cross(sun_right, sun_dir));
	float sx = dot(direction - sun_dir * sun_dot, sun_right);
	float sy = dot(direction - sun_dir * sun_dot, sun_up);
	float angle = atan(sy, sx);

	float outer = smoothstep(glow_size * 2.0, 0.0, dist_from_sun);
	result += glow_color * (outer * outer * 0.3) * vec3(1.0, 0.8, 0.6);

	float ray_pattern = cos(angle * ray_count) * 0.5 + 0.5;
	ray_pattern = pow(ray_pattern, ray_sharpness);
	float ray_start = s_size * 0.8;
	float ray_end = s_size + ray_length;
	float ray_mask = smoothstep(ray_end, ray_start, dist_from_sun) *
		smoothstep(s_size * 0.5, ray_start, dist_from_sun);
	result += mix(s_color, glow_color, 0.5) * (ray_pattern * ray_mask * 0.8);

	float mid_glow = smoothstep(glow_size, s_size * 0.5, dist_from_sun) *
		smoothstep(s_size * 0.3, s_size * 0.8, dist_from_sun);
	float inner_glow = smoothstep(s_size * 1.5, s_size * 0.9, dist_from_sun);
	inner_glow *= inner_glow;
	result += glow_color * mid_glow * 0.6;
	result += mix(glow_color, s_color, 0.7) * inner_glow * 0.5;

	float disc_mask = smoothstep(s_size, s_size * 0.85, dist_from_sun);
	float disc_gradient = smoothstep(s_size, 0.0, dist_from_sun);
	vec3 disc_color = mix(s_color * 0.95, s_color * 1.2, disc_gradient) +
		vec3(0.1, 0.05, 0.0) * (1.0 - disc_gradient);
	result = mix(result, disc_color, disc_mask);

	float center = smoothstep(s_size * 0.4, 0.0, dist_from_sun);
	result += vec3(1.0, 0.98, 0.9) * (center * center * 0.3);
	return result;
}

float stars(vec2 uv, float density) {
	vec2 star_uv = uv * 30.0;
	vec2 star_id = floor(star_uv);
	vec2 star_pos = fract(star_uv);
	float star = 0.0;
	for (int x = 0; x <= 1; x++) {
		for (int y = 0; y <= 1; y++) {
			vec2 cell_id = star_id + vec2(float(x), float(y));
			float cell_hash = hash(cell_id);
			if (cell_hash < density * 0.12) {
				vec2 star_center = fract(sin(cell_id * vec2(12.9898, 78.233)) * 43758.5453) * 0.8 + 0.1;
				vec2 local = star_pos - vec2(float(x), float(y)) - star_center;
				float dist = length(local);
				float brightness = cell_hash * 0.5 + 0.5;
				float star_size = 0.025 + brightness * 0.015;
				float intensity = max(0.0, 1.0 - dist * (1.0 / star_size));
				star += brightness * intensity * intensity;
			}
		}
	}
	return min(star, 1.0);
}

void sky() {
	vec3 direction = EYEDIR;
	float altitude = direction.y;

	vec3 sky_color;
	if (altitude > 0.0) {
		float factor = altitude * altitude * sqrt(altitude);
		sky_color = mix(horizon_color, zenith_color, factor);
	} else {
		float factor = altitude * altitude * altitude;
		sky_color = mix(horizon_color, ground_color, -factor);
	}

	vec3 final_color = sky_color;

	if (is_night < 0.5) {
		bool show_sun = season < 0.5 || (season > 1.5 && season < 2.5);
		if (show_sun) {
			vec3 sun_dir = normalize(sun_position);
			final_color += anime_sun(direction, sun_dir, sun_color, sun_glow_color,
				sun_size, sun_glow_size, sun_ray_count, sun_ray_length, sun_ray_sharpness);
		}
	} else {
		vec3 moon_dir = normalize(moon_position);
		float moon_dot = dot(direction, moon_dir);
		float dist_from_moon = acos(clamp(moon_dot, -1.0, 1.0));

		float outer_glow = smoothstep(moon_glow_size * 3.0, 0.0, dist_from_moon);
		outer_glow = outer_glow * outer_glow * outer_glow;
		final_color += moon_glow_color * outer_glow * 0.15;

		float mid_glow = smoothstep(moon_glow_size * 1.5, moon_size * 0.5, dist_from_moon);
		mid_glow = mid_glow * mid_glow;
		final_color += moon_glow_color * mid_glow * 0.25;

		float inner_halo = smoothstep(moon_size * 1.8, moon_size * 0.95, dist_from_moon);
		inner_halo *= smoothstep(moon_size * 0.7, moon_size * 0.95, dist_from_moon);
		vec3 halo_color = mix(moon_glow_color, moon_color, 0.5);
		final_color += halo_color * inner_halo * 0.4;

		if (dist_from_moon < moon_size) {
			float moon_mask = smoothstep(moon_size, moon_size * 0.85, dist_from_moon);
			vec2 moon_uv = (direction.xy - moon_dir.xy) * 20.0;
			float craters = snoise(moon_uv * 5.0) * 0.3;
			float disc_gradient = smoothstep(moon_size, 0.0, dist_from_moon);
			vec3 moon_surface = moon_color * (0.75 + craters + disc_gradient * 0.15);
			final_color = mix(final_color, moon_surface, moon_mask);
			float center = smoothstep(moon_size * 0.4, 0.0, dist_from_moon);
			center = center * center;
			final_color += vec3(1.0, 1.0, 0.98) * center * 0.15;
		}

		float star_visibility = smoothstep(-0.3, 0.2, direction.y);
		if (star_visibility > 0.01) {
			vec2 star_uv = vec2(atan(direction.z, direction.x) * 0.15915 + 0.5,
				acos(clamp(direction.y, -1.0, 1.0)) * 0.31831);
			float star_field = stars(star_uv, star_density);
			final_color += star_color * star_field * star_brightness * star_visibility;
		}
	}

	float atmosphere_glow = 1.0 - abs(altitude);
	atmosphere_glow = atmosphere_glow * atmosphere_glow * atmosphere_glow;
	final_color += vec3(0.5, 0.7, 1.0) * (atmosphere_glow * 0.1 * atmosphere_intensity);

	float time_variation = sin(TIME * 0.1) * 0.01;
	final_color += vec3(time_variation, time_variation * 0.5, time_variation * 0.3);

	COLOR = final_color;
}
