// Volumetric water surface — distilled from the Godot 4 Water TEST project's
// interactive_water_system/rendering/surface/water_surface.gdshader (C# IWS).
//
// Kept: Gerstner wave displacement, scrolling micro-normals, depth-buffer based
// water depth -> Beer-Lambert absorption, screen-space refraction, subsurface
// glow, fresnel reflectance, shoreline foam, and caustics projected onto the
// pond floor. Dropped from the original: the compute-driven ripple textures,
// planar-reflection viewport, LOD tiers, buoyancy hooks and underwater camera
// post — none of which a static diorama pond needs. Driven from GDScript
// (WaterVolume.gd) instead of the original C# WaterManager.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── Time / placement ─────────────────────────────────────────────────────────
uniform float sim_time             = 0.0;
uniform vec3  water_world_position = vec3(0.0);
uniform vec2  water_size_xz        = vec2(12.0, 12.0);

// Pond outline clip — reuse the ground's painted water mask (density.b) so the
// waterline follows the pond shape instead of the mesh rectangle. uv_rotation /
// flip_u / flip_v are pushed by GroundMat.gd to stay aligned with the ground and
// the carved basin (which digs from the same mask).
uniform sampler2D density_map : filter_linear, repeat_disable;
uniform float ground_size = 33.0;
uniform float uv_rotation : hint_range(-180.0, 180.0, 1.0) = 0.0;
uniform bool  flip_u = false;
uniform bool  flip_v = true;
uniform float pond_edge_low  = 0.04;
uniform float pond_edge_high = 0.14;

// ── Gerstner waves (filled by WaterVolume.gd) ────────────────────────────────
uniform int   wave_count           = 0;
uniform vec2  wave_directions[8];
uniform float wave_wavelengths[8];
uniform float wave_amplitudes[8];
uniform float wave_speeds[8];
uniform float wave_steepnesses[8];
uniform float wave_nonlinear_exp   = 1.3;
uniform float wave_scale           = 1.0;   // 0 = flat (winter ice), <1 = calmer (spring)

// ── Optics ───────────────────────────────────────────────────────────────────
uniform vec3  absorption_coeff     = vec3(0.9, 0.35, 0.18);
uniform float scattering_intensity = 0.4;
uniform float visibility_distance  = 4.0;
uniform float water_ior            = 1.333;
uniform float refraction_strength  = 0.03;
uniform vec4  color_shallow : source_color = vec4(0.13, 0.52, 0.55, 1.0);
uniform vec4  color_deep    : source_color = vec4(0.02, 0.16, 0.22, 1.0);

uniform vec4  subsurface_color    : source_color = vec4(0.06, 0.55, 0.45, 1.0);
uniform float subsurface_strength = 0.7;
uniform float subsurface_exponent = 4.0;

// ── Surface shading ──────────────────────────────────────────────────────────
uniform float water_roughness   = 0.06;
uniform float glint_strength     = 0.5;
uniform float glint_sharpness    = 128.0;
uniform float glint_density      = 1.0;

uniform sampler2D micro_normal_1 : hint_normal, repeat_enable;
uniform sampler2D micro_normal_2 : hint_normal, repeat_enable;
uniform float micro_normal_strength    = 0.25;
uniform float micro_normal_scale       = 6.0;
uniform vec2  wind_direction           = vec2(1.0, 0.27);
uniform float wind_speed               = 0.5;
uniform float micro_normal_speed1      = 0.6;
uniform float micro_normal_speed2      = -0.4;
uniform float micro_normal_layer_ratio = 1.7;

// ── Foam ─────────────────────────────────────────────────────────────────────
uniform sampler2D foam_normal_detail  : hint_normal, repeat_enable;
uniform sampler2D foam_bubble_texture : hint_default_white, repeat_enable;
uniform vec4  foam_color              : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float foam_amount             = 1.0;   // master foam toggle (0 = no foam)
uniform float foam_intensity          = 1.2;
uniform float shoreline_width         = 0.35;
uniform float shoreline_foam_intensity = 2.0;
uniform float foam_density            = 3.0;
uniform float foam_normal_strength    = 0.5;

