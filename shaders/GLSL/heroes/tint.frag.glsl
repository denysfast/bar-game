#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// patterns: 0 rim, 1 stone, 2 heat, 3 electric, 4 ice, 5 shadow
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vColor;
	vec4 vPar;
	vec3 vModel;
	vec3 vWN;
	vec3 vWorld;
};

out vec4 fragColor;

float tri(vec3 p) {
	return (fbm2(p.xy) + fbm2(p.yz + 3.1) + fbm2(p.zx + 7.7)) / 3.0;
}

void main() {
	float now = fxNow();
	float env = vPar.z;
	if (env < 0.003) discard;
	float pattern = vPar.x;
	float strength = vPar.y;
	float seed = vPar.w;
	vec3 n = normalize(vWN);
	vec3 v = normalize(cameraViewInv[3].xyz - vWorld);
	float ndv = abs(dot(n, v));
	float fres = pow(1.0 - ndv, 2.5);
	vec3 col = vColor.rgb;
	vec3 rgb;
	float a;
	if (pattern < 0.5) {
		float pulse = 0.85 + 0.15 * sin(now * 0.2 + seed);
		rgb = col * (0.22 + fres * 1.3) * pulse;
		a = 0.12 + fres * 0.25;
	} else if (pattern < 1.5) {
		float nz = tri(vModel * 0.12 + seed);
		float cr = tri(vModel * 0.05 + seed + 11.0);
		float crack = 1.0 - smoothstep(0.0, 0.025, abs(cr - 0.5));
		vec3 grey = col * (0.55 + 0.6 * nz);
		rgb = grey * (1.0 - crack * 0.75) * 0.75 + vec3(0.05) * fres;
		a = 0.88;
	} else if (pattern < 2.5) {
		float nz = fbm2(vModel.xz * 0.07 + vec2(vModel.y * 0.05 - now * 0.02, seed));
		float glow = smoothstep(0.35, 0.9, nz) * (0.75 + 0.25 * sin(now * 0.25 + seed));
		rgb = col * (0.25 + glow * 1.3 + fres * 0.9) + vec3(1.0, 0.85, 0.5) * glow * glow * 0.5;
		a = 0.3 + glow * 0.2;
	} else if (pattern < 3.5) {
		float tick = floor(now / 2.0);
		float nz = tri(vModel * 0.06 + vec3(0.0, 0.0, mod(tick, 512.0) * 0.37) + seed);
		float e = clamp(1.0 - abs(nz - 0.5) * 22.0, 0.0, 1.0);
		e = pow(e, 3.0);
		rgb = mix(col, vec3(1.0), e * 0.6) * (e * 1.8 + fres * 0.6 + 0.08);
		a = e * 0.35 + fres * 0.1;
	} else if (pattern < 4.5) {
		float nz = tri(vModel * 0.2 + seed);
		float sparkle = step(0.97, hash12(floor(vModel.xz * 0.8) + floor(now / 6.0)));
		rgb = col * (0.35 + 0.35 * nz + fres * 1.1) + vec3(1.0) * sparkle * 0.8;
		a = 0.5;
	} else {
		float nz = tri(vModel * 0.08 + vec3(now * 0.01) + seed);
		rgb = col * (fres * 1.2 + nz * 0.15);
		a = 0.55 + nz * 0.2;
	}
	float k = env * vColor.a * strength;
	fragColor = vec4(rgb * k, clamp(a * k, 0.0, 1.0));
}
