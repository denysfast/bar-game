#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vColor;
	vec4 vT;
};

out vec4 fragColor;

void main() {
	float now = fxNow();
	float x = vT.x;
	float age = vT.y;
	float fade = pow(1.0 - clamp(age, 0.0, 1.0), 1.6);
	float core = exp(-x * x * 16.0);
	float glow = exp(-x * x * 2.5) - exp(-2.5);
	float flow = 0.75 + 0.5 * vnoise2(vec2(vT.z * 0.03 + now * 0.2, x * 1.5 + vT.w));
	vec3 rgb = (vColor.rgb * glow * 0.9 * flow + vec3(1.0, 0.97, 0.94) * core * (1.0 - age) * 0.9) * fade * vColor.a;
	if (max(rgb.r, max(rgb.g, rgb.b)) < 0.003) discard;
	fragColor = vec4(rgb, clamp(glow * 0.3 * fade * vColor.a, 0.0, 1.0));
}