// ── Caustics on the pond floor ───────────────────────────────────────────────
uniform sampler2D caustics_texture : repeat_enable;
uniform float caustics_strength      = 0.16;
uniform float caustics_scale         = 0.35;
uniform float caustics_speed         = 0.45;
uniform float caustics_distortion    = 0.4;
uniform float caustics_fade_distance = 4.0;

// ── Lighting (synced to the scene sun by WaterVolume.gd) ─────────────────────
uniform vec3  sun_direction = vec3(0.4, 0.7, 0.4);
uniform vec3  sun_color     = vec3(1.0, 0.95, 0.85);
uniform float sun_elevation = 1.2;

// Winter ice: blend the surface to an opaque frosted sheet with cracks.
uniform float ice_amount = 0.0;                        // 0 = water, 1 = full ice
uniform vec4  ice_color : source_color = vec4(0.82, 0.9, 0.96, 1.0);
uniform float ice_crack_scale = 0.9;
uniform float ice_roughness = 0.5;

// Koi fish swimming under the surface (top-down), driven by WaterVolume.gd.
const int MAX_FISH = 12;
uniform int   fish_count = 0;
uniform vec4  fish_data[MAX_FISH];                     // xy = world pos, z = heading, w = phase
uniform float fish_size = 0.32;                        // world size (~ body half-length)
uniform float fish_tail_freq = 7.0;
uniform vec3  fish_color1 : source_color = vec3(0.95, 0.42, 0.1);   // orange koi
uniform vec3  fish_color2 : source_color = vec3(0.96, 0.95, 0.92);  // white koi
uniform float fish_opacity = 0.9;

// ── Boat interaction: GPU wave-equation ripple field + hull collar ───────────
// sim_height_tex is the live height field solved by RippleSim.gd on the GPU
// (real 2D wave equation: reflects off the shore, interferes). We sample it for
// surface displacement + normals + foam. boat_* draw the hull's displacement dip
// and foam collar.
uniform sampler2D sim_height_tex : hint_default_black, repeat_disable, filter_linear;
uniform vec2  sim_center        = vec2(0.0);   // world xz centre of the sim rect
uniform float sim_size          = 22.0;        // world size the sim covers
uniform float sim_render_scale  = 0.06;        // sim height -> world displacement
uniform float sim_normal_scale  = 1.2;
uniform float sim_foam_scale    = 7.0;         // foam from ripple steepness
uniform vec2  boat_pos          = vec2(9999.0);
uniform float boat_radius       = 1.1;
uniform float boat_displace     = 0.05;
uniform float boat_collar_foam  = 1.0;

// Hull cutout — carve the water out of the boat's hull with a few tapering
// trapezoid segments (bow / mid / stern) that hug the hull outline, plus a
// vertical mask so only water below the waterline is removed. Ported from the
// RealisticEnvironments ocean_system water_cutout_trapezoid technique.
const int MAX_HULL_CUTS = 4;
uniform int  hull_cut_count = 0;
uniform vec4 hull_cut_centers[MAX_HULL_CUTS];   // xyz world centre
uniform vec4 hull_cut_axes[MAX_HULL_CUTS];      // right.xz, forward.xz
uniform vec4 hull_cut_shapes[MAX_HULL_CUTS];    // max half width, half length, unused, shape type
uniform vec4 hull_cut_widths[MAX_HULL_CUTS];    // start half width, end half width
uniform vec4 hull_cut_vert[MAX_HULL_CUTS];      // unused, max_y, height feather, unused
uniform bool hull_cut_debug = false;            // paint the cutout region red instead of discarding

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture,  repeat_disable, filter_nearest;

