#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
// Hero FX: overlay pass on the unit's own model (rim glow / stone / heat / electric / ice / shadow).
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
//__HEROFX_COMMON__
#line 10000

layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 normal;
layout (location = 2) in vec3 T;
layout (location = 3) in vec3 B;
layout (location = 4) in vec4 uv;
layout (location = 5) in uvec2 bonesInfo;
#define pieceIndex (bonesInfo.x & 0x000000FFu)

layout (location = 6) in vec4 i_color;
layout (location = 7) in vec4 i_par;     // pattern, strength, start, end
layout (location = 8) in vec4 i_anim;    // alphaFrom, animStart, animFrames, seed
layout (location = 9) in uvec4 instData;

#if USEQUATERNIONS == 0
layout(std140, binding = 0) readonly buffer MatrixBuffer {
	mat4 mat[];
};
#else
//__QUATERNIONDEFS__
#endif

out DataVS {
	vec4 vColor;
	vec4 vPar;     // pattern, strength, envelope, seed
	vec3 vModel;
	vec3 vWN;
	vec3 vWorld;
};

void main() {
	float now = fxNow();
	uint baseIndex = instData.x;
#if USEQUATERNIONS == 0
	mat4 modelMatrix = mat[baseIndex];
	mat4 pieceMatrix = mat[baseIndex + pieceIndex + 1u];
	vec4 localPos = pieceMatrix * vec4(pos, 1.0);
	vec4 worldPos = modelMatrix * localPos;
	vec3 wn = mat3(modelMatrix) * mat3(pieceMatrix) * normal;
#else
	Transform pieceTX = GetPieceModelTransform(baseIndex, pieceIndex);
	Transform modelTX = GetModelWorldTransform(baseIndex);
	vec4 localPos = vec4(ApplyTransform(pieceTX, vec4(pos, 1.0)).xyz, 1.0);
	vec4 worldPos = ApplyTransform(modelTX, localPos);
	vec3 wn = RotateByQuaternion(modelTX.quat, RotateByQuaternion(pieceTX.quat, normal));
#endif
	// follow the runtime model scale exactly like the CUS shaders do (scale around the model origin)
	float us = fxUnitScale(instData.y);
#if USEQUATERNIONS == 0
	worldPos = modelMatrix * vec4(localPos.xyz * us, 1.0);
#else
	worldPos = ApplyTransform(modelTX, vec4(localPos.xyz * us, 1.0));
#endif
	float env = fxEnvelope(now, i_par.z, i_par.w, 10.0, 15.0);
	float ak = smoothstep(i_anim.y, i_anim.y + max(i_anim.z, 0.001), now);
	float al = mix(i_anim.x, 1.0, ak);
	if ((uni[instData.y].composite & 0x00000003u) < 1u) env = 0.0;   // not drawn as a model (icon / out of view)
	gl_Position = cameraViewProj * worldPos;
	vColor = vec4(i_color.rgb, i_color.a * al);
	vPar = vec4(i_par.x, i_par.y, env, i_anim.w);
	vModel = localPos.xyz;
	vWN = wn;
	vWorld = worldPos.xyz;
}
