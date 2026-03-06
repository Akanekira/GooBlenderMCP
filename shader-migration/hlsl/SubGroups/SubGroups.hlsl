// =============================================================================
// SubGroups.hlsl
// 所有子群组函数集合（单文件，避免多 include）
// 溯源：docs/analysis/sub_groups/
// =============================================================================

#ifndef PBRTOONBASE_SUBGROUPS_INCLUDED
#define PBRTOONBASE_SUBGROUPS_INCLUDED

// -----------------------------------------------------------------------------
// SigmoidSharp
// 可控 Sigmoid 曲线，用于 Toon 阴影边缘锐化
// 溯源：sub_groups/SigmoidSharp.md
// 节点实现：运算.003(×-3) → 运算.005(×sharp·(x-c)) → 运算.002(pow 100000) → 运算.006(+1) → 运算.007(÷)
// 底数 100000（非 e），陡峭度 ≈ e^34.54，适合 Toon 阶段感边缘
// -----------------------------------------------------------------------------
float SigmoidSharp(float x, float center, float sharp)
{
    float t = -3.0 * sharp * (x - center);
    return 1.0 / (1.0 + pow(100000.0, t));
}

// -----------------------------------------------------------------------------
// SmoothStep（自定义，与 HLSL 内置 smoothstep 等价）
// 溯源：sub_groups/SmoothStep.md
// -----------------------------------------------------------------------------
float SmoothStepCustom(float minVal, float maxVal, float x)
{
    float t = saturate((x - minVal) / (maxVal - minVal));
    return t * t * (3.0 - 2.0 * t);
}

// -----------------------------------------------------------------------------
// PerceptualSmoothnessToPerceptualRoughness
// 溯源：sub_groups/PerceptualSmoothnessToPerceptualRoughness.md
// -----------------------------------------------------------------------------
float PerceptualSmoothnessToPerceptualRoughness(float smoothness)
{
    return 1.0 - smoothness;
}

// -----------------------------------------------------------------------------
// PerceptualRoughnessToRoughness
// 溯源：sub_groups/PerceptualRoughnessToRoughness.md
// -----------------------------------------------------------------------------
float PerceptualRoughnessToRoughness(float perceptualRoughness)
{
    return perceptualRoughness * perceptualRoughness;
}

// -----------------------------------------------------------------------------
// ComputeDiffuseColor
// 溯源：sub_groups/ComputeDiffuseColor.md
// -----------------------------------------------------------------------------
float3 ComputeDiffuseColor(float3 albedo, float metallic)
{
    return albedo * (1.0 - metallic);
}

// -----------------------------------------------------------------------------
// ComputeFresnel0
// 溯源：sub_groups/ComputeFresnel0.md
// -----------------------------------------------------------------------------
float3 ComputeFresnel0(float3 baseColor, float metallic, float3 dielectricF0)
{
    return lerp(dielectricF0, baseColor, metallic);
}

// -----------------------------------------------------------------------------
// DecodeNormal
// 从切线空间 XY 重建 Z，转换到世界空间
// 溯源：sub_groups/DecodeNormal.md
// -----------------------------------------------------------------------------
float3 DecodeNormal(float X, float Y, float normalStrength, float3x3 TBN)
{
    float z = sqrt(max(0.0, 1.0 - X * X - Y * Y));
    float3 normalTS = float3(X, Y, z);
    // 应用法线强度（与 float3(0,0,1) 插值）
    normalTS = lerp(float3(0, 0, 1), normalTS, normalStrength);
    normalTS = normalize(normalTS);
    // 切线空间 → 世界空间
    return normalize(mul(normalTS, TBN));
}

// -----------------------------------------------------------------------------
// DirectionalLightAttenuation
// 平行光方向衰减（背光面保留量控制）
// 溯源：sub_groups/DirectionalLightAttenuation.md
// -----------------------------------------------------------------------------
float DirectionalLightAttenuation(float NoL_unsaturate, float attenuationAdjust)
{
    float clamped = saturate(NoL_unsaturate);
    return lerp(attenuationAdjust, 1.0, clamped);
}

// -----------------------------------------------------------------------------
// FresnelAttenuation
// Rim 用简化 Fresnel 衰减，(1-NoV)^4
// 溯源：sub_groups/FresnelAttenuation.md
// -----------------------------------------------------------------------------
float FresnelAttenuation(float NoV)
{
    float t = 1.0 - NoV;
    float t2 = t * t;
    return t2 * t2; // (1-NoV)^4
}