// ── Varyings ─────────────────────────────────────────────────────────────────
varying vec3 v_world_pos;
varying vec3 v_gerstner_normal;
varying vec2 v_wave_gradient_xz;
varying vec2 v_pond_uv;

const float MIN_WAVE_LEN = 0.001;

// Same density-map orientation mapping used by ground.gdshader / the old water.
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

// ── Helpers ──────────────────────────────────────────────────────────────────
vec3 beer_lambert(float path_length, vec3 absorption) {
	return exp(-max(path_length, 0.0) * absorption);
}
float scatter_phase(float cos_theta) {
	float t = cos_theta * 0.5 + 0.5;
	return t * t;
}
float fresnel_schlick(float cos_theta, float f0) {
	float f = 1.0 - clamp(cos_theta, 0.0, 1.0);
	float f2 = f * f;
	return f0 + (1.0 - f0) * f2 * f2 * f;
}
vec3 blend_normals_udn(vec3 n1, vec3 n2) {
	return normalize(n1 + vec3(n2.x, 0.0, n2.z));
}
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
vec2 rotate2(vec2 uv, float a) {
	float s = sin(a); float c = cos(a);
	return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}
// Voronoi -> (F1 distance, F2-F1 edge distance) for ice cracks.
vec2 voronoi2(vec2 uv) {
	vec2 ip = floor(uv);
	vec2 fp = fract(uv);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(ip + g);
			float d = length(g + o - fp);
			if (d < f1) { f2 = f1; f1 = d; }
			else if (d < f2) { f2 = d; }
		}
	}
	return vec2(f1, f2 - f1);
}

// Sample the GPU-simulated ripple height field at a world XZ. Shared by the
// vertex (displacement) and fragment (normal + foam) stages.
vec2 sim_uv(vec2 world_xz) {
	return (world_xz - sim_center) / max(sim_size, 0.001) + 0.5;
}
float sim_h(vec2 world_xz) {
	vec2 uv = sim_uv(world_xz);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
	return texture(sim_height_tex, uv).r * sim_render_scale;
}

// Signed distance (xz) to a hull cutout segment (rounded box, optional taper).
float hull_cut_sdf(vec2 world_xz, int i) {
	vec4 c = hull_cut_centers[i];
	vec4 axes = hull_cut_axes[i];
	vec4 shape = hull_cut_shapes[i];
	vec4 w = hull_cut_widths[i];
	vec2 delta = world_xz - c.xz;
	vec2 right = normalize(axes.xy);
	vec2 forward = normalize(axes.zw);
	vec2 local = vec2(dot(delta, right), dot(delta, forward));
	float hl = max(shape.y, 0.001);
	float hw = shape.x;
	if (shape.w > 0.5) {
		float t = clamp(local.y / (hl * 2.0) + 0.5, 0.0, 1.0);
		hw = mix(w.x, w.y, t);
	}
	vec2 q = vec2(abs(local.x) - hw, abs(local.y) - hl);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
}

float fish_h1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float fish_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fish_h1(i);
	float b = fish_h1(i + vec2(1.0, 0.0));
	float c = fish_h1(i + vec2(0.0, 1.0));
	float d = fish_h1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Top-down koi field with body, tail, pectoral fins, dorsal ridge, koi blotches
