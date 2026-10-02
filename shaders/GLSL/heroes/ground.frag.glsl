#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: ground patterns. kind: 0 shock, 1 rune, 2 hex, 3 electric, 4 heat, 5 heal, 6 glow, 7 sweep,
// 8 fog, 9 web, 10 mark (reticle + stack segments), 11 fire, 12 swirl. Optional sector (cone) mask.
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vLocal;
	vec4 vRad;
	vec4 vColor;
	vec4 vLife;
	vec4 vSector;
};

out vec4 fragColor;

float now;
float px;   // elmos per pixel around this fragment

float lineG(float dist, float th) {
	th = max(th, px * 0.9);
	return exp(-(dist * dist) / (th * th));
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float glyph(vec2 uv, float id, float th) {
	float g = 0.0;
	for (int s = 0; s < 4; s++) {
		vec2 h1 = hash22(vec2(id, float(s) * 7.1 + 0.3));
		vec2 h2 = hash22(vec2(id + 3.7, float(s) * 3.3 + 1.1));
		vec2 a = (floor(h1 * 3.0) - 1.0) * vec2(0.27, 0.3);
		vec2 b = (floor(h2 * 3.0) - 1.0) * vec2(0.27, 0.3);
		if (dot(a - b, a - b) < 0.001) { b = vec2(-a.x, a.y * 0.2); }
		float dd = sdSegment(uv, a, b);
		g = max(g, exp(-(dd * dd) / (th * th)));
	}
	// a dot or a small circle in some glyphs
	float hc = hash12(vec2(id, 91.7));
	if (hc > 0.6) {
		g = max(g, exp(-pow(length(uv) - 0.14, 2.0) / (th * th)));
	}
	return g;
}

void main() {
	now = fxNow();
	vec2 p = vLocal.xy;
	float kind = vLocal.z;
	float env = vLocal.w;
	float d = length(p);
	px = max(fwidth(d), 0.05);
	float ang = atan(p.y, p.x);
	float r0 = vRad.x;
	float r1 = vRad.y;
	float width = max(vRad.z, 1.0);
	float seed = vRad.w;
	float start = vLife.x;
	float end = vLife.y;
	bool timed = (end - start) < 1.0e6;
	float age = now - start;
	float life = timed ? clamp(age / max(end - start, 1.0), 0.0, 1.0) : 0.0;
	float tick = mod(floor(now / 2.0), 1024.0);

	float I = 0.0;     // light in the effect colour
	float hot = 0.0;   // extra white-hot light
	float occ = 0.0;   // tint/occlusion amount

	if (kind < 0.5) {
		// ---- shock: expanding front with a rippling, heat-haze-like wake
		float e = 1.0 - pow(1.0 - life, 3.0);
		float rc = mix(r0, r1, e);
		float w = width * (0.6 + 0.9 * life);
		if (d > rc + w * 2.5) discard;
		float ed = d - rc;
		float n = fbm2lo(p * 0.025 + seed);
		float front = ed > 0.0 ? exp(-(ed * ed) / (w * w * 0.1)) : exp(ed / (w * 0.9));
		front *= 0.65 + 0.7 * n;
		float wake = ed < 0.0 ? exp(ed / (w * 3.5)) * (0.5 + 0.5 * sin(ed / w * 6.5 + now * 0.5)) : 0.0;
		float inner = (1.0 - smoothstep(0.0, max(rc, 1.0), d)) * 0.3 * (1.0 - life);
		float fade = pow(1.0 - life, 1.2);
		I = (front * 1.25 + wake * 0.4 + inner) * fade;
		hot = pow(front, 3.0) * 0.8 * fade;
		occ = I * 0.35;
	} else if (kind < 1.5) {
		// ---- rune circle: rotating glyph band, double circles, counter-rotating hexagram
		float grow = smoothstep(0.0, 20.0, age);
		float rr = r1 * (0.3 + 0.7 * grow);
		float wb = max(width, rr * 0.12);
		if (d > rr + wb) discard;
		float rot = vLife.z != 0.0 ? vLife.z : 0.35;
		float rotA = ang + now * rot / 30.0;
		float lw = 1.2 + rr * 0.004;
		float outer = lineG(d - rr, lw) + 0.35 * exp(-abs(d - rr) / (wb * 0.35));
		float inner = lineG(d - (rr - wb), lw * 0.9);
		float runes = 0.0;
		if (d < rr && d > rr - wb) {
			float N = max(floor(TAU * (rr - wb * 0.5) / (wb * 0.9)), 6.0);
			float a01 = fract(rotA / TAU) * N;
			float ci = floor(a01);
			vec2 cuv = vec2(fract(a01) - 0.5, (d - (rr - wb)) / wb - 0.5);
			float th = max(0.055, px / wb * 1.2);
			runes = glyph(cuv, ci + seed * 13.0, th) * (0.55 + 0.45 * sin(now * 0.12 + ci * 1.3));
		}
		float ri = (rr - wb) * 0.78;
		float star = 0.0;
		float rotB = -now * rot * 0.7 / 30.0 + seed;
		for (int k = 0; k < 6; k++) {
			float th = rotB + float(k) * TAU / 6.0;
			vec2 nrm = vec2(cos(th), sin(th));
			float dist = abs(dot(p, nrm) - ri * 0.5);
			star = max(star, lineG(dist, lw * 0.8));
		}
		star *= 1.0 - smoothstep(ri - 2.0, ri + 2.0, d);
		float ring2 = lineG(d - ri, lw * 0.8);
		float fill = 0.07 * (1.0 - smoothstep(0.0, rr, d));
		float shimmer = 0.75 + 0.25 * sin(ang * 3.0 - now * 0.12);
		I = ((outer + inner * 0.8 + ring2 * 0.7 + runes * 1.1 + star * 0.75) * shimmer + fill) * (0.6 + 0.4 * grow);
		hot = (lineG(d - rr, lw * 0.5) + runes * 0.4) * 0.5;
		occ = I * 0.4;
		if (timed) { I *= 1.0 - life * 0.3; }
	} else if (kind < 2.5) {
		// ---- hex grid lit by an expanding wave, flickering cells, bright rim
		float s = max(width, 8.0);
		if (d > r1 + s) discard;
		vec4 hc = hexCoords(p / s);
		float hd = hexDist(hc.xy);
		vec2 cid = hc.zw;
		float cd = length(cid * s);
		float edgeL = smoothstep(0.38, 0.5, hd);
		float rc = timed ? mix(r0, r1 * 1.15, 1.0 - pow(1.0 - life, 2.0)) : mod(age * 4.0, r1 * 1.4);
		float wave = exp(-pow((cd - rc) / (s * 2.2), 2.0));
		float flick = hash12(cid + vec2(seed, floor(now / 4.0)));
		float inside = 1.0 - smoothstep(r1 - s * 0.5, r1, cd);
		float cellGlow = (wave * 0.8 + 0.25 * step(0.88, flick)) * (1.0 - hd * 1.4);
		float lines = edgeL * (0.25 + wave * 1.3);
		float border = lineG(d - r1, 1.6 + r1 * 0.003) + 0.3 * exp(-abs(d - r1) / (s * 0.6));
		float fade = timed ? 1.0 - smoothstep(0.55, 1.0, life) : 1.0;
		I = ((cellGlow + lines) * inside + border) * fade;
		hot = wave * edgeL * inside * 0.6 * fade;
		occ = I * 0.35;
	} else if (kind < 3.5) {
		// ---- electric: jagged lightning running around the ring + arcs crawling inward
		float rc = timed ? mix(r0, r1, 1.0 - pow(1.0 - life, 2.5)) : r1;
		float amp = max(width * 0.5, 4.0);
		if (d > rc + amp * 4.0) discard;
		float N1 = max(floor(TAU * rc / 26.0), 12.0);
		float x = (ang / TAU + 0.5) * N1;
		for (int k = 0; k < 2; k++) {
			float s = seed + float(k) * 31.0 + tick * 1.37;
			float disp = linNoiseWrap(x, N1, s) * amp + 0.5 * amp * linNoiseWrap(x * 3.0, N1 * 3.0, s + 5.0);
			float dist = abs(d - rc - disp);
			I += lineG(dist, 1.1 + rc * 0.0015) * 1.2 + exp(-dist / (amp * 0.8)) * 0.22;
			hot += lineG(dist, 0.6 + rc * 0.001) * 0.8;
		}
		float M = max(floor(TAU * rc / 55.0), 8.0);
		float xa = (ang / TAU + 0.5) * M;
		float ci = floor(xa);
		float fa = fract(xa) - 0.5;
		float hs = hash12(vec2(ci + seed, tick));
		if (hs < 0.5 && d < rc) {
			float rIn = rc * mix(0.2, 0.75, hash12(vec2(ci + seed + 9.0, tick)));
			if (d > rIn) {
				float arcLen = fa * TAU / M * d;
				float tR = (rc - d) / max(rc - rIn, 1.0);
				float jit = (linNoise(d * 0.05, ci * 3.1 + tick) + 0.5 * linNoise(d * 0.16, ci * 1.7 + tick)) * amp * 1.4 * sin(PI * min(tR, 0.5));
				float dl = abs(arcLen - jit);
				float taper = 1.0 - tR * 0.75;
				I += (lineG(dl, 1.0) * 1.1 + exp(-dl / (amp * 0.6)) * 0.15) * taper;
				hot += lineG(dl, 0.5) * 0.6 * taper;
			}
		}
		I += 0.14 * (1.0 - smoothstep(0.0, rc, d)) * (0.4 + fbm2lo(p * 0.03 + vec2(tick * 0.37)));
		float fl = 0.75 + 0.5 * hash12(vec2(tick, seed));
		float fade = timed ? 1.0 - smoothstep(0.5, 1.0, life) : 1.0;
		I *= fl * fade;
		hot *= fl * fade;
		occ = I * 0.3;
	} else if (kind < 4.5) {
		// ---- heat: shimmering isolines over a hot disc
		float r = r1;
		if (d > r + 20.0) discard;
		float disc = 1.0 - smoothstep(r * 0.5, r, d);
		float n = fbm2(p * 0.016 + vec2(now * 0.004, -now * 0.006) + seed);
		float iso = pow(abs(sin(n * 18.0 - now * 0.07)), 12.0);
		float edge = lineG(d - r, 2.5) * 0.6 + 0.25 * exp(-abs(d - r) / 10.0);
		I = disc * (0.12 + iso * 0.55) + edge * (0.75 + 0.25 * sin(now * 0.2));
		hot = disc * iso * 0.15;
		occ = I * 0.4;
	} else if (kind < 5.5) {
		// ---- heal: soft disc, rings converging inward, twinkling crosses
		float r = r1;
		if (d > r + 10.0) discard;
		float disc = 1.0 - smoothstep(r * 0.6, r, d);
		float rings = pow(0.5 + 0.5 * sin(d * 0.09 + now * 0.15), 8.0) * disc;
		vec2 g = p / 26.0;
		vec2 ci = floor(g);
		vec2 f = fract(g) - 0.5;
		float tw = hash12(ci + seed);
		float ph = fract(tw * 7.0 + now / 70.0);
		float cth = max(0.06, px / 26.0);
		float plus = exp(-f.x * f.x / (cth * cth)) * step(abs(f.y), 0.22) + exp(-f.y * f.y / (cth * cth)) * step(abs(f.x), 0.22);
		plus *= step(0.72, tw) * sin(PI * ph) * disc;
		float edge = lineG(d - r, 2.0) + 0.3 * exp(-abs(d - r) / 8.0);
		I = 0.1 * disc + rings * 0.45 + plus * 0.9 + edge * 0.8;
		hot = plus * 0.3;
		occ = I * 0.35;
	} else if (kind < 6.5) {
		// ---- glow: soft light pool on the ground (under flashes, pillars, orbs)
		if (d > r1) discard;
		float g = exp(-d * d / (r1 * r1) * 4.0) - exp(-4.0);
		float fade = timed ? pow(1.0 - life, 1.5) : 1.0;
		I = g * (0.9 + 0.1 * sin(now * 0.5 + seed)) * fade * 1.2;
		hot = g * g * 0.4 * fade;
		occ = I * 0.25;
	} else if (kind < 7.5) {
		// ---- sweep: a burning band under a rotating beam; the swept part keeps glowing as embers
		float band = exp(-pow((d - r1) / width, 2.0));
		if (band < 0.01 && d > r0 + 4.0) discard;
		float rot = vLife.z;
		float a0 = vLife.w;
		float swept = abs(rot) * max(age, 0.0) / 30.0;
		float beamAng = a0 + rot * max(age, 0.0) / 30.0;
		float diff = mod((beamAng - ang) * sign(rot + 1.0e-6), TAU);
		float laps = floor(swept / TAU);
		float since = (diff / max(abs(rot), 0.01));   // seconds since the beam passed here
		float covered = (diff <= swept) ? 1.0 : 0.0;
		float emb = fbm2(p * 0.045 + vec2(seed, now * 0.01));
		float trail = exp(-since * 2.2) * 1.5 + exp(-since * 0.4) * (0.15 + 0.5 * emb * emb);
		float inner = (d < r0) ? 0.06 : 0.0;
		float fade = timed ? 1.0 - smoothstep(0.75, 1.0, life) : 1.0;
		I = (band * trail * max(covered, step(1.0, laps)) + inner) * fade;
		hot = band * exp(-since * 5.0) * 0.9 * covered * fade;
		occ = I * 0.4;
	} else if (kind < 8.5) {
		// ---- fog: drifting smoke/fog bank (mostly tints/occludes, little light)
		float r = r1;
		if (d > r + 30.0) discard;
		vec2 drift = vec2(now * 0.012, now * 0.007);
		float n = fbm2(p * 0.008 + drift + seed);
		float n2 = fbm2(p * 0.02 - drift * 1.7 + seed * 1.3);
		float edgeN = (n - 0.5) * r * 0.35;
		float disc = 1.0 - smoothstep(r * 0.55, r + edgeN, d);
		float dens = disc * smoothstep(0.25, 0.75, n * 0.7 + n2 * 0.5);
		I = dens * 0.35;
		hot = 0.0;
		occ = dens * 0.75;
	} else if (kind < 9.5) {
		// ---- web: radial spokes + sagging polygonal threads, a pulse running along the threads
		float r = r1;
		if (d > r + 6.0) discard;
		float spokes = 12.0;
		float sa = (ang / TAU + 0.5) * spokes;
		float si = floor(sa + 0.5);
		float spokeDist = abs(sa - si) * TAU / spokes * d;
		float web = lineG(spokeDist, 0.9 + d * 0.004);
		float spacing = max(width, 14.0);
		// polygon threads sag between spokes
		float sf = fract(sa) - 0.5;
		float sag = (0.25 - sf * sf) * spacing * 0.5;
		float rr = d + sag;
		float ringI = floor(rr / spacing + 0.5);
		float ringDist = abs(rr - ringI * spacing);
		float rings = lineG(ringDist, 0.8 + d * 0.003) * step(0.5, ringI);
		float pulse = 0.6 + 0.4 * sin(d * 0.05 - now * 0.2);
		float disc = 1.0 - smoothstep(r - 4.0, r + 2.0, d);
		I = (web + rings) * pulse * disc + lineG(d - r, 1.5) * 0.6;
		hot = (web + rings) * 0.2 * disc;
		occ = I * 0.4;
	} else if (kind < 10.5) {
		// ---- mark: rotating reticle brackets + segmented stack ring (vLife.z = max stacks, vSector.w = stacks)
		float r = r1;
		if (d > r * 1.35) discard;
		float maxS = max(vLife.z, 1.0);
		float stacks = vSector.w;
		float rotA = ang + now * 0.06;
		// stack segments
		float sa = fract(rotA / TAU) * maxS;
		float segI = floor(sa);
		float segF = fract(sa);
		float gap = smoothstep(0.0, 0.08, segF) * (1.0 - smoothstep(0.92, 1.0, segF));
		float lit = step(segI + 0.5, stacks);
		float ringD = abs(d - r);
		float seg = exp(-(ringD * ringD) / (max(width, 3.0) * max(width, 3.0) * 0.25)) * gap;
		float segLight = seg * (lit * (1.1 + 0.25 * sin(now * 0.3 + segI)) + (1.0 - lit) * 0.18);
		// four counter-rotating brackets outside the ring
		float rb = r * 1.18;
		float ba = ang - now * 0.09;
		float bq = mod(ba, TAU / 4.0) - TAU / 8.0;
		float bracket = lineG(d - rb, 1.2 + r * 0.01) * (1.0 - smoothstep(0.18, 0.26, abs(bq)));
		float tick = lineG(abs(bq) * d, 1.0) * step(r * 1.05, d) * step(d, r * 1.3);
		// inner dot
		float core = exp(-d * d / (r * r * 0.02)) * 0.4;
		I = segLight + bracket * 0.9 + tick * 0.6 + core;
		hot = seg * lit * 0.5;
		occ = I * 0.45;
	} else if (kind < 11.5) {
		// ---- fire: flame tongues licking outward from the centre (use with arc for cones)
		float r = r1;
		if (d > r * 1.15) discard;
		float rn = d / r;
		float fl = fbm2(vec2(ang * 3.0 + seed, d * 0.035 - now * 0.11));
		float fl2 = fbm2(vec2(ang * 7.0 - seed, d * 0.07 - now * 0.19));
		float tongue = smoothstep(rn - 0.1, rn + 0.45, fl * 0.9 + fl2 * 0.5);
		float body = tongue * (1.0 - smoothstep(0.75, 1.1, rn));
		float coreF = body * (1.0 - smoothstep(0.0, 0.6, rn));
		float fade = timed ? 1.0 - smoothstep(0.7, 1.0, life) : 1.0;
		I = (body * 1.1 + coreF * 0.6) * fade;
		hot = pow(body, 3.0) * 0.9 * (1.0 - rn) * fade;
		occ = body * 0.4 * fade;
	} else {
		// ---- swirl: whirlpool / gravity well, spiral arms flowing inward to a dark core
		float r = r1;
		if (d > r + 10.0) discard;
		float rn = d / r;
		float arms = 4.0;
		float spin = vLife.z != 0.0 ? vLife.z : 1.0;
		float sp = ang * arms + log(d + 8.0) * 7.0 + now * 0.12 * spin;
		float n = fbm2lo(p * 0.02 + seed);
		float band = pow(0.5 + 0.5 * sin(sp + n * 3.0), 3.0);
		float disc = 1.0 - smoothstep(0.75, 1.0, rn);
		float well = 1.0 - smoothstep(0.0, 0.35, rn);
		I = band * disc * (0.25 + 0.9 * (1.0 - rn)) + lineG(d - r, 1.5 + r * 0.004) * 0.5;
		hot = band * disc * pow(1.0 - rn, 3.0) * 0.6;
		occ = disc * 0.25 + well * 0.6;
		if (timed) { float f = 1.0 - smoothstep(0.8, 1.0, life); I *= f; hot *= f; occ *= f; }
	}

	// sector / cone mask: vSector.x = arc (rad, 0 = full circle), .y = centre angle, .z = rad/s
	float arc = vSector.x;
	if (arc > 0.001 && arc < TAU - 0.001) {
		float cA = vSector.y + vSector.z * max(age, 0.0) / 30.0;
		float da = abs(mod(ang - cA + PI, TAU) - PI);
		float soft = min(0.12, arc * 0.15);
		float mask = 1.0 - smoothstep(arc * 0.5 - soft, arc * 0.5, da);
		if (mask <= 0.0) discard;
		// thin bright edges along the cone sides
		float sideDist = abs(da - arc * 0.5 + soft * 0.5) * d;
		float side = lineG(sideDist, 1.2) * step(d, r1) * 0.35 * mask;
		I = I * mask + side;
		hot *= mask;
		occ *= mask;
	}

	I *= env * vColor.a;
	hot *= env * vColor.a;
	vec3 rgb = vColor.rgb * I + vec3(1.0, 0.97, 0.92) * hot;
	if (max(rgb.r, max(rgb.g, rgb.b)) < 0.003) discard;
	fragColor = vec4(rgb, clamp(occ * env * vColor.a, 0.0, 0.85));
}
