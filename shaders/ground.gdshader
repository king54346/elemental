// Ground shader — ported from Three.js ground chunks (vertex_begin + fragment_color).
// The mesh is flat; all detail is procedural color driven by data textures.
// Lighting/shadows are handled by Godot's PBR (roughness 1, metallic 0), matching
// the original which used MeshStandardMaterial + onBeforeCompile (diffuseColor only).
shader_type spatial;

// --- data textures (linear, no sRGB) ---
uniform sampler2D density_map : filter_linear, repeat_disable;        // path_data_rgb (ClampToEdge)
uniform sampler2D displacement_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D perlin_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_rock_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_rock_ao : filter_linear_mipmap, repeat_enable;

// uGroundSize (WORLD_SIZE = gridCols*GROUND_SIZE = 3*11 = 33)
uniform float ground_size = 33.0;
uniform float rock_tiling = 6.0;
uniform float water_depth_intensity = 1.0;

// Rotates / flips the data-texture sampling (density/displacement/etc.) about the
// center, to align the density map with the model layout.
uniform float uv_rotation : hint_range(-180.0, 180.0, 1.0) = -90.0;
uniform bool flip_u = false;
uniform bool flip_v = true;

// spring / day color config (already linear, from SeasonManager)
uniform vec3 ground_color_light = vec3(0.2784, 0.1372, 0.0235);
uniform vec3 ground_color_dark = vec3(0.94, 0.58, 0.22);
uniform vec3 ground_color_below_grass = vec3(0.12, 0.15, 0.03);
uniform vec3 rock_color = vec3(1.0, 0.78, 0.47);
uniform vec3 water_shallow = vec3(1.0, 0.4, 0.0);
uniform vec3 water_deep = vec3(0.06, 0.5, 0.51);
// grassy floor tint under dense grass so gaps between blades read as grass, not
// dirt (set per-season to the mid grass tone by GroundMat.gd).
uniform vec3 grass_floor = vec3(0.2, 0.46, 0.02);

varying vec2 v_uv;

// density map is rotated relative to the model layout; rotate UV about center.
vec2 rot_density(vec2 uv) {
	float a = radians(uv_rotation);
	float s = sin(a);
	float c = cos(a);
	vec2 p = uv - vec2(0.5);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	vec2 r = p + vec2(0.5);
	if (flip_u) {
		r.x = 1.0 - r.x;
	}
	if (flip_v) {
		r.y = 1.0 - r.y;
	}
	return r;
}

void vertex() {
	// heightUv = (worldPos.xz + uGroundSize.xz*0.5) / uGroundSize.xz
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = rot_density((world_pos.xz + vec2(ground_size) * 0.5) / vec2(ground_size));
}

void fragment() {
	vec4 height_map = texture(displacement_map, v_uv);
	vec4 density = texture(density_map, v_uv);
	vec4 perlin = texture(perlin_noise, v_uv * 2.0);
	vec4 rock_map = texture(ground_rock_map, v_uv * rock_tiling);
	float rock_ao = texture(ground_rock_ao, v_uv * rock_tiling).r;

	float density_mask = smoothstep(0.01, 1.25, density.g);
	vec3 x = mix(perlin.rgb, vec3(1.0), smoothstep(0.9, 1.0, density.g));
	float rock_mask = smoothstep(0.0, 0.55, x.r);

	vec3 ground_color = mix(ground_color_light, ground_color_dark, height_map.r);
	ground_color = mix(ground_color, ground_color_below_grass, density_mask);

	vec3 rock_col = rock_map.rgb * rock_color * mix(1.0, rock_ao, 2.0 * rock_mask);
	ground_color = mix(rock_col, ground_color, rock_mask);

	// grass floor: tint the ground toward grass color under dense grass so gaps
	// between blades don't reveal bare dirt (very visible from top-down)
	ground_color = mix(ground_color, grass_floor, smoothstep(0.1, 0.55, density.g));

	// distant ground (outside the central play area) reads as continuing meadow so
	// the far edge looks like grassy hills fading to the horizon, not bare dirt
	vec2 outside = max(vec2(0.0), abs(v_uv - 0.5) - 0.5);
	float far = clamp((outside.x + outside.y) * 2.5, 0.0, 1.0);
	ground_color = mix(ground_color, grass_floor, far * 0.9);

	// water
	float water_mask = density.b;
	vec2 water_grad = vec2(dFdx(water_mask), dFdy(water_mask));
	float edge_strength = length(water_grad) * 5.0;
	float edge_softness = smoothstep(0.0, 1.0, edge_strength);
	water_mask = mix(water_mask, water_mask * (1.0 - edge_softness * 0.7), min(edge_strength, 1.0));

	vec2 water_center = vec2(0.53, 0.535);
	float dist_from_center = length(v_uv - water_center);
	float depth_gradient = 1.0 - smoothstep(0.0, 0.3, dist_from_center);
	depth_gradient = pow(depth_gradient, water_depth_intensity);
	vec3 water_color = mix(water_shallow, water_deep, depth_gradient);

	ground_color = mix(ground_color, water_color, water_mask);

	ALBEDO = ground_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