// and eyes. Returns rgb + coverage mask for the nearest fish at world_xz.
vec4 fish_field(vec2 world_xz, float t) {
	vec3 col = vec3(0.0);
	float best = 0.0;
	for (int i = 0; i < fish_count && i < MAX_FISH; i++) {
		vec2 fp = fish_data[i].xy;
		float ang = fish_data[i].z;
		float ph = fish_data[i].w;
		float seed = float(i) * 7.13;
		vec2 dd = (world_xz - fp) / fish_size;
		float ca = cos(-ang);
		float sa = sin(-ang);
		vec2 lp = vec2(ca * dd.x - sa * dd.y, sa * dd.x + ca * dd.y);   // forward = +x
		float sway = sin(t * fish_tail_freq + ph - lp.x * 2.5) * 0.2 * smoothstep(0.4, -1.0, lp.x);
		float yy = lp.y - sway;
		float ay = abs(yy);

		// body: tapering ellipse
		float bw = 0.42 * sqrt(max(0.0, 1.0 - lp.x * lp.x));
		float body = smoothstep(bw, bw - 0.05, ay) * step(-1.0, lp.x) * step(lp.x, 1.0);
		// forked tail fin
		float tw = 0.32 * smoothstep(-1.75, -1.0, lp.x);
		float tail = smoothstep(tw, tw - 0.05, ay) * step(-1.8, lp.x) * step(lp.x, -0.85);
		// pectoral fins: two side fins near the shoulder, flapping
		float flap = 0.06 + 0.05 * sin(t * fish_tail_freq * 1.1 + ph);
		float shoulder = smoothstep(0.5, 0.15, lp.x) * smoothstep(-0.05, 0.2, lp.x);
		float pec = smoothstep(0.12, 0.0, abs(ay - (bw + 0.06 + flap))) * shoulder;
		// dorsal fin: thin ridge along the back centre
		float dorsal = smoothstep(0.055, 0.0, ay) * smoothstep(0.7, -0.55, lp.x) * step(-0.55, lp.x);

		float m = max(max(body, tail), pec * 0.85);
		if (m > best) {
			best = m;
			float hh = fract(sin(seed) * 43758.5453);
			vec3 base = (hh < 0.45) ? fish_color2 : fish_color1;
			vec3 patchcol = (hh < 0.45) ? fish_color1 : fish_color2;
			// koi blotches (条纹/花纹)
			float p1 = smoothstep(0.46, 0.6, fish_noise(lp * 2.2 + vec2(seed, seed * 1.7)));
			float p2 = smoothstep(0.5, 0.62, fish_noise(lp * 4.0 + vec2(seed * 2.3, 9.1)));
			vec3 c = mix(base, patchcol, clamp(p1 * 0.85 + p2 * 0.4, 0.0, 1.0));
			// pectoral fins: pale translucent
			c = mix(c, mix(c, vec3(1.0), 0.35), clamp(pec - body, 0.0, 1.0));
			// dorsal ridge (背脊): darker line
			c = mix(c, c * 0.55, dorsal * 0.8);
			// eyes (眼睛): two dark dots near the head
			float eye = smoothstep(0.085, 0.04, length(vec2(lp.x - 0.68, ay - 0.17)));
			c = mix(c, vec3(0.04, 0.03, 0.02), eye);
			col = c;
		}
	}
	return vec4(col, best);
}

// ── Gerstner ─────────────────────────────────────────────────────────────────
vec2 gerstner_horiz_disp(vec2 pos_xz, float t) {
	vec2 disp = vec2(0.0);
	for (int i = 0; i < wave_count && i < 8; i++) {
		float k = TAU / max(wave_wavelengths[i], MIN_WAVE_LEN);
		vec2 d = normalize(wave_directions[i]);
		float phase = k * dot(d, pos_xz) - wave_speeds[i] * t;
		disp += d * (wave_steepnesses[i] * wave_amplitudes[i] * cos(phase));
	}
	return disp;
}
float gerstner_evaluate(vec2 pos_xz, float t, out vec3 normal_delta, out vec2 horiz_disp) {
	float h = 0.0;
	normal_delta = vec3(0.0);
	horiz_disp = vec2(0.0);
	float nexp = max(wave_nonlinear_exp, 1.0);
	for (int i = 0; i < wave_count && i < 8; i++) {
		float wl = max(wave_wavelengths[i], MIN_WAVE_LEN);
		float k = TAU / wl;
		vec2 d = normalize(wave_directions[i]);
		float amp = wave_amplitudes[i];
		float phase = k * dot(d, pos_xz) - wave_speeds[i] * t;
		float sp = sin(phase);
		float cp = cos(phase);
		float abs_sp = abs(sp);
		h += amp * pow(abs_sp, nexp) * sign(sp);
		float pow_term = (abs_sp < 1e-5) ? 0.0 : amp * nexp * pow(abs_sp, nexp - 1.0) * cp;
		normal_delta.x += pow_term * k * d.x;
		normal_delta.z += pow_term * k * d.y;
		horiz_disp += d * (wave_steepnesses[i] * amp * cp);
	}
	return h;
}

