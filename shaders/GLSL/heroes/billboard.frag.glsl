#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vUV;
	vec4 vColor;
	vec4 vMisc;
};

out vec4 fragColor;

void main() {
	float now = fxNow();
	vec2 uv = vUV.xy;
	float life = vUV.z;
	float kind = vUV.w;
	float seed = vMisc.x;
	float env = vMisc.y;
	float r = length(uv);
	if (r > 1.0) discard;
	float ang = atan(uv.y, uv.x);
	vec3 col = vColor.rgb;
	vec3 hotC = vec3(1.0, 0.97, 0.93);
	vec3 rgb;
	float a;
	float tick = mod(floor(now / 2.0), 1024.0);

	if (kind < 0.5) {
		// ---- flash: white core, turbulent fireball, corona, rays, expanding shock ring
		float I = life < 0.06 ? life / 0.06 : pow(1.0 - (life - 0.06) / 0.94, 1.6);
		float core = exp(-r * r * 38.0);
		float turb = fbm2(uv * 3.2 + vec2(seed, seed * 0.7) + life * 1.5);
		float fire = exp(-r * r * 5.5) * (0.55 + 0.9 * turb);
		float corona = exp(-r * 3.2) * 0.45;
		float rays = pow(max(linNoiseWrap((ang / TAU + 0.5) * 22.0, 22.0, seed + tick), 0.0), 4.0) * exp(-r * 2.2) * (1.2 - life);
		float sr = 0.25 + 0.72 * (1.0 - pow(1.0 - life, 2.0));
		float shock = exp(-pow((r - sr) / 0.035, 2.0)) * (1.0 - life) * 0.9;
		float edge = 1.0 - smoothstep(0.85, 1.0, r);
		rgb = hotC * core * 2.2 + col * (fire + corona) * 1.3 + mix(col, hotC, 0.5) * rays * 1.2 + mix(col, hotC, 0.3) * shock;
		rgb *= I * edge;
		a = clamp((fire * 0.45 + corona * 0.2) * I * edge, 0.0, 1.0);
	} else {
		// ---- orb: swirling plasma ball, bright limb, halo, crackling tendrils
		float pulse = 1.0 + 0.08 * sin(now * 0.25 + seed);
		float br = 0.40 * pulse;
		float rn = r / br;
		float rot = now * 0.035;
		vec2 ruv = mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * uv;
		float plasma = fbm2(ruv * 6.0 / pulse + vec2(seed, now * 0.02));
		float plasma2 = fbm2(uv.yx * 9.0 - vec2(now * 0.03, seed));
		float inBall = 1.0 - smoothstep(0.92, 1.0, rn);
		float limb = pow(clamp(rn, 0.0, 1.0), 4.0);
		float core = exp(-rn * rn * 6.0);
		vec3 ball = mix(col, hotC, 0.35 + 0.4 * plasma) * (0.55 + 0.9 * plasma * plasma2) + hotC * (core * 1.4 + limb * 0.7);
		float halo = exp(-max(rn - 1.0, 0.0) * 2.4) * (1.0 - inBall) * 0.75;
		float outer = exp(-r * 2.6) * 0.35;
		// tendrils: a few jagged arcs from the limb outward, re-rolled every tick
		float tend = 0.0;
		float N = 7.0;
		float xa = (ang / TAU + 0.5) * N;
		float ci = floor(xa);
		float hs = hash12(vec2(ci + seed, tick));
		if (hs < 0.55 && rn > 0.95) {
			float len = mix(1.5, 2.4, hash12(vec2(ci + seed, tick + 7.0)));
			float centre = (ci + 0.5 + (hash12(vec2(ci, tick + 3.0)) - 0.5) * 0.6) / N;
			float jit = linNoise(r * 14.0, ci * 3.7 + tick) * 0.06 + linNoise(r * 37.0, ci + tick * 1.3) * 0.02;
			float da = ((ang / TAU + 0.5) - centre) * TAU * r - jit * (rn - 0.95);
			float th = 0.012 + 0.01 * (1.0 - min((rn - 1.0) / (len - 1.0), 1.0));
			float on = 1.0 - smoothstep(len - 0.25, len, rn);
			tend = exp(-da * da / (th * th)) * on + exp(-abs(da) / 0.05) * on * 0.25;
		}
		rgb = ball * inBall + col * (halo + outer) + mix(col, hotC, 0.6) * tend * 1.3;
		a = clamp(inBall * 0.55 + halo * 0.35 + tend * 0.3, 0.0, 1.0);
		float edge = 1.0 - smoothstep(0.9, 1.0, r);
		rgb *= edge;
		a *= edge;
	}
	float I = env * vColor.a;
	rgb *= I;
	if (max(rgb.r, max(rgb.g, rgb.b)) < 0.003) discard;
	fragColor = vec4(rgb, clamp(a * I, 0.0, 1.0));
}
