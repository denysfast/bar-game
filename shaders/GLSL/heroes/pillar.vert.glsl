#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: light column. An open tube shaded as a glowing volume (intensity ~ chord length through it);
// pass 0 = coloured outer shell, pass 1 = thin white-hot inner core.
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec4 tube;      // cos, y01, sin, angle01
layout (location = 1) in vec4 i_base;    // x, y (ground), z, radius
layout (location = 2) in vec4 i_color;
layout (location = 3) in vec4 i_life;    // start, end, seed, height

uniform float passMode;

out DataVS {
	vec4 vP;       // y01, angle01, life, envelope
	vec4 vColor;
	vec3 vNormal;
	vec3 vWorld;
	float vPass;
};

void main() {
	float now = fxNow();
	float start = i_life.x;
	float end = i_life.y;
	float ttl = end - start;
	float env = fxEnvelope(now, start, end, 2.0, max(4.0, min(ttl * 0.45, 30.0)));
	if (env < 0.002) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
	float life = ttl < 1.0e6 ? clamp((now - start) / max(ttl, 1.0), 0.0, 1.0) : 0.0;
	float age = now - start;

	float y01 = tube.y;
	float h = i_life.w * smoothstep(0.0, 9.0, age);              // shoots up in ~0.3 s
	float r = i_base.w;
	if (passMode > 0.5) r *= 0.32;
	r *= 1.0 + 0.9 * exp(-y01 * 7.0);                             // flared base
	r *= mix(1.0, 0.55, smoothstep(0.55, 1.0, life));              // collapses while fading
	r *= 1.0 + 0.05 * sin(now * 0.6 + y01 * 9.0 + i_life.z);

	vec3 n = vec3(tube.x, 0.0, tube.z);
	vec3 world = i_base.xyz + vec3(tube.x * r, y01 * h, tube.z * r);
	gl_Position = cameraViewProj * vec4(world, 1.0);
	vP = vec4(y01, tube.w, life, env);
	vColor = i_color;
	vNormal = n;
	vWorld = world;
	vPass = passMode;
}
