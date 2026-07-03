#[compute]
#version 450

// 2D wave-equation ripple solver (single band), distilled from the IWS
// IWSRippleCompute.glsl. Height + velocity are packed into an rg32f field that
// ping-pongs each step. Boat disturbances arrive as brushes (SSBO). The pond
// shape comes in as a mask: land cells are pinned to 0, so ripples reflect off
// the real shoreline and interfere — a proper little fluid, not procedural rings.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg16f) uniform restrict readonly  image2D field_in;   // r=height g=velocity
layout(set = 0, binding = 1, rg16f) uniform restrict writeonly image2D field_out;
layout(set = 0, binding = 2, r32f)  uniform restrict readonly  image2D mask_tex;    // 1=water 0=land

layout(set = 0, binding = 3, std430) readonly buffer BrushBuffer {
	int  count;
	int  _p0, _p1, _p2;
	vec4 brushes[64];   // xy = uv, z = radius (uv), w = strength
} bb;

layout(push_constant, std430) uniform Params {
	vec4 p0;   // x=c2  y=damping  z=height_clamp  w=inject_scale
} pc;

float load_h(ivec2 p, ivec2 cmax) {
	return imageLoad(field_in, clamp(p, ivec2(0), cmax)).r;
}

void main() {
	ivec2 pos  = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(field_in);
	if (pos.x >= size.x || pos.y >= size.y) return;
	ivec2 cmax = size - ivec2(1);

	float mask = imageLoad(mask_tex, pos).r;
	if (mask < 0.5) {
		imageStore(field_out, pos, vec4(0.0));   // land = fixed wall (reflects)
		return;
	}

	vec2  hv = imageLoad(field_in, pos).rg;
	float h  = hv.r;
	float v  = hv.g;

	float hL = load_h(pos + ivec2(-1, 0), cmax);
	float hR = load_h(pos + ivec2( 1, 0), cmax);
	float hU = load_h(pos + ivec2( 0,-1), cmax);
	float hD = load_h(pos + ivec2( 0, 1), cmax);
	float lap = hL + hR + hU + hD - 4.0 * h;

	// brush injection (velocity impulses -> outward-travelling rings)
	float inj = 0.0;
	int cnt = min(bb.count, 64);
	if (cnt > 0) {
		vec2 uv = (vec2(pos) + 0.5) / vec2(size);
		for (int i = 0; i < cnt; i++) {
			vec2  buv = bb.brushes[i].xy;
			float r   = max(bb.brushes[i].z, 1e-4);
			float s   = bb.brushes[i].w;
			float d   = distance(uv, buv);
			if (d < r) {
				float rn = d / r;
				float prof = 1.0 - rn * rn;
				inj += s * prof * prof;
			}
		}
	}

	v = (v + pc.p0.x * lap) * pc.p0.y;
	v += inj * pc.p0.w;
	h = clamp(h + v, -pc.p0.z, pc.p0.z);

	imageStore(field_out, pos, vec4(h, v, 0.0, 0.0));
}
