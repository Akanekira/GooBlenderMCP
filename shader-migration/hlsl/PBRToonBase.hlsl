// =============================================================================
// PBRToonBase.hlsl
// 主 Shader 函数 — 按 Frame 顺序组装所有模块
// 溯源：docs/analysis/01_shader_arch.md
// 注：本文件为伪代码级 HLSL，供理解渲染流程使用，非可直接编译版本
// =============================================================================

#ifndef PBRTOONBASE_MAIN_INCLUDED
#define PBRTOONBASE_MAIN_INCLUDED

#include "PBRToonBase_Input.hlsl"
#include "SubGroups/SubGroups.hlsl"

#ifndef PI
#define PI 3.14159265358979323846
#endif

// =============================================================================
// Frame.013 — GetSurfaceData（贴图采样 + 表面参数计算）
// 溯源：docs/analysis/01_shader_arch.md#frame013
// =============================================================================
SurfaceData GetSurfaceData(Varyings input)
{
    SurfaceData s;

    // --- 框.001 albedo ---
    float4 dTex   = SAMPLE_TEXTURE2D(_D, sampler_D, input.uv);
    s.albedo       = dTex.rgb;
    s.alpha        = dTex.a;

    // --- 法线贴图（框.002 N）---
    // DecodeNormal 在 InitLightingData 中使用，此处仅采样 XY
    float4 nTex    = SAMPLE_TEXTURE2D(_N, sampler_N, input.uv);
    // nTex.xy 存储切线空间法线 XY，后续由 DecodeNormal 重建

    // --- 参数贴图拆通道 ---
    float4 pTex    = SAMPLE_TEXTURE2D(_P, sampler_P, input.uv);
    float  metallic_raw    = pTex.r;    // 框.006 P_R
    float  ao_raw          = pTex.g;    // 框.007 P_G（directOcclusion）
    float  smoothness_raw  = pTex.b;    // 框.008 P_B
    s.rampUV               = pTex.a;    // 框.009 P_A

    // --- 框.012 metallic / 框.049 AO ---
    s.metallic  = metallic_raw  * _MetallicMax;
    s.ao        = ao_raw;               // directOcclusion（AO 额外叠加逻辑由节点决定）

    // --- 框.008 Smoothness → perceptualRoughness → roughness ---
    s.smoothness            = smoothness_raw * _SmoothnessMax;
    s.perceptualRoughness   = PerceptualSmoothnessToPerceptualRoughness(s.smoothness);
    s.roughness             = PerceptualRoughnessToRoughness(s.perceptualRoughness);

    // --- 各向异性 T 轴（框.060~062）---
    float smoothnessT             = smoothness_raw * _Aniso_SmoothnessMaxT;
    s.perceptualRoughnessT        = PerceptualSmoothnessToPerceptualRoughness(smoothnessT);
    s.roughnessT                  = PerceptualRoughnessToRoughness(s.perceptualRoughnessT);

    // --- 各向异性 B 轴（框.063~065）---
    float smoothnessB             = smoothness_raw * _Aniso_SmoothnessMaxB;
    s.perceptualRoughnessB        = PerceptualSmoothnessToPerceptualRoughness(smoothnessB);
    s.roughnessB                  = PerceptualRoughnessToRoughness(s.perceptualRoughnessB);

    // --- 框.031 diffuseColor / 框.013 fresnel0 ---
    s.diffuseColor  = ComputeDiffuseColor(s.albedo, s.metallic);
    s.fresnel0      = ComputeFresnel0(s.albedo, s.metallic, float3(0.04, 0.04, 0.04));

    // --- 自发光 ---
    s.emission = SAMPLE_TEXTURE2D(_E, sampler_E, input.uv).rgb;

    // 切线空间法线（decoded 后赋值，DecodeNormal 在 InitLightingData 内调用）
    s.normalTS = float3(nTex.xy, 0); // 占位，实际 Z 在 DecodeNormal 中重建

    return s;
}

