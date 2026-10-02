#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 20000

in DataVS {
	vec4 vP;
	vec4 vColor;
	vec3 vNormal;
	vec3 vWorld;
	float vPass;
};

out vec4 fragColor;

void main() {
	float now = fxNow();
	float y01 = vP.x;
	float a01 = vP.y;
	float life = vP.z;
	float env = vP.w;
	vec3 camPos = cameraViewInv[3].xyz;
	vec3 v = camPos - vWorld;
	// horizontal chord through a glowing cylinder ~ |n.v| in the horizontal plane
	vec2 vh = normalize(v.xz + vec2(0.0001));
	float ndv = abs(dot(normalize(vNormal.xz + vec2(0.0001)), vh));
	float vert = smoothstep(0.0, 0.04, y01) * (1.0 - smoothstep(0.55, 1.0, y01));
	float base = exp(-y01 * 9.0);
	float streak = fbm2(vec2(a01 * 9.0, y01 * 6.0 - now * 0.06));
	float spiral = 0.75 + 0.25 * sin(a01 * TAU * 2.0 + y01 * 18.0 - now * 0.35);
	vec3 hotC = vec3(1.0, 0.97, 0.92);
	vec3 rgb;
	float a;
	if (vPass < 0.5) {
		float sharp = smoothstep(0.35, 0.75, streak);
		float I = pow(ndv, 1.4) * vert * (0.25 + 0.95 * sharp) * spiral + base * pow(ndv, 0.8) * 0.6;
		rgb = vColor.rgb * I * 0.75 + hotC * base * ndv * 0.25;
		a = I * 0.35;
	} else {
		float I = pow(ndv, 3.0) * vert * (0.6 + 0.5 * streak) + base * 0.4;
		rgb = mix(hotC, vColor.rgb, 0.35) * I * 0.9;
		a = I * 0.1;
	}
	float k = env * vColor.a * (1.0 - life * 0.35);
	rgb *= k;
	if (max(rgb.r, max(rgb.g, rgb.b)) < 0.003) discard;
	fragColor = vec4(rgb, clamp(a * k, 0.0, 1.0));
}
