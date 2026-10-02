#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: procedural lightning. One instance = one bolt (or one branch, or one crawling arc),
// drawn as a camera-facing triangle strip of SEGS segments; the jagged path is evaluated here.
// passMode 0 = wide glow on a smoothed path, 1 = hot core on the full jagged path.
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec4 tv;        // x = t (0..1 along), y = side (-1 / 1)
layout (location = 1) in vec4 i_p0w;     // static: p0.xyz, width          | attached: rx, ry, rz, centerY
layout (location = 2) in vec4 i_p1j;     // static: p1.xyz, jitter (elmos) | attached: arcIndex, arcCount, reach, width
layout (location = 3) in vec4 i_color;
layout (location = 4) in vec4 i_life;    // start, end (frames), seed, static: grow frames | attached: re-pick period
layout (location = 5) in vec4 i_branch;  // static: anchorT (<0 = main bolt), branch vector xyz | attached: orb params
layout (location = 6) in vec4 i_extra;   // intensity, static: branch seed | attached: mode, glowScale, freq/jitterScale
#if ATTACHED == 1
layout (location = 7) in uvec4 instData;
#elif BOLTMODE == 1
layout (location = 7) in vec4 i_anchor;  // arcs at a map point: x, y, z, heading
#endif

uniform float passMode;

out DataVS {
	vec4 vColor;
	vec2 vUV;
	float vPass;
};

float now;
float tickSlow;
float tickFast;

void cullVertex() {
	gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
	vColor = vec4(0.0);
	vUV = vec2(0.0);
	vPass = passMode;
}

// 2D perpendicular offset of a bolt at t; full = all octaves (core), else smoothed first octave (glow)
vec2 jag(float t, float seed, float freq, bool full) {
	float x = t * freq;
	vec2 o;
	if (full) {
		o.x = linNoise(x, seed + tickSlow * 3.17);
		o.y = linNoise(x, seed + 71.3 + tickSlow * 3.17);
		o.x += 0.5 * linNoise(x * 2.7, seed + 11.0 + tickFast * 1.71);
		o.y += 0.5 * linNoise(x * 2.7, seed + 37.0 + tickFast * 1.71);
		o.x += 0.25 * linNoise(x * 6.3, seed + 23.0 + tickFast * 2.31);
		o.y += 0.25 * linNoise(x * 6.3, seed + 53.0 + tickFast * 2.31);
	} else {
		o.x = smoothNoise1(x, seed + tickSlow * 3.17);
		o.y = smoothNoise1(x, seed + 71.3 + tickSlow * 3.17);
	}
	return o;
}

#if BOLTMODE == 0
vec3 mainPath(float t, vec3 p0, vec3 p1, vec3 fa, vec3 fb, float amp, float freq, float seed, bool full) {
	vec2 o = jag(t, seed, freq, full);
	float env = pow(max(sin(PI * clamp(t, 0.0, 1.0)), 0.0), 0.75);
	return mix(p0, p1, t) + (fa * o.x + fb * o.y) * amp * env;
}
#endif