// =============================================================================
// Frame.012 — Init（几何向量初始化）
// 溯源：docs/analysis/01_shader_arch.md#frame012
// =============================================================================
LightingData InitLightingData(Varyings input, SurfaceData sd)
{
    LightingData ld;

    // --- TBN 矩阵 ---
    float3 N_geo = normalize(input.normalWS);
    float3 T_geo = normalize(input.tangentWS);
    float3 B_geo = normalize(input.bitangentWS);
    float3x3 TBN = float3x3(T_geo, B_geo, N_geo);

    // --- 框.002 N：法线（DecodeNormal 解码切线空间 XY → 世界空间）---
    float4 nTex = SAMPLE_TEXTURE2D(_N, sampler_N, input.uv); // 再次采样以拿到 XY
    ld.N = (_UseNormalTex > 0.5)
         ? DecodeNormal(nTex.x, nTex.y, _NormalStrength, TBN)
         : N_geo;

    // --- 框.003 V：视角方向（Incoming 取反）---
    ld.V = normalize(-GetWorldSpaceViewDir(input.positionWS)); // 伪代码：需 URP GetWorldSpaceViewDir

    // --- 框.020 L：主光方向（SHADERINFO → URP MainLight）---
    Light mainLight = GetMainLight(); // URP 内置
    ld.L = normalize(mainLight.direction);
    ld.lightColor   = mainLight.color * mainLight.distanceAttenuation;
    ld.castShadow   = mainLight.shadowAttenuation; // 投影阴影值

    // --- 框.022 T / 框.055 B ---
    ld.T = T_geo;
    ld.B = B_geo;

    // --- 基础点积 ---
    ld.NoV = saturate(dot(ld.N, ld.V));
    ld.NoL = dot(ld.N, ld.L);           // Unsaturated，允许负值
    ld.LoV = dot(ld.L, ld.V);

    // --- 各向异性点积（框.056~059）---
    ld.ToL  = dot(ld.T, ld.L);
    ld.BdotL = dot(ld.B, ld.L);
    ld.ToV  = dot(ld.T, ld.V);
    ld.BdotV = dot(ld.B, ld.V);

    // --- 框.023~025 半角点积（Get_NoH_LoH_ToH_BoH）---
    Get_NoH_LoH_ToH_BoH(
        ld.NoL, ld.NoV, ld.LoV,
        ld.ToV, ld.ToL, ld.BdotV, ld.BdotL,
        ld.NdotH, ld.LdotH, ld.TdotH, ld.BdotH);

    return ld;
}

