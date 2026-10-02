#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: lightning fragment. Output is premultiplied (blend ONE, ONE_MINUS_SRC_ALPHA):
// rgb = emitted light, a = how much of the background it tints over (keeps colour readable on bright maps).
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
#line 20000

in DataVS {
	vec4 vColor;
	vec2 vUV;
	float vPass;
};

out vec4 fragColor;

void main() {
	float x = vUV.y;
	float I = vColor.a;
	if (I < 0.003) discard;
	if (vPass < 0.5) {
		float g = exp(-x * x * 4.0);
		g = max(g - 0.0183, 0.0) / 0.9817;
		vec3 rgb = vColor.rgb * g * 0.55 * I;
		fragColor = vec4(rgb, clamp(g * 0.2 * I, 0.0, 1.0));
	} else {
		float core = exp(-x * x * 26.0);
		float halo = exp(-x * x * 3.2);
		vec3 hot = mix(vec3(1.0, 0.98, 0.96), vColor.rgb, 0.15);
		vec3 rgb = (vColor.rgb * halo * 1.15 + hot * core * 1.9) * I;
		fragColor = vec4(rgb, clamp(halo * 0.35 * I, 0.0, 1.0));
	}
}
