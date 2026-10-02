#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: laser beam. One camera-facing quad per beam spanning the beam plus its glow and end flares;
// the fragment shader evaluates a capsule distance field. Optional rotation around p0 (sweeping lasers)
// and ground-snapped far end (heightmap).
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec4 quad;      // xy = corner -1..1
layout (location = 1) in vec4 i_p0w;     // p0.xyz, width
layout (location = 2) in vec4 i_p1c;     // p1.xyz, flare scale
layout (location = 3) in vec4 i_color;
layout (location = 4) in vec4 i_life;    // start, end, seed, pulse speed
layout (location = 5) in vec4 i_rot;     // rot (rad/s around Y at p0), groundEnd, delay frames of rotation start, unused

uniform sampler2D heightmapTex;

out DataVS {
	vec4 vA;       // along, across, length, width
	vec4 vColor;
	vec4 vMisc;    // seed, pulse, flare scale, envelope
	vec2 vQuad;
};

void main() {
	float now = fxNow();
	float start = i_life.x;
	float end = i_life.y;
	float ttl = end - start;
	float env = fxEnvelope(now, start, end, max(1.0, min(4.0, ttl * 0.15)), max(2.0, min(ttl * 0.35, 12.0)));
	if (env < 0.002) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }

	vec3 p0 = i_p0w.xyz;
	vec3 p1 = i_p1c.xyz;
	if (i_rot.x != 0.0) {
		float ang = i_rot.x * max(now - start - i_rot.z, 0.0) / 30.0;
		vec2 v = p1.xz - p0.xz;
		float s = sin(ang);
		float c = cos(ang);
		p1.xz = p0.xz + vec2(v.x * c - v.y * s, v.x * s + v.y * c);
	}
	if (i_rot.y > 0.5) {
		p1.y = textureLod(heightmapTex, heightmapUVatWorldPos(p1.xz), 0.0).x + 3.0;
	}
	vec3 dir = p1 - p0;
	float L = length(dir);
	if (L < 0.5) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
	dir /= L;

	float seed = i_life.z;
	float pulse = i_life.w;
	float w = i_p0w.w * (1.0 + 0.12 * sin(now * 0.9 * pulse + seed)) * mix(0.35, 1.0, env);
	float fs = i_p1c.w;
	float ext = max(w * 5.0 + 6.0, w * 4.0 * fs * 1.8);

	vec3 camPos = cameraViewInv[3].xyz;
	float along = mix(-ext, L + ext, quad.x * 0.5 + 0.5);
	vec3 pAxis = p0 + dir * clamp(along, 0.0, L);
	vec3 toCam = normalize(camPos - pAxis);
	vec3 right = cross(dir, toCam);
	float rl = length(right);
	right = rl > 0.05 ? right / rl : normalize(cross(dir, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	// keep the beam readable from far away
	float minW = length(camPos - pAxis) * 0.0012;
	float cover = clamp(w / max(minW, 0.001), 0.3, 1.0);
	w = max(w, minW);
	ext = max(ext, w * 5.0 + 6.0);
	float across = quad.y * ext;
	vec3 world = p0 + dir * along + right * across;
	// pull a little towards the camera so the end flare is not swallowed by the ground it hits
	world += toCam * min(w * 2.0, 12.0);

	gl_Position = cameraViewProj * vec4(world, 1.0);
	vA = vec4(along, across, L, w);
	vColor = vec4(i_color.rgb, i_color.a * cover);
	vMisc = vec4(seed, pulse, fs, env);
	vQuad = quad.xy;
}