vec3 depth_to_world(vec2 screen_uv, float depth, mat4 inv_proj, mat4 inv_view) {
	vec4 ndc = vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	vec4 view = inv_proj * ndc;
	view.xyz /= view.w;
	return (inv_view * vec4(view.xyz, 1.0)).xyz;
}

// ── Vertex ───────────────────────────────────────────────────────────────────
void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_pond_uv = rot_density((world_pos.xz + vec2(ground_size) * 0.5) / vec2(ground_size));
	float t = sim_time;

	// Newton inverse so the sampled Gerstner point lands on this world column.
	vec2 guess_xz = world_pos.xz;
	for (int iter = 0; iter < 4; iter++) {
		vec2 disp = gerstner_horiz_disp(guess_xz, t);
		vec2 error = (guess_xz + disp) - world_pos.xz;
		float el = length(error);
		if (el > 2.0) error = error / el * 2.0;
		guess_xz -= error;
		if (el < 0.0001) break;
	}

	vec3 normal_delta;
	vec2 horiz_disp;
	float wave_h = gerstner_evaluate(guess_xz, t, normal_delta, horiz_disp);
	wave_h *= wave_scale;            // calmer in spring, flat under winter ice
	horiz_disp *= wave_scale;
	normal_delta *= wave_scale;

	vec3 displaced = world_pos;
	displaced.y  += wave_h;
	displaced.xz += horiz_disp;

	// Boat: simulated ripple field + a dip in the water right under the hull.
	displaced.y += sim_h(world_pos.xz);
	float _bd = distance(world_pos.xz, boat_pos);
	displaced.y -= exp(-pow(_bd / max(boat_radius, 0.05), 2.0)) * boat_displace;

	vec3 g_normal = normalize(vec3(-normal_delta.x, 1.0, -normal_delta.z));
	v_gerstner_normal = g_normal;
	v_world_pos = displaced;
	v_wave_gradient_xz = normal_delta.xz;

	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced, 1.0)).xyz;
	NORMAL = (MODEL_MATRIX * vec4(g_normal, 0.0)).xyz;
}

// ── Caustics (triplanar, projected onto the refracted floor) ─────────────────
vec3 projected_caustics(vec3 geo_world, vec3 geo_normal, float underwater_len, float t) {
	if (caustics_strength < 0.001) return vec3(0.0);
	vec2 grad = v_wave_gradient_xz;
	float gl = length(grad);
	if (gl > 1.5) grad *= 1.5 / gl;
	vec2 distort = grad * caustics_distortion;

	vec2 uv_xz = geo_world.xz * caustics_scale + distort;
	vec2 uv_xy = geo_world.xy * caustics_scale + distort;
	vec2 uv_zy = geo_world.zy * caustics_scale + distort;

	vec2 flow1 = vec2(t * caustics_speed * 0.12, t * caustics_speed * 0.08);
	vec2 flow2 = vec2(-t * caustics_speed * 0.10, -t * caustics_speed * 0.14);

	vec3 n_abs = pow(max(abs(geo_normal), vec3(0.001)), vec3(4.0));
	vec3 blend = n_abs / (n_abs.x + n_abs.y + n_abs.z);
	float lod = clamp(log2(1.0 + underwater_len * caustics_scale), 0.0, 6.0);

	float c_xz = textureLod(caustics_texture, uv_xz + flow1, lod).r * textureLod(caustics_texture, uv_xz * 1.7 + flow2, lod).r;
	float c_xy = textureLod(caustics_texture, uv_xy + flow1, lod).r * textureLod(caustics_texture, uv_xy * 1.7 + flow2, lod).r;
	float c_zy = textureLod(caustics_texture, uv_zy + flow1, lod).r * textureLod(caustics_texture, uv_zy * 1.7 + flow2, lod).r;
	float c = pow(clamp(c_xz * blend.y + c_xy * blend.z + c_zy * blend.x, 0.0, 1.0), 1.8);

	float fade = clamp(1.0 - underwater_len / max(caustics_fade_distance, 0.5), 0.0, 1.0);
	vec3 tint = exp(-underwater_len * absorption_coeff * 0.5);
	float sun_factor = clamp(sun_elevation / 1.5708, 0.0, 1.0);
	return vec3(c) * caustics_strength * fade * sun_factor * sun_color * tint;
}

