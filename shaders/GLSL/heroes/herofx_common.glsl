// Hero FX shared GLSL (inserted by fx_t4_heroes.lua at //__HEROFX_COMMON__).
// Time is in sim frames (30/s), interpolated: timeInfo.x + timeInfo.w.
#define PI 3.14159265
#define TAU 6.2831853

float fxNow() { return timeInfo.x + timeInfo.w; }

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
vec3 hash32(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// 1D value noise in -1..1. lin = piecewise linear (jagged), smooth = cubic.
float linNoise(float x, float s) {
	float i = floor(x);
	float f = x - i;
	return mix(hash12(vec2(i, s)), hash12(vec2(i + 1.0, s)), f) * 2.0 - 1.0;
}
float smoothNoise1(float x, float s) {
	float i = floor(x);
	float f = x - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash12(vec2(i, s)), hash12(vec2(i + 1.0, s)), f) * 2.0 - 1.0;
}
// periodic (wraps every n cells) linear noise, for angles
float linNoiseWrap(float x, float n, float s) {
	float i = floor(x);
	float f = x - i;
	float a = hash12(vec2(mod(i, n), s));
	float b = hash12(vec2(mod(i + 1.0, n), s));
	return mix(a, b, f) * 2.0 - 1.0;
}

// 2D value noise 0..1 and fbm
float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise2(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}
float fbm2lo(vec2 p) {
	return 0.6 * vnoise2(p) + 0.4 * vnoise2(p * 2.1 + vec2(5.3, 1.7));
}

// life envelope: fade in over fin frames from start, fade out over fout frames before end
float fxEnvelope(float now, float start, float end, float fin, float fout) {
	return smoothstep(start, start + fin, now) * (1.0 - smoothstep(end - fout, end, now));
}

// a stable perpendicular frame around a direction
void fxFrame(vec3 fwd, out vec3 a, out vec3 b) {
	vec3 upRef = abs(fwd.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	a = normalize(cross(fwd, upRef));
	b = normalize(cross(fwd, a));
}

// distance to a hexagon border (hex of unit cell size), p in cell-local coords
float hexDist(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.5, 0.8660254)), p.x);
}
// returns (local.xy, id.xy) for a pointy hex grid with unit spacing
vec4 hexCoords(vec2 uv) {
	const vec2 r = vec2(1.0, 1.7320508);
	const vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	return vec4(gv, uv - gv);
}

#if ATTACHED == 1 && HEROFX_VS == 1
struct SUniformsBuffer {
	uint composite;
	uint unused2;
	uint unused3;
	uint unused4;
	float maxHealth;
	float health;
	float unused5;
	float unused6;
	vec4 drawPos;
	vec4 speed;
	vec4[4] userDefined;
};
layout(std140, binding = 1) readonly buffer UniformsBuffer {
	SUniformsBuffer uni[];
};
#endif

// unit heading: 0 along +z, increasing towards +x
vec3 fxRotHeading(vec3 v, float h) {
	float s = sin(h);
	float c = cos(h);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

// orb position relative to its unit, must match HeroFX.orbPos in Lua
vec3 fxOrbOffset(vec4 orb, float now) {
	// orb = (orbit radius, height, revolutions per second, phase)
	float a = orb.w + now * orb.z * TAU / 30.0;
	float bob = sin(now * 0.07 + orb.w) * 4.0;
	return vec3(cos(a) * orb.x, orb.y + bob, sin(a) * orb.x);
}
