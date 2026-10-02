#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: shield bubble (kind 0) and cloak shimmer (kind 1) on an ellipsoid around a unit or a point.
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec4 sph;       // unit sphere position == normal
layout (location = 1) in vec4 i_shape;   // offsetY, rx, ry, rz
layout (location = 2) in vec4 i_color;
layout (location = 3) in vec4 i_life;    // start, end, seed, kind
layout (location = 4) in vec4 i_par;     // hexScale (0 = none), fresnel power, follow heading, unused
layout (location = 5) in vec4 i_anim;    // scaleFrom, alphaFrom, animStart, animFrames
layout (location = 6) in vec4 i_hit0;    // hit dir xyz (unit sphere space), hit frame
layout (location = 7) in vec4 i_hit1;
layout (location = 8) in vec4 i_hit2;
layout (location = 9) in vec4 i_hit3;
#if ATTACHED == 1
layout (location = 10) in uvec4 instData;
#else
layout (location = 10) in vec4 i_anchor; // x, y, z, heading
#endif

out DataVS {
	vec4 vColor;
	vec4 vLife;
	vec4 vPar;
	vec3 vN;       // sphere-space normal (for patterns, hits)
	vec3 vWN;      // world normal (for fresnel)
	vec3 vWorld;
	vec4 vH0;
	vec4 vH1;
	vec4 vH2;
	vec4 vH3;
	float vEnv;
};

void main() {
	float now = fxNow();
	float start = i_life.x;
	float end = i_life.y;
	float ttl = end - start;
	float env = fxEnvelope(now, start, end, 12.0, ttl > 1.0e6 ? 15.0 : max(3.0, min(ttl * 0.3, 15.0)));
	if (env < 0.002) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
#if ATTACHED == 1
	vec4 anc = uni[instData.y].drawPos;
#else
	vec4 anc = i_anchor;
#endif
	float ak = smoothstep(i_anim.z, i_anim.z + max(i_anim.w, 0.001), now);
	float sc = mix(i_anim.x, 1.0, ak);
	float al = mix(i_anim.y, 1.0, ak);
	// pops in with a small overshoot
	float pop = 1.0 + 0.12 * sin(clamp((now - start) / 12.0, 0.0, 1.0) * PI) * (1.0 - smoothstep(0.0, 1.0, (now - start) / 12.0));
	vec3 ext = i_shape.yzw * sc * pop * mix(0.6, 1.0, smoothstep(start, start + 10.0, now));
	vec3 n = normalize(sph.xyz);
	vec3 local = n * ext;
	vec3 wn = normalize(n / max(ext, vec3(0.001)));
	if (i_par.z > 0.5) {
		local = fxRotHeading(local, anc.w);
		wn = fxRotHeading(wn, anc.w);
	}
	vec3 world = anc.xyz + vec3(0.0, i_shape.x, 0.0) + local;
	gl_Position = cameraViewProj * vec4(world, 1.0);
	vColor = vec4(i_color.rgb, i_color.a * al);
	vLife = i_life;
	vPar = i_par;
	vN = n;
	vWN = wn;
	vWorld = world;
	vH0 = i_hit0;
	vH1 = i_hit1;
	vH2 = i_hit2;
	vH3 = i_hit3;
	vEnv = env;
}
