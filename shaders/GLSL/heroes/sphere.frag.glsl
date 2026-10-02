#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vColor;
	vec4 vLife;
	vec4 vPar;
	vec3 vN;
	vec3 vWN;
	vec3 vWorld;
	vec4 vH0;
	vec4 vH1;
	vec4 vH2;
	vec4 vH3;
	float vEnv;
};

out vec4 fragColor;

float now = 0.0;

// triplanar hex edge mask + cell id hash
vec2 hexTri(vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec4 a = hexCoords(n.yz * scale);
	vec4 b = hexCoords(n.xz * scale);
	vec4 c = hexCoords(n.xy * scale);
	float ea = smoothstep(0.36, 0.5, hexDist(a.xy));
	float eb = smoothstep(0.36, 0.5, hexDist(b.xy));
	float ec = smoothstep(0.36, 0.5, hexDist(c.xy));
	float edge = ea * w.x + eb * w.y + ec * w.z;
	float cell = hash12(a.zw + 1.3) * w.x + hash12(b.zw + 7.1) * w.y + hash12(c.zw + 3.7) * w.z;
	return vec2(edge, cell);
}

// expanding ripple from a hit: returns (wave, spot)
vec2 hitRipple(vec4 h, vec3 n) {
	float age = now - h.w;
	if (h.w <= 0.0 || age < 0.0 || age > 50.0) return vec2(0.0);
	float ad = acos(clamp(dot(n, normalize(h.xyz)), -1.0, 1.0));
	float front = age * 0.05;
	float k = 1.0 - age / 50.0;
	float wave = exp(-pow((ad - front) / 0.1, 2.0)) * k * k;
	float spot = exp(-ad * ad * 40.0) * exp(-age / 7.0);
	return vec2(wave, spot);
}

void main() {
	now = fxNow();
	vec3 camPos = cameraViewInv[3].xyz;
	vec3 v = normalize(camPos - vWorld);
	vec3 wn = normalize(vWN);
	float ndv = abs(dot(wn, v));
	float kind = vLife.w;
	float seed = vLife.z;
	vec3 col = vColor.rgb;
	vec3 hotC = vec3(1.0, 0.98, 0.95);
	vec3 rgb;
	float a;
	float back = gl_FrontFacing ? 1.0 : 0.4;

	if (kind < 0.5) {
		float fp = vPar.y > 0.0 ? vPar.y : 2.6;
		float fres = pow(1.0 - ndv, fp);
		float energy = fbm2(vN.xz * 2.5 + vec2(now * 0.006, vN.y * 2.0 - now * 0.01) + seed);
		float hexE = 0.0;
		float cell = 0.0;
		if (vPar.x > 0.0) {
			vec2 hx = hexTri(vN, vPar.x);
			hexE = hx.x;
			cell = hx.y;
		}
		vec2 h0 = hitRipple(vH0, vN);
		vec2 h1 = hitRipple(vH1, vN);
		vec2 h2 = hitRipple(vH2, vN);
		vec2 h3 = hitRipple(vH3, vN);
		float wave = h0.x + h1.x + h2.x + h3.x;
		float spot = h0.y + h1.y + h2.y + h3.y;
		// slow scan band drifting upward, cells twinkling
		float scan = exp(-pow(fract(vN.y * 0.5 + 0.5 - now * 0.004) - 0.5, 2.0) * 60.0) * 0.35;
		float twinkle = step(0.93, fract(cell * 13.7 + floor(now / 9.0) * 0.618)) * 0.35;
		float I = 0.05 + fres * 0.95 + hexE * (0.10 + 0.55 * fres + 1.4 * wave + scan) + energy * 0.10 * (0.3 + fres)
			+ twinkle * (1.0 - hexE) * 0.4 + wave * 0.6 + scan * 0.25;
		rgb = col * I + hotC * (spot * 1.6 + wave * hexE * 0.6 + pow(fres, 3.0) * 0.25);
		a = clamp(I * 0.3 + spot * 0.2, 0.0, 1.0);
	} else {
		// cloak: faint refraction-like shimmer, interference bands and a thin rim
		float fres = pow(1.0 - ndv, 3.0);
		float bands = pow(0.5 + 0.5 * sin(vWorld.y * 0.45 - now * 0.35 + fbm2lo(vN.xz * 3.0 + now * 0.01) * 6.0), 10.0);
		float sparkle = step(0.985, hash12(floor(vN.xz * 40.0) + floor(now / 3.0))) * 0.6;
		float I = fres * 0.55 + bands * 0.18 * (0.3 + fres) + sparkle * fres;
		rgb = col * I + hotC * fres * fres * 0.15;
		a = I * 0.15;
	}
	float k = vEnv * vColor.a * back;
	rgb *= k;
	if (max(rgb.r, max(rgb.g, rgb.b)) < 0.002) discard;
	fragColor = vec4(rgb, clamp(a * k, 0.0, 1.0));
}