// =============================================================================
// 主片元函数（Fragment Shader）
// 按 Frame 顺序逐步组装最终颜色
// =============================================================================
float4 PBRToonBase_Frag(Varyings input) : SV_Target
{
    // -------------------------------------------------------------------------
    // Frame.013 + Frame.012 — 表面数据 + 光照初始化
    // -------------------------------------------------------------------------
    SurfaceData  sd = GetSurfaceData(input);
    LightingData ld = InitLightingData(input, sd);

    // -------------------------------------------------------------------------
    // Frame.005 — DiffuseBRDF（Toon 漫反射）
    // 溯源：docs/analysis/01_shader_arch.md#frame005
    // -------------------------------------------------------------------------

    // 框.014 RemaphalfLambert：halfLambert 重映射 + Sigmoid 锐化
    float halfLambert = SigmoidSharp(ld.NoL,
                                     _RemaphalfLambert_center,
                                     _RemaphalfLambert_sharp);

    // 框.018 shadowArea：搭配 castShadow 形成最终阴影区域
    // CastShadow_center/sharp 控制阴影过渡边缘
    float shadowFactor = SigmoidSharp(halfLambert * ld.castShadow,
                                      _CastShadow_center,
                                      _CastShadow_sharp);

    // 框.032 shadowRampColor：Toon Ramp 采样
    float3 shadowRampColor;
    float  shadowRampAlpha;
    RampSelect(sd.rampUV, _RampIndex, shadowRampColor, shadowRampAlpha);
    // 混合明暗（伪代码：shadowFactor 驱动 Ramp UV 的 U 坐标）
    float rampU     = shadowFactor; // Ramp U = shadow factor
    float3 rampCurrent; float rampA;
    RampSelect(rampU, _RampIndex, rampCurrent, rampA);

    // 框.033 directLighting_diffuse：直接光漫反射
    float3 directOcclusion = lerp(_directOcclusionColor.rgb, 1.0, sd.ao);
    float3 lightFactor      = ld.lightColor * _dirLight_lightColor.rgb;
    float3 diffuseDirect    = DirectLightingDiffuse(rampCurrent, directOcclusion,
                                                    sd.diffuseColor, lightFactor);

    // DeSaturation：暗部去饱和（卡通压色），作用于阴影区域
    float desat = _ColorDesaturationAttenuation * (1.0 - shadowFactor);
    diffuseDirect = DeSaturation(desat, diffuseDirect);

    // -------------------------------------------------------------------------
    // Frame.004 — SpecularBRDF（各向异性 GGX 高光）
    // 溯源：docs/analysis/01_shader_arch.md#frame004
    // -------------------------------------------------------------------------
    float clampedRoughness = max(sd.roughness, 0.001);
    float absNdotL = saturate(ld.NoL);

    // 框.026 DV / 框.065 AnisoDV
    float dvIsotropic, dvAnisotropic;
    DV_SmithJointGGX_Aniso(
        ld.NdotH, absNdotL, ld.NoV, clampedRoughness,
        ld.TdotH, ld.BdotH, ld.ToL, ld.BdotL,
        ld.ToV, ld.BdotV, sd.roughnessT, sd.roughnessB,
        dvIsotropic, dvAnisotropic);

    // 框.068 ToonAniso：等向/各向异性混合（Use anisotropy? 开关）
    float dv = (_UseAnisotropy > 0.5) ? dvAnisotropic : dvIsotropic;
    // ToonAniso 开关进一步选择使用 Toon 化的各向异性
    dv = (_UseToonAniso > 0.5) ? dvAnisotropic : dv;

    // 框.027 F：Schlick Fresnel
    float3 F = F_Schlick(sd.fresnel0, float3(1, 1, 1), ld.LdotH);

    // 框.028 specTerm：高光项
    float3 specularTerm  = F * dv * absNdotL * PI;
    float3 specularColor = specularTerm * _SpecularColor.rgb * ld.lightColor;

    // -------------------------------------------------------------------------
    // Frame.006 — IndirectLighting（间接光照）
    // 溯源：docs/analysis/01_shader_arch.md#frame006
    // -------------------------------------------------------------------------
    float3 specularFGD;
    float  diffuseFGD, reflectivity;
    GetPreIntegratedFGD(ld.NoV, sd.perceptualRoughness, sd.fresnel0,
                        specularFGD, diffuseFGD, reflectivity);

    // 框.035 energyCompensation（能量守恒补偿）
    float3 energyCompensation = 1.0 - reflectivity;

    // 框.036 indirectDiffuse
    float3 indirectDiffuse = sd.diffuseColor * diffuseFGD
                           * _AmbientLightColorTint.rgb;

    // 框.038 indirectSpecular（概念性：需反射探针/SkyBox，此处简化）
    float3 indirectSpecular = specularFGD * _specularFGDStrength;

    // -------------------------------------------------------------------------
    // Frame.007 — ShadowAdjust（全局阴影亮度调整）
    // 溯源：docs/analysis/01_shader_arch.md#frame007
    // -------------------------------------------------------------------------
    // SmoothStep 作用于漫反射的阴影区亮度
    float shadowAdj = SmoothStepCustom(0.0, 1.0, _GlobalShadowBrightnessAdjustment);
    diffuseDirect  *= lerp(shadowAdj, 1.0, shadowFactor);

    // 组合直接光照
    float3 color = diffuseDirect + specularColor + indirectDiffuse + indirectSpecular;

    // -------------------------------------------------------------------------
    // Frame.008 — ToonFresnel（Toon 风格边缘色叠加）
    // 溯源：docs/analysis/01_shader_arch.md#frame008
    // -------------------------------------------------------------------------
    // LayerWeight Fresnel 因子（基于 NoV，模拟 Blender 的 LAYER_WEIGHT 节点）
    float toonFresnelFactor = pow(1.0 - ld.NoV, _ToonfresnelPow);
    toonFresnelFactor = SmoothStepCustom(_ToonfresnelSMO_L, _ToonfresnelSMO_H,
                                         toonFresnelFactor);

    // LayerWeight Value + Offset 控制混合强度
    float layerWeight = saturate(toonFresnelFactor * _LayerWeightValue + _LayerWeightValueOffset);

    // 内/外颜色混合
    float3 toonFresnelColor = lerp(_fresnelInsideColor.rgb, _fresnelOutsideColor.rgb, layerWeight);
    color += toonFresnelColor * layerWeight;

    // -------------------------------------------------------------------------
    // Frame.009 — Rim（屏幕空间深度边缘光）
    // 溯源：docs/analysis/01_shader_arch.md#frame009
    // -------------------------------------------------------------------------
    // 屏幕空间 UV
    float2 screenUV = input.screenPos.xy / input.screenPos.w;

    // 法线视空间分量（近似：使用世界空间法线 XY 作为偏移方向）
    float3 normalVS = float3(ld.N.x, ld.N.y, 0); // 概念性转换

    // 框.041 DepthRim：深度差遮罩
    float rimDepthMask = DepthRim(screenUV, normalVS, _Rim_width_X, _Rim_width_Y);

    // 框.042 FresnelAttenuation：Fresnel 遮罩
    float rimFresnelMask = FresnelAttenuation(ld.NoV);

    // 框.043 VerticalAttenuation：法线垂直遮罩
    float rimVerticalMask = VerticalAttenuation(ld.N);

    // 三路遮罩相乘
    float rimMask = rimDepthMask * rimFresnelMask * rimVerticalMask;

    // 框.045 DirectionalLightAttenuation：光源方向调制
    float rimDirAtten = DirectionalLightAttenuation(ld.NoL, _Rim_DirLightAtten);

    // 框.046 Rim_Color：Rim 颜色合成
    float3 rimFinalColor = RimColor(sd.albedo, ld.lightColor,
                                    _Rim_Color.rgb, _Rim_ColorStrength, ld.LoV);

    // 框.047 Rim：最终 Rim 叠加
    color += rimFinalColor * rimMask * rimDirAtten;

    // -------------------------------------------------------------------------
    // Frame.010 — Emission（自发光叠加）
    // 溯源：docs/analysis/01_shader_arch.md#frame010
    // -------------------------------------------------------------------------
    // _E.RGB 以 ADD 模式叠加（框.051）
    color += sd.emission;

    // -------------------------------------------------------------------------
    // RS Effect（框.048）— 特效叠加（RSModel/RS_Eff 开关控制）
    // 溯源：docs/analysis/01_shader_arch.md#frame048
    // -------------------------------------------------------------------------
    if (_UseRSEff > 0.5)
    {
        // RS_Index 选择效果类型，RS_Strength 控制强度
        // RS_MultiplyValue 乘法混合，RS_ColorTint 染色
        // 具体实现为两级 MIX，此处简化为颜色叠加
        float3 rsColor = _RS_ColorTint.rgb * _RS_MultiplyValue * _RS_Strength;
        color += rsColor;
    }

    // -------------------------------------------------------------------------
    // Frame.011 — ThinFilmFilter（薄膜/彩虹光视角色变）
    // 溯源：docs/analysis/01_shader_arch.md#frame011
    // -------------------------------------------------------------------------
    // LAYER_WEIGHT Fresnel 因子 → 驱动 LUT 采样
    float thinFilmFresnel = saturate(1.0 - ld.NoV); // 视角相关

    // 采样 ThinFilm 彩虹 LUT（U = Fresnel 因子，V = 0.5 固定）
    float3 thinFilmColor = SAMPLE_TEXTURE2D(_ThinFilmLUT, sampler_ThinFilmLUT,
                               float2(thinFilmFresnel, 0.5)).rgb;

    // 内/外颜色混合 + RS ColorTint 染色
    thinFilmColor = lerp(_fresnelInsideColor.rgb, thinFilmColor, thinFilmFresnel);
    thinFilmColor *= _RS_ColorTint.rgb;

    // 叠加（强度由 LayerWeight 控制）
    color += thinFilmColor * thinFilmFresnel * _RS_Strength;

    // -------------------------------------------------------------------------
    // Simple Transmission（框.069）— 简化透射（概念性）
    // 溯源：docs/analysis/01_shader_arch.md#frame069
    // 注：依赖 Goo Engine SCREENSPACEINFO，Unity URP 可简化为背向光方向透射
    // -------------------------------------------------------------------------
    if (_UseSimpleTransmission > 0.5)
    {
        // 概念：背光面 NoL 的绝对值 × 透射强度 → 叠加次表面散射感
        float transmissionFactor = saturate(-ld.NoL) * _SimpleTransmissionValue;
        color += sd.albedo * ld.lightColor * transmissionFactor;
    }

    // -------------------------------------------------------------------------
    // Frame.014 — Alpha（最终 Alpha 与输出）
    // 溯源：docs/analysis/01_shader_arch.md#frame014
    // -------------------------------------------------------------------------
    float finalAlpha = sd.alpha * _Alpha;

    // ShaderOutput → Transparent + Emission MIX_SHADER 混合（伪代码）
    // Unity URP 中通过 Blend SrcAlpha OneMinusSrcAlpha 控制透明
    return float4(color, finalAlpha);
}

// =============================================================================
// 顶点函数（Vertex Shader）
// 负责变换坐标、传递 UV / 法线 / 切线 / screenPos 给片元
// =============================================================================
Varyings PBRToonBase_Vert(Attributes input)
{
    Varyings output;

    // 坐标变换（URP 宏）
    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    output.positionCS  = posInputs.positionCS;
    output.positionWS  = posInputs.positionWS;
    output.screenPos   = ComputeScreenPos(posInputs.positionCS);

    // UV
    output.uv = TRANSFORM_TEX(input.uv, _D); // 伪代码：_D_ST 缩放偏移

    // 法线 / 切线 / 副切线（世界空间）
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    output.normalWS    = normInputs.normalWS;
    output.tangentWS   = normInputs.tangentWS;
    output.bitangentWS = normInputs.bitangentWS;

    return output;
}

#endif // PBRTOONBASE_MAIN_INCLUDED
