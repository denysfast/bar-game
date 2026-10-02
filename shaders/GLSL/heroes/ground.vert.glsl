#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: ground rings / auras. A grid plane per instance whose vertices sample the heightmap,
// so the decal follows the terrain. Attached variant takes its centre from the unit's draw position.
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec2 gridxy;    // -1..1
layout (location = 1) in vec4 i_geo;     // cx, cz, R (half extent), kind
layout (location = 2) in vec4 i_rad;     // r0, r1, width, seed
layout (location = 3) in vec4 i_color;
layout (location = 4) in vec4 i_life;    // start, end, param1, param2
layout (location = 5) in vec4 i_sector;  // arc (0 = full circle), centre angle, rot (rad/s), param3
layout (location = 6) in vec4 i_anim;    // scaleFrom, alphaFrom, animStart, animFrames (smooth set())
#if ATTACHED == 1
layout (location = 7) in uvec4 instData;
#endif

uniform sampler2D heightmapTex;

out DataVS {
	vec4 vLocal;   // local x, z (elmos), kind, envelope
	vec4 vRad;
	vec4 vColor;
	vec4 vLife;
	vec4 vSector;
};

void main() {
	float now = fxNow();
	float start = i_life.x;
	float end = i_life.y;
	float ttl = end - start;
	float env = fxEnvelope(now, start, end, ttl > 1.0e6 ? 12.0 : max(1.0, min(6.0, ttl * 0.08)), ttl > 1.0e6 ? 15.0 : max(2.0, min(ttl * 0.25, 20.0)));
	if (env < 0.002) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
	vec2 c = i_geo.xy;
#if ATTACHED == 1
	c = uni[instData.y].drawPos.xz;
#endif
	float ak = smoothstep(i_anim.z, i_anim.z + max(i_anim.w, 0.001), now);
	float sc = mix(i_anim.x, 1.0, ak);
	float al = mix(i_anim.y, 1.0, ak);
	vec2 local = gridxy * i_geo.z * sc;
	vec3 world;
	world.xz = c + local;
	world.y = textureLod(heightmapTex, heightmapUVatWorldPos(world.xz), 0.0).x + 2.5;
	gl_Position = cameraViewProj * vec4(world, 1.0);
	vLocal = vec4(local / sc, i_geo.w, env);
	vRad = i_rad;
	vColor = vec4(i_color.rgb, i_color.a * al);
	vLife = i_life;
	vSector = i_sector;
}
