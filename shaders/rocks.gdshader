// Rocks shader — ported from Three.js rocks chunks.
// Blends three rock colors via displacement(blur) + perlin noise, then adds moss
// on upward-facing surfaces. Lighting handled by Godot PBR (roughness 1, metallic 0).
shader_type spatial;

uniform sampler2D displacement_map : filter_linear_mipmap, repeat_enable; // displacement_map_blur
uniform sampler2D perlin_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 rock_color1 = vec3(0.96, 0.86, 0.54);
uniform vec3 rock_color2 = vec3(0.97, 0.82, 0.42);
uniform vec3 rock_color3 = vec3(0.31, 0.24, 0.06);
uniform vec3 moss_color1 = vec3(0.97, 0.82, 0.42);
uniform vec3 moss_color2 = vec3(0.97, 0.82, 0.42);
uniform vec3 moss_color3 = vec3(0.14, 0.17, 0.003);
uniform float moss_noise_factor = 1.2;
uniform float moss_visibility = 3.0;

varying vec3 v_world_normal;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 displacement = texture(displacement_map, UV);
	vec4 perlin = texture(perlin_noise, UV * 2.0);

	vec3 color1 = mix(rock_color1, rock_color2, displacement.r);
	vec3 color = mix(color1, rock_color3, perlin.r);
	color *= 0.9 + (perlin.r * 0.2);

	float upward_facing = max(0.0, v_world_normal.y);
	vec3 moss1 = mix(moss_color1, moss_color2, displacement.r);
	vec3 moss = mix(moss1, moss_color3, displacement.r);
	color = mix(color, moss, upward_facing * (perlin.r / moss_noise_factor) * moss_visibility);

	ALBEDO = color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
