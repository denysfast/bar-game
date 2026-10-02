#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: glowing ribbon trail; one camera-facing quad per history segment.
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec4 quad;      // x: -1 = p0 end, 1 = p1 end; y: across
layout (location = 1) in vec4 i_p0w;     // p0, width
layout (location = 2) in vec4 i_p1a;     // p1, age at p0 (0 = newest, 1 = oldest)
layout (location = 3) in vec4 i_color;
layout (location = 4) in vec4 i_par;     // age at p1, intensity, seed, distance along trail at p0

out DataVS {
	vec4 vColor;
	vec4 vT;       // across, age, along distance, seed
};

void main() {
	float t = quad.x * 0.5 + 0.5;
	vec3 p0 = i_p0w.xyz;
	vec3 p1 = i_p1a.xyz;
	vec3 p = mix(p0, p1, t);
	float age = mix(i_p1a.w, i_par.x, t);
	vec3 dir = p1 - p0;
	float L = length(dir);
	if (L < 0.01) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
	dir /= L;
	vec3 camPos = cameraViewInv[3].xyz;
	vec3 toCam = normalize(camPos - p);
	vec3 right = cross(dir, toCam);
	float rl = length(right);
	right = rl > 0.05 ? right / rl : normalize(cross(dir, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	float w = i_p0w.w * mix(1.0, 0.25, age);
	float minW = length(camPos - p) * 0.0015;
	float cover = clamp(w / max(minW, 0.001), 0.3, 1.0);
	w = max(w, minW);
	gl_Position = cameraViewProj * vec4(p + right * quad.y * w, 1.0);
	vColor = vec4(i_color.rgb, i_color.a * i_par.y * cover);
	vT = vec4(quad.y, age, i_par.w + t * L, i_par.z);
}
