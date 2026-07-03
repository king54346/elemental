// Wind lines — ported from the Three.js windLines material. A thin ribbon whose
// visible segment sweeps along its length as `progress` goes 0->1, tapering at the
// ends. UV.x carries the along-curve ratio, UV.y the ribbon side (0/1).
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float thickness = 0.25;
uniform float progress = 0.0;
uniform vec3 wind_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 tangent = vec3(0.0, 0.7071, -0.7071);

varying float v_alpha;

void vertex() {
	float ratio = UV.x;
	float side = UV.y - 0.5;

	float base_thickness = smoothstep(0.0, 1.0, 1.0 - abs(ratio - 0.5) * 2.0);
	float remaped = progress * 3.0 - 1.0;
	float progress_thickness = smoothstep(0.0, 1.0, 1.0 - abs(ratio - remaped));
	float final_thickness = thickness * base_thickness * progress_thickness;

	VERTEX += tangent * side * final_thickness;
	v_alpha = base_thickness * progress_thickness;
}

void fragment() {
	ALBEDO = wind_color;
	ALPHA = v_alpha;
}