void main() {
	now = fxNow();
	tickSlow = mod(floor(now / 5.0), 2048.0);
	tickFast = mod(floor(now / 2.0), 2048.0);
	bool full = passMode > 0.5;

	float start = i_life.x;
	float end = i_life.y;
	float seed = i_life.z;
	float ttl = end - start;
	float env = fxEnvelope(now, start, end, max(1.0, min(3.0, ttl * 0.1)), max(2.0, min(ttl * 0.45, 20.0)));
	if (env < 0.002) { cullVertex(); return; }

	float t = tv.x;
	float intensity = i_extra.x * env;
	float width;
	vec3 pHere;
	vec3 pA;
	vec3 pB;
	float dt = 0.6 / float(SEGS);

#if BOLTMODE == 0
	vec3 p0 = i_p0w.xyz;
	vec3 p1 = i_p1j.xyz;
	vec3 dir = p1 - p0;
	float len = length(dir);
	if (len < 0.5) { cullVertex(); return; }
	vec3 fa;
	vec3 fb;
	fxFrame(dir / len, fa, fb);
	float amp = i_p1j.w > 0.0 ? i_p1j.w : clamp(len * 0.075, 3.0, 55.0);
	float freq = clamp(len / 70.0, 2.5, 11.0);
	width = i_p0w.w;

	float grow = i_life.w;
	float g = grow > 0.0 ? clamp((now - start) / grow, 0.0, 1.0) : 1.0;
	// the return stroke: a bright surge right when the leader connects
	float sinceConnect = now - start - grow;
	float surge = (grow > 0.0 && sinceConnect > 0.0) ? exp(-sinceConnect / 4.0) : 0.0;
	intensity *= 1.0 + 1.3 * surge;

	// flicker per tick, occasional dropouts for long-lived bolts
	float fl = 0.72 + 0.56 * hash12(vec2(seed, tickFast));
	if (ttl > 12.0 && hash12(vec2(seed + 3.1, tickFast)) < 0.16) fl *= 0.3;
	intensity *= fl;

	float anchorT = i_branch.x;
	if (anchorT < 0.0) {
		float tt = t * g;
		pHere = mainPath(tt, p0, p1, fa, fb, amp, freq, seed, full);
		pA = mainPath(max(tt - dt, 0.0), p0, p1, fa, fb, amp, freq, seed, full);
		pB = mainPath(min(tt + dt, 1.0), p0, p1, fa, fb, amp, freq, seed, full);
		width *= 0.8 + 0.45 * hash12(vec2(floor(tt * freq * 6.3), tickFast + seed));
		if (grow > 0.0 && g < 1.0) width *= mix(0.55, 1.0, tt / max(g, 0.01));
	} else {
		float gb = clamp((g - anchorT) / max(1.0 - anchorT, 0.05) * 1.6, 0.0, 1.0);
		if (gb <= 0.0) { cullVertex(); return; }
		// branches are recomputed from the parent's full path so they stay attached when it re-jitters
		vec3 s = mainPath(anchorT, p0, p1, fa, fb, amp, freq, seed, true);
		vec3 bv = i_branch.yzw;
		float bl = length(bv);
		vec3 ba;
		vec3 bb;
		fxFrame(bv / max(bl, 0.001), ba, bb);
		float bseed = i_extra.y;
		float bamp = bl * 0.16;
		float bfreq = clamp(bl / 45.0, 2.0, 7.0);
		float tt = t * gb;
		vec2 o = jag(tt, bseed, bfreq, full);
		vec2 oa = jag(max(tt - dt, 0.0), bseed, bfreq, full);
		vec2 ob = jag(min(tt + dt, 1.0), bseed, bfreq, full);
		pHere = s + bv * tt + (ba * o.x + bb * o.y) * bamp * sqrt(tt);
		pA = s + bv * max(tt - dt, 0.0) + (ba * oa.x + bb * oa.y) * bamp * sqrt(max(tt - dt, 0.0));
		pB = s + bv * min(tt + dt, 1.0) + (ba * ob.x + bb * ob.y) * bamp * sqrt(min(tt + dt, 1.0));
		width *= 0.55 * (1.0 - 0.75 * tt);
		intensity *= 0.8;
	}
#else
#if ATTACHED == 1
	vec4 dp = uni[instData.y].drawPos;
#else
	vec4 dp = i_anchor;
#endif
	float mode = i_extra.y;
	float arcIndex = i_p1j.x;
	float arcCount = max(i_p1j.y, 1.0);
	float reach = i_p1j.z;
	width = i_p1j.w;
	float period = max(i_life.w, 1.0);
	float epochF = (now + arcIndex / arcCount * period * 1.37) / period;
	float epoch = mod(floor(epochF), 4096.0);
	float ef = fract(epochF);
	vec2 key = vec2(seed + arcIndex * 7.13, epoch);
	if (hash12(key + 3.3) > 0.78) { cullVertex(); return; }   // this arc sleeps this epoch
	intensity *= pow(1.0 - ef, 1.3) * smoothstep(0.0, 0.06, ef);
	intensity *= 0.75 + 0.5 * hash12(vec2(seed + arcIndex, tickFast));
	vec3 dA = normalize(hash32(key) * 2.0 - 1.0 + vec3(0.0, 0.001, 0.0));
	float jitterScale = i_extra.w > 0.0 ? i_extra.w : 1.0;
	float aseed = seed + arcIndex * 13.7 + epoch * 0.37;
	vec3 fa;
	vec3 fb;
	if (mode < 0.5) {
		// body crawl: an arc between two nearby points on the unit's (heading-rotated) ellipsoid
		vec3 C = dp.xyz + vec3(0.0, i_p0w.w, 0.0);
		vec3 ext = i_p0w.xyz;
		dA.y = abs(dA.y) * 0.9 + 0.08;
		dA = normalize(dA);
		vec3 dB = normalize(dA + (hash32(key + 19.7) * 2.0 - 1.0) * 1.3);
		dB.y = abs(dB.y) * 0.9 + 0.05;
		dB = normalize(dB);
		vec3 sA = C + fxRotHeading(dA * ext, dp.w);
		vec3 sB = C + fxRotHeading(dB * ext, dp.w);
		vec3 chord = sB - sA;
		float L = max(length(chord), 1.0);
		fxFrame(chord / L, fa, fb);
		float amp = L * 0.13 * jitterScale;
		float freq = clamp(L / 18.0, 2.0, 7.0);
		for (int k = 0; k < 3; k++) {
			float tk = clamp(t + float(k - 1) * dt, 0.0, 1.0);
			vec3 d = normalize(mix(dA, dB, tk));
			vec3 surf = C + fxRotHeading(d * ext, dp.w);
			vec3 outward = normalize(surf - C);
			vec2 o = jag(tk, aseed, freq, full);
			vec3 p = surf + outward * (reach * L * 0.35 * sin(PI * tk)) + (fa * o.x + fb * o.y) * amp * sin(PI * tk);
			if (k == 0) pA = p; else if (k == 1) pHere = p; else pB = p;
		}
		width *= 0.85 + 0.3 * sin(PI * t);
	} else {
		// orb tendrils: from the orb's surface outward, free end flickers
		vec3 C = dp.xyz + fxOrbOffset(i_branch, now);
		float r0 = i_p0w.x;
		fxFrame(dA, fa, fb);
		float amp = reach * 0.22 * jitterScale;
		float freq = 4.0;
		for (int k = 0; k < 3; k++) {
			float tk = clamp(t + float(k - 1) * dt, 0.0, 1.0);
			vec2 o = jag(tk, aseed, freq, full);
			vec3 p = C + dA * (r0 * 0.8 + tk * reach) + (fa * o.x + fb * o.y) * amp * sqrt(tk);
			if (k == 0) pA = p; else if (k == 1) pHere = p; else pB = p;
		}
		width *= 1.0 - 0.8 * t;
	}
#endif

	vec3 seg = pB - pA;
	float segLen = length(seg);
	if (segLen < 0.0001) { cullVertex(); return; }
	seg /= segLen;

	vec3 camPos = cameraViewInv[3].xyz;
	vec3 toCam = normalize(camPos - pHere);
	vec3 right = cross(seg, toCam);
	float rl = length(right);
	right = rl > 0.05 ? right / rl : normalize(cross(seg, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	float camDist = length(camPos - pHere);

	float w;
	float cover;
	if (full) {
		w = width * 1.7;
		float minW = camDist * 0.0011;
		cover = clamp(w / max(minW, 0.001), 0.25, 1.0);
		w = max(w, minW);
	} else {
		float gs = i_extra.z > 0.0 ? i_extra.z : 9.0;
		w = width * gs + 3.0;
		float minW = camDist * 0.005;
		cover = clamp(w / max(minW, 0.001), 0.3, 1.0);
		w = max(w, minW);
	}

	vec3 world = pHere + right * tv.y * w;
	// the wide glow is pulled towards the camera so terrain does not slice it with a hard edge
	if (!full) world += toCam * min(w * 0.9, 40.0);
	gl_Position = cameraViewProj * vec4(world, 1.0);
	vColor = vec4(i_color.rgb, intensity * i_color.a * cover);
	vUV = vec2(t, tv.y);
	vPass = passMode;
}
