#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: camera-facing billboards. kind 0 = flash burst, 1 = energy orb (orbits its anchor).
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec4 quad;      // xy = -1..1
layout (location = 1) in vec4 i_pos;     // xyz (anchor / position), radius
layout (location = 2) in vec4 i_color;
layout (location = 3) in vec4 i_life;    // start, end, seed, kind
layout (location = 4) in vec4 i_orb;     // orbit, height, speed (rev/s), phase
layout (location = 5) in vec4 i_anim;    // scaleFrom, alphaFrom, animStart, animFrames
#if ATTACHED == 1
layout (location = 6) in uvec4 instData;
#endif

out DataVS {
	vec4 vUV;      // quad xy, life 0..1, kind
	vec4 vColor;
	vec4 vMisc;    // seed, envelope, radius, unused
};

void main() {
	float now = fxNow();
	float start = i_life.x;
	float end = i_life.y;
	float ttl = end - start;
	float kind = i_life.w;
	float fin = kind < 0.5 ? 1.0 : 10.0;
	float env = fxEnvelope(now, start, end, fin, kind < 0.5 ? 1.0 : max(2.0, min(ttl * 0.3, 15.0)));
	if (env < 0.002) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }

	vec3 c = i_pos.xyz;
#if ATTACHED == 1
	c = uni[instData.y].drawPos.xyz;
#endif
	if (kind > 0.5) {
		c += fxOrbOffset(i_orb, now);
	}
	float ak = smoothstep(i_anim.z, i_anim.z + max(i_anim.w, 0.001), now);
	float sc = mix(i_anim.x, 1.0, ak);
	float al = mix(i_anim.y, 1.0, ak);

	float life = ttl < 1.0e6 ? clamp((now - start) / max(ttl, 1.0), 0.0, 1.0) : 0.0;
	float radius = i_pos.w * sc;
	float size = radius;
	if (kind < 0.5) {
		size *= 0.45 + 0.55 * (1.0 - pow(1.0 - life, 3.0));
	} else {
		size *= 2.5;   // orb quad covers the halo and crackle around the ball
	}
	vec3 camPos = cameraViewInv[3].xyz;
	vec3 toCam = normalize(camPos - c);
	vec3 right = cameraViewInv[0].xyz;
	vec3 up = cameraViewInv[1].xyz;
	// pulled towards the camera so ground-level bursts are not cut in half by the terrain
	vec3 world = c + (right * quad.x + up * quad.y) * size + toCam * min(radius * 0.7, 60.0);
	gl_Position = cameraViewProj * vec4(world, 1.0);
	vUV = vec4(quad.xy, life, kind);
	vColor = vec4(i_color.rgb, i_color.a * al);
	vMisc = vec4(i_life.z, env, radius, 0.0);
}