// -----------------------------------------------------------------------------
// VerticalAttenuation
// 法线垂直分量衰减（顶部 Rim 强，底部弱）
// 溯源：sub_groups/VerticalAttenuation.md
// -----------------------------------------------------------------------------
float VerticalAttenuation(float3 normalWS)
{
    // Blender Z_up → Unity Y_up
    return saturate(normalWS.y);
}

// -----------------------------------------------------------------------------
// F_Schlick
// Schlick Fresnel 近似
// 溯源：sub_groups/F_Schlick.md
// -----------------------------------------------------------------------------
float3 F_Schlick(float3 f0, float3 f90, float u)
{
    float t  = 1.0 - u;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (f90 - f0) * t5;
}

// -----------------------------------------------------------------------------
// Get_NoH_LoH_ToH_BoH
// 从已知点积推导半角向量各点积（避免显式重建 H）
// 溯源：sub_groups/Get_NoH_LoH_ToH_BoH.md
// -----------------------------------------------------------------------------
void Get_NoH_LoH_ToH_BoH(
    float NoL, float NoV, float LoV,
    float ToV, float ToL, float BoV, float BoL,
    out float NdotH, out float LdotH, out float TdotH, out float BdotH)
{
    float invLenLV = rsqrt(max(2.0 * (1.0 + LoV), 1e-7));
    NdotH = saturate((NoL + NoV) * invLenLV);
    LdotH = saturate((LoV + 1.0) * invLenLV);
    TdotH = saturate((ToL + ToV) * invLenLV);
    BdotH = saturate((BoL + BoV) * invLenLV);
}

// -----------------------------------------------------------------------------
// DV_SmithJointGGX_Aniso（伪代码）
// 各向异性 GGX NDF × Smith Joint Visibility 项
// 溯源：sub_groups/DV_SmithJointGGX_Aniso.md
// -----------------------------------------------------------------------------
void DV_SmithJointGGX_Aniso(
    float NdotH, float NdotL, float NdotV, float clampedRoughness,
    float TdotH, float BdotH, float TdotL, float BdotL,
    float TdotV, float BdotV, float roughnessT, float roughnessB,
    out float dvIsotropic, out float dvAnisotropic)
{
    // --- 各向同性分支 ---
    // D_GGX(NdotH, roughness)
    float a2 = clampedRoughness * clampedRoughness;
    float d  = (NdotH * a2 - NdotH) * NdotH + 1.0;
    float D_iso = a2 / (PI * d * d + 1e-7);

    // V_SmithJointGGX(NdotL, NdotV, roughness)
    float lambdaV = NdotL * sqrt((-NdotV * clampedRoughness + NdotV) * NdotV + clampedRoughness);
    float lambdaL = NdotV * sqrt((-NdotL * clampedRoughness + NdotL) * NdotL + clampedRoughness);
    float V_iso = 0.5 / (lambdaV + lambdaL + 1e-7);

    dvIsotropic = D_iso * V_iso;

    // --- 各向异性分支 ---
    // D_GGXAniso(NdotH, TdotH, BdotH, roughnessT, roughnessB)
    float f = TdotH * TdotH / (roughnessT * roughnessT)
            + BdotH * BdotH / (roughnessB * roughnessB)
            + NdotH * NdotH;
    float D_aniso = 1.0 / (PI * roughnessT * roughnessB * f * f + 1e-7);

    // V_SmithJointGGXAniso
    float lambdaV_a = NdotL * length(float3(roughnessT * TdotV, roughnessB * BdotV, NdotV));
    float lambdaL_a = NdotV * length(float3(roughnessT * TdotL, roughnessB * BdotL, NdotL));
    float V_aniso = 0.5 / (lambdaV_a + lambdaL_a + 1e-7);

    dvAnisotropic = D_aniso * V_aniso;
}

