#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vA;
	vec4 vColor;
	vec4 vMisc;
	vec2 vQuad;
};

out vec4 fragColor;

void main() {
	float now = fxNow();
	float along = vA.x;
	float across = vA.y;
	float L = vA.z;
	float w = vA.w;
	float seed = vMisc.x;
	float pulse = vMisc.y;
	float fs = vMisc.z;
	float env = vMisc.w;

	float dAx = along < 0.0 ? -along : (along > L ? along - L : 0.0);
	float d = length(vec2(dAx, across));
	float core = exp(-(d * d) / (w * w * 0.16));
	float glow = exp(-(d * d) / (w * w * 1.9));
	float halo = exp(-d / (w * 2.4));

	// energy travelling from the emitter to the target
	float flow = vnoise2(vec2(along * 0.035 - now * 0.55 * pulse, across / w * 0.6 + seed));
	float bands = 0.78 + 0.22 * sin(along * 0.085 - now * 0.95 * pulse) + 0.25 * (flow - 0.5);

	// impact flare + rays
	vec2 ev = vec2(along - L, across);
	float de = length(ev);
	float fr = w * 2.6 * fs;
	float flare = exp(-(de * de) / (fr * fr)) * (1.05 + 0.3 * sin(now * 1.7 + seed));
	float ang = atan(ev.y, ev.x);
	float rays = pow(max(linNoiseWrap((ang / TAU + 0.5) * 18.0, 18.0, seed + mod(floor(now / 2.0), 512.0)), 0.0), 3.0)
		* exp(-de / (w * 3.6 * fs)) * 1.6;
	// emitter glow
	float dm = length(vec2(along, across));
	float muzzle = exp(-(dm * dm) / (w * w * 3.2)) * 0.9;

	vec3 hot = vec3(1.0, 0.97, 0.94);
	vec3 col = vColor.rgb;
	vec3 rgb = hot * core * 1.7 * bands
		+ col * glow * 1.15 * bands
		+ col * halo * 0.4
		+ (hot * 0.6 + col) * (flare + rays)
		+ (hot * 0.5 + col * 0.6) * muzzle;
	float a = glow * 0.5 + halo * 0.14 + flare * 0.35 + rays * 0.15;

	float edge = (1.0 - smoothstep(0.65, 1.0, abs(vQuad.y))) * (1.0 - smoothstep(0.88, 1.0, abs(vQuad.x)));
	float I = env * vColor.a * edge;
	if (I < 0.002) discard;
	fragColor = vec4(rgb * I, clamp(a * I, 0.0, 1.0));
}
