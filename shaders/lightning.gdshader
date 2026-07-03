// Lightning bolt — ported from the Three.js lightning arc material. A jagged tube
// coloured blue->cyan along its height, additively blended, fading out via `fade`
// (0 = full, 1 = gone). Height gradient uses local VERTEX.y over bolt_height.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float fade = 0.0;
uniform float bolt_height = 15.0;
uniform vec3 color_a : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 color_b : source_color = vec3(0.0, 1.0, 1.0);
uniform float intensity = 3.0;

varying float v_progress;

void vertex() {
	v_progress = clamp(VERTEX.y / bolt_height, 0.0, 1.0);
}

void fragment() {
	vec3 col = mix(color_a, color_b, v_progress) * intensity;
	ALBEDO = col * 1.3;
	ALPHA = clamp(1.0 - fade, 0.0, 1.0);
}