// -----------------------------------------------------------------------------
// GetPreIntegratedFGD（伪代码）
// 采样预积分 FGD LUT
// 溯源：sub_groups/GetPreIntegratedFGDGGXAndDisneyDiffuse.md
// -----------------------------------------------------------------------------
void GetPreIntegratedFGD(
    float NdotV, float perceptualRoughness, float3 fresnel0,
    out float3 specularFGD, out float diffuseFGD, out float reflectivity)
{
    // 半纹素偏移避免边缘采样错误
    float2 uv = float2(NdotV, perceptualRoughness);
    uv = uv * (1.0 - 1.0 / 512.0) + 0.5 / 512.0;

    float4 s = SAMPLE_TEXTURE2D_LOD(_FGD_LUT, sampler_FGD_LUT, uv, 0);
    // s.x = FGD_a, s.y = FGD_b, s.z = DisneyDiffuse FGD
    specularFGD = fresnel0 * s.x + s.y;
    diffuseFGD  = s.z;
    reflectivity = s.x + s.y;
}

// -----------------------------------------------------------------------------
// RampSelect（伪代码）
// 根据 RampIndex 选择并采样 Toon 阴影色带
// 溯源：sub_groups/RampSelect.md
// 建议：将 5 条 Ramp 合并为 5×N 的竖向 LUT
// -----------------------------------------------------------------------------
void RampSelect(float rampUV, float rampIndex,
                out float3 rampColor, out float rampAlpha)
{
    // rampIndex [0,4] → LUT V 坐标
    float v = (rampIndex + 0.5) / 5.0;
    float4 s = SAMPLE_TEXTURE2D(_RampLUT, sampler_RampLUT, float2(rampUV, v));
    rampColor = s.rgb;
    rampAlpha = s.a;
}

// -----------------------------------------------------------------------------
// directLighting_diffuse
// 直接光漫反射合并阴影 + 遮蔽 + 漫反射色 + 光方向
// 溯源：sub_groups/directLighting_diffuse.md
// -----------------------------------------------------------------------------
float3 DirectLightingDiffuse(
    float3 shadowRampColor, float3 directOcclusion,
    float3 diffuseColor,    float3 lightFactor)
{
    return shadowRampColor * diffuseColor * lightFactor * directOcclusion;
}

// -----------------------------------------------------------------------------
// DeSaturation
// 暗部去饱和（卡通压色）
// 溯源：sub_groups/DeSaturation.md
// -----------------------------------------------------------------------------
float3 DeSaturation(float factor, float3 color)
{
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722)); // Rec.709
    return lerp(color, luma.xxx, factor);
}

// -----------------------------------------------------------------------------
// DepthRim（简化）
// 屏幕空间深度差边缘检测
// 溯源：sub_groups/DepthRim.md
// 注：完整实现需 ScreenspaceInfo；此处展示 URP 深度图采样思路
// -----------------------------------------------------------------------------
float DepthRim(float2 screenUV, float3 normalVS,
               float rimWidthX, float rimWidthY)
{
    // 法线偏移采样坐标
    float2 offset   = float2(normalVS.x * rimWidthX, normalVS.y * rimWidthY);
    float2 offsetUV = screenUV + offset * 0.01; // 缩放系数待调整

    // 采样深度（URP _CameraDepthTexture）
    float depthCenter = SAMPLE_TEXTURE2D(_CameraDepthTexture,
                            sampler_CameraDepthTexture, screenUV).r;
    float depthOffset = SAMPLE_TEXTURE2D(_CameraDepthTexture,
                            sampler_CameraDepthTexture, offsetUV).r;

    // 线性化并求差（伪代码，实际需 LinearEyeDepth）
    float diff = LinearEyeDepth(depthOffset) - LinearEyeDepth(depthCenter);

    return saturate(diff * 10.0); // 灵敏度系数待调整
}

// -----------------------------------------------------------------------------
// Rim_Color
// Rim 颜色合成（albedo + 平行光 + Rim 颜色参数 + LoV 调制）
// 溯源：sub_groups/Rim_Color.md
// -----------------------------------------------------------------------------
float3 RimColor(
    float3 albedo, float3 dirLightColor,
    float3 rimColor, float rimColorStrength, float LoV)
{
    // LoV 映射：光从正面照射时降低 Rim
    float loVFactor = saturate(LoV * 0.5 + 0.5);

    // Rim 颜色与平行光混合
    float3 blended = lerp(rimColor, dirLightColor * rimColor, loVFactor);

    // 带上 albedo 染色
    blended = lerp(blended, albedo * blended, 0.5);

    return blended * rimColorStrength;
}

#endif // PBRTOONBASE_SUBGROUPS_INCLUDED