// ── Fragment ─────────────────────────────────────────────────────────────────
void fragment() {
	// Clip to the pond outline so water never spills onto dry ground.
	float pond_mask = smoothstep(pond_edge_low, pond_edge_high, texture(density_map, v_pond_uv).b);
	if (pond_mask < 0.01) {
		discard;
	}

	vec3 world_pos = v_world_pos;
	vec3 normal_g = normalize(v_gerstner_normal);

	// Carve the water out of the boat hull: discard where a cutout segment covers
	// this fragment AND it's below that segment's waterline ceiling.
	float _in_cut = 0.0;
	for (int i = 0; i < hull_cut_count && i < MAX_HULL_CUTS; i++) {
		float sdf = hull_cut_sdf(world_pos.xz, i);
		float hmask = 1.0 - smoothstep(hull_cut_vert[i].y, hull_cut_vert[i].y + hull_cut_vert[i].z, world_pos.y);
		if (sdf < 0.0 && hmask > 0.5) {
			if (hull_cut_debug) { _in_cut = 1.0; } else { discard; }
		}
	}

	// 1. Micro-normal detail (two scrolling layers)
	vec2 wind_n = normalize(wind_direction);
	vec2 mn_uv1 = world_pos.xz / micro_normal_scale + wind_n * wind_speed * micro_normal_speed1 * sim_time;
	vec2 mn_uv2 = world_pos.xz / (micro_normal_scale * micro_normal_layer_ratio) + wind_n * wind_speed * micro_normal_speed2 * sim_time;
	vec3 mn1 = texture(micro_normal_1, mn_uv1).xyz * 2.0 - 1.0;
	vec3 mn2 = texture(micro_normal_2, mn_uv2).xyz * 2.0 - 1.0;
	vec3 mn_combined = normalize(mn1 + mn2);
	vec3 micro_n_ts = normalize(mix(vec3(0.0, 0.0, 1.0), mn_combined, micro_normal_strength));
	vec3 micro_n = normalize(vec3(micro_n_ts.x, micro_n_ts.z, micro_n_ts.y));
	vec3 n_combined = blend_normals_udn(normal_g, micro_n);

	// Ripple normal (finite differences of the simulated height field).
	float _re = sim_size / 256.0;
	float _rx = sim_h(world_pos.xz + vec2(_re, 0.0)) - sim_h(world_pos.xz - vec2(_re, 0.0));
	float _rz = sim_h(world_pos.xz + vec2(0.0, _re)) - sim_h(world_pos.xz - vec2(0.0, _re));
	vec3 ripple_n = normalize(vec3(-_rx * sim_normal_scale, 2.0 * _re, -_rz * sim_normal_scale));
	n_combined = blend_normals_udn(n_combined, ripple_n);
	NORMAL = n_combined;

	// 2. Depth reconstruction -> underwater path length
	float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 geo_world = depth_to_world(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	bool is_sky = (raw_depth < 1e-6);
	float view_depth = is_sky ? visibility_distance : max(length(geo_world - world_pos), 0.0);

	// 3. Caustics onto the floor (before absorption)
	vec3 caustics = vec3(0.0);
	if (!is_sky && caustics_strength > 0.001 && view_depth > 0.02) {
		vec3 dx = dFdx(geo_world);
		vec3 dy = dFdy(geo_world);
		vec3 geo_n = normalize(cross(dx, dy));
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - geo_world);
		if (dot(geo_n, vdir) < 0.0) geo_n = -geo_n;
		if (geo_world.y < world_pos.y - 0.02) {
			caustics = projected_caustics(geo_world, geo_n, view_depth, sim_time);
		}
	}

	// 4. Refraction + Beer-Lambert absorption
	vec3 transmittance = beer_lambert(view_depth, absorption_coeff);
	vec2 refract_off = normal_g.xz * refraction_strength * clamp(view_depth * 0.5, 0.0, 1.0);
	vec2 refract_uv = clamp(SCREEN_UV + refract_off, vec2(0.001), vec2(0.999));
	vec3 bg_color = texture(SCREEN_TEXTURE, refract_uv).rgb;
	vec3 absorbed_bg = (bg_color + caustics) * transmittance;

	float cos_theta = max(dot(-VIEW, sun_direction), 0.0);
	vec3 scatter_col = color_shallow.rgb * sun_color * scattering_intensity * scatter_phase(cos_theta) * (1.0 - transmittance);
	vec3 deep_contrib = color_deep.rgb * (1.0 - transmittance.g) * (1.0 - transmittance.g);
	vec3 final_albedo = absorbed_bg + scatter_col + deep_contrib * 0.3;
	float final_alpha = clamp(1.0 - transmittance.g * 0.8 + 0.15, 0.0, 1.0);

	// 5. Subsurface glow on wave crests
	float crest_weight = clamp((1.0 - normal_g.y) * 3.0, 0.0, 1.0);
	float sss_factor = pow(max(dot(-VIEW, -sun_direction), 0.0), subsurface_exponent);
	final_albedo += subsurface_color.rgb * subsurface_strength * sss_factor * crest_weight * sun_color;

	// 5.5 Koi fish swimming just under the surface (hidden under winter ice).
	if (fish_count > 0 && ice_amount < 0.99) {
		vec4 fish = fish_field(world_pos.xz, sim_time);
		final_albedo = mix(final_albedo, fish.rgb, fish.a * fish_opacity * (1.0 - ice_amount));
	}

	// 6. Shoreline foam (thin band where the water is shallow)
	float total_foam = 0.0;
	if (shoreline_width > 0.01 && !is_sky && view_depth < shoreline_width) {
		float shore_t = 1.0 - clamp(view_depth / shoreline_width, 0.0, 1.0);
		vec2 shore_uv = world_pos.xz * 0.8 + wind_n * sim_time * 0.015;
		float shore_noise = clamp(texture(foam_normal_detail, shore_uv).r * 2.0 - 0.5, 0.0, 1.0);
		total_foam = smoothstep(0.2, 0.7, shore_t * shore_noise) * shoreline_foam_intensity;
	}
	// crest foam
	float slope = clamp(1.0 - normal_g.y, 0.0, 1.0);
	total_foam += smoothstep(0.08, 0.23, slope) * foam_intensity;
	// ripple foam (on wave-equation crests) + foam collar around the displacing hull
	float ripple_slope = (abs(_rx) + abs(_rz)) * sim_foam_scale;
	total_foam += smoothstep(0.15, 0.6, ripple_slope) * 0.8;
	float _dbf = distance(world_pos.xz, boat_pos);
	float collar = smoothstep(boat_radius + 0.45, boat_radius + 0.05, _dbf)
	             * smoothstep(boat_radius - 0.55, boat_radius + 0.05, _dbf);
	total_foam += collar * boat_collar_foam;
	total_foam = clamp(total_foam * foam_amount, 0.0, 1.0);

	if (total_foam > 0.01) {
		float tile_scale = max(foam_density * 0.08, 0.02);
		vec2 fuv = world_pos.xz * tile_scale;
		float fdetail = texture(foam_bubble_texture, fuv).r * 0.6 + texture(foam_bubble_texture, fuv * 1.7).r * 0.4;
		fdetail = mix(0.3, 1.0, smoothstep(0.2, 0.78, fdetail));
		total_foam *= fdetail;
		vec3 fn = texture(foam_normal_detail, fuv * 0.7).xyz * 2.0 - 1.0;
		fn = normalize(mix(vec3(0.0, 0.0, 1.0), fn, foam_normal_strength));
		NORMAL = blend_normals_udn(NORMAL, vec3(fn.x, 0.0, fn.z) * total_foam);
	}
	final_albedo = mix(final_albedo, foam_color.rgb, total_foam);
	final_alpha = max(final_alpha, total_foam * 0.85 + 0.05);

	// 7. Fresnel + sun glints
	float cos_view_n = max(dot(-VIEW, NORMAL), 0.0);
	float f0 = pow((1.0 - water_ior) / (1.0 + water_ior), 2.0);
	float fresnel = fresnel_schlick(cos_view_n, f0);

	float glint_mod = 0.0;
	if (glint_strength > 0.001) {
		vec2 gp = world_pos.xz * glint_density + wind_n * sim_time * 0.04;
		vec2 gc = floor(gp);
		vec2 gf = fract(gp);
		float hx = fract(sin(dot(gc, vec2(127.1, 311.7))) * 43758.5453);
		float hy = fract(sin(dot(gc, vec2(269.5, 183.3))) * 43758.5453);
		float gd = length(gf - vec2(hx, hy));
		float gv = pow(max(1.0 - gd * 2.0, 0.0), glint_sharpness * 0.02 + 2.0);
		vec3 rdir = reflect(-VIEW, NORMAL);
		gv *= pow(max(dot(rdir, sun_direction), 0.0), clamp(glint_sharpness * 0.5, 4.0, 256.0));
		gv *= mix(0.2, 1.0, fresnel);
		glint_mod = clamp(gv * glint_strength, 0.0, 1.0);
	}

	// Winter ice: frosted opaque sheet with voronoi cracks + mottled frost.
	float ice_rough = water_roughness;
	if (ice_amount > 0.001) {
		vec2 iw = world_pos.xz;
		float frost = texture(foam_normal_detail, iw * 0.22).x;      // soft frost mottle
		vec2 vor = voronoi2(iw * ice_crack_scale);
		float crack = smoothstep(0.06, 0.0, vor.y);                  // thin dark plate cracks
		vec3 ice_col = ice_color.rgb * (0.9 + 0.12 * frost);
		ice_col = mix(ice_col, ice_color.rgb * 0.5, crack * 0.7);
		final_albedo = mix(final_albedo, ice_col, ice_amount);
		final_alpha = mix(final_alpha, 1.0, ice_amount);
		ice_rough = mix(water_roughness, ice_roughness, ice_amount);
	}

	// 8. Output (fade the very rim with the pond mask for a soft waterline)
	final_alpha *= pond_mask;
	ALBEDO = final_albedo;
	ALPHA = final_alpha;
	if (_in_cut > 0.5) { ALBEDO = vec3(1.0, 0.15, 0.15); ALPHA = 0.85; }
	float foam_rough = mix(ice_rough, 0.9, total_foam);
	ROUGHNESS = max(foam_rough - glint_mod * foam_rough * 0.92, 0.005);
	METALLIC = 0.0;
	SPECULAR = mix(fresnel * 0.5 + glint_mod * 0.2, 0.35, ice_amount);
	SSS_STRENGTH = subsurface_strength * crest_weight * 0.3 * (1.0 - ice_amount);
}
