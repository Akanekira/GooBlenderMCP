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
// Frame.069 — SimpleTransmission（屏幕空间伪透射，修改 albedo，前置于漫反射）
// 溯源：docs/analysis/Frames/Frame069_SimpleTransmission.md
// 注：SCREENSPACEINFO 为 Goo Engine 专有节点；Unity 替换为 _CameraOpaqueTexture
// =============================================================================
float3 Frame069_SimpleTransmission(SurfaceData sd, LightingData ld, Varyings input)
{
    // Step 1: 菲涅尔.001（IOR=1.25）— 产生边缘权重，用于屏幕采样坐标偏移
    float ior    = 1.25;
    float NdotV  = saturate(dot(ld.N, -ld.V));
    float fresnel = saturate(pow(1.0 - NdotV, 1.0 + ior * 0.5));

    // Step 2: 矢量运算.002 ADD — 摄像机视线 + Fresnel(broadcast) = 偏移视图坐标
    float3 offsetViewPos = (-ld.V) + float3(fresnel, fresnel, fresnel);

    // Step 3: Screenspace Info.001 — 在偏移坐标处采样场景背景色（概念性）
    // Unity URP：需开启 Opaque Texture 或 GrabPass，使用 _CameraOpaqueTexture
    float2 screenUV       = input.screenPos.xy / input.screenPos.w;
    float2 offsetScreenUV = screenUV + offsetViewPos.xy * 0.01; // 概念性近似
    float3 sceneColor     = SAMPLE_TEXTURE2D(_CameraOpaqueTexture,
                                             sampler_CameraOpaqueTexture,
                                             offsetScreenUV).rgb;

    // Step 4: 混合.034 — 场景色 lerp 到 Albedo（clamp）
    // A=sceneColor, B=albedo, Factor=_SimpleTransmissionValue（default 0.65）
    float3 transBlend = saturate(lerp(sceneColor, sd.albedo, _SimpleTransmissionValue));

    // Step 5: 混合.035 — 功能开关（clamp）
    // A=albedo, B=transBlend, Factor=_UseSimpleTransmission（0 or 1）
    float3 result = saturate(lerp(sd.albedo, transBlend, _UseSimpleTransmission));

    return result;
}

// =============================================================================
// Frame.005 — DiffuseBRDF（Toon 漫反射）
// 溯源：docs/analysis/Frames/Frame005_DiffuseBRDF.md
// 节点：SigmoidSharp×2 / MINIMUM / COMBXYZ / RampSelect / directLighting_diffuse
// =============================================================================
float3 Frame005_DiffuseBRDF(SurfaceData sd, LightingData ld, out float outRampAlpha)
{
    // 帧.015 shadowNdotL：SigmoidSharp #1（halfLambert 阴影）
    // 注：noL 来自 Frame.012 的 运算.001，可能已含 halfLambert 变换
    float shadowNdotL = SigmoidSharp(ld.NoL,
                                     _RemaphalfLambert_center,
                                     _RemaphalfLambert_sharp);

    // 帧.019 shadowScene：SigmoidSharp #2（投影阴影独立软化）
    float shadowScene = SigmoidSharp(ld.castShadow,
                                     _CastShadow_center,
                                     _CastShadow_sharp);

    // 运算.002 MINIMUM：双路阴影取暗合并（投影阴影完全覆盖自阴影）
    float shadowCombined = min(shadowNdotL, shadowScene);

    // 帧.018 shadowArea：COMBXYZ 打包为 RampUV Vector
    // X=阴影值（Ramp U），Y=0.5（固定 V，1D Ramp 中线），Z=0
    float3 rampUV = float3(shadowCombined, 0.5, 0.0);

    // 帧.032 shadowRampColor：RampSelect Toon Ramp 采样
    float3 rampColor; float rampAlpha;
    RampSelect(rampUV, _RampIndex, rampColor, rampAlpha);

    // 群组.019 directLighting_diffuse：漫反射四路乘积
    // = (rampColor × 1/π) × diffuseColor × dirLightColor × directOcclusion
    float3 directOcclusion = lerp(_directOcclusionColor.rgb, 1.0, sd.ao);
    float3 diffuseDirect   = DirectLightingDiffuse(rampColor, directOcclusion,
                                                   sd.diffuseColor,
                                                   _dirLight_lightColor.rgb);

    outRampAlpha = rampAlpha; // → Frame.007 ShadowAdjust / SmoothStep.x
    return diffuseDirect;
}

// =============================================================================
// Frame.007 — ShadowAdjust（全局阴影亮度调整）
// 溯源：docs/analysis/01_shader_arch.md#frame007
// 入参 rampAlpha 来自 Frame.005 的 RampSelect 输出
// =============================================================================
float3 Frame007_ShadowAdjust(float3 diffuse, float rampAlpha)
{
    float shadowAdj = SmoothStepCustom(0.0, 1.0, _GlobalShadowBrightnessAdjustment);
    return diffuse * lerp(shadowAdj, 1.0, rampAlpha);
}

// =============================================================================
// Frame.004 — SpecularBRDF（各向异性 GGX 高光）
// 溯源：docs/analysis/Frames/Frame004_SpecularBRDF.md
// =============================================================================
float3 Frame004_SpecularBRDF(SurfaceData sd, LightingData ld)
{
    float clampedRoughness = max(sd.roughness, 0.001);
    float absNdotL = saturate(ld.NoL);

    // 框.026 DV / 框.065 AnisoDV
    float dvIsotropic, dvAnisotropic;
    DV_SmithJointGGX_Aniso(
        ld.NdotH, absNdotL, ld.NoV, clampedRoughness,
        ld.TdotH, ld.BdotH, ld.ToL, ld.BdotL,
        ld.ToV, ld.BdotV, sd.roughnessT, sd.roughnessB,
        dvIsotropic, dvAnisotropic);

    // 框.027 F：Schlick Fresnel（两路共用同一 F 项）
    float3 F = F_Schlick(sd.fresnel0, float3(1, 1, 1), ld.LdotH);

    // 框.028 specTerm / 框.066 specTermAniso：两路高光项（F × DV）
    float3 specTerm      = F * dvIsotropic;   // Vector Math.003 [帧.028]
    float3 specTermAniso = F * dvAnisotropic;  // Vector Math.018 [帧.066]

    // 框.068 Toon Aniso 选择（混合.020）：Toon 路径使用简化的 BdotV 高光
    float3 toonAnisoResult = (_UseToonAniso > 0.5) ? saturate(BdotV) : specTermAniso;

    // 混合.016 / 混合.017：Use anisotropy? + AnisotropicMask 加权混合
    float3 finalSpecTerm;
    if (_UseAnisotropy > 0.5)
        finalSpecTerm = lerp(specTerm, toonAnisoResult, _AnisotropicMask);
    else
        finalSpecTerm = specTerm;

    // Vector Math.016：π 归一化修正（待确认）
    // finalSpecTerm *= PI;

    // 帧.034（根级）：directLighting_specular = specTerm × lightColor
    float3 specularColor = finalSpecTerm * ld.lightColor;

    return specularColor;
}

// =============================================================================
// Frame.006 — IndirectLighting（间接光照）
// 溯源：docs/analysis/Frames/Frame006_IndirectLighting.md
// 节点：群组.005(GetPreIntegratedFGD) / 运算.015(DIVIDE) / 运算.013(SUBTRACT) /
//       Vector Math.012(MULTIPLY) / Vector Math.013(ADD) /
//       混合.025/010(indirectSpecComp) / 混合.013(ambientCombined) /
//       混合.007/008(indirectDiffuse) / 混合.011(totalSpecular) / 混合.009(totalLighting)
// 入参：directSpecular（Frame.004 输出）/ directDiffuse（Frame.005 输出）
// 职责：在函数内完成 energyCompFactor 修正 + VM.015 汇合 + 间接项叠加，返回完整 totalLighting
// =============================================================================
float3 Frame006_IndirectLighting(SurfaceData sd, LightingData ld,
                                 float3 directSpecular, float3 directDiffuse)
{
    // Stage 1: FGD LUT 查询（群组.005 GetPreIntegratedFGDGGXAndDisneyDiffuse）
    // LUT 布局：R=B_term, G=A+B(reflectivity), B=Disney Diffuse FGD
    float3 specularFGD;
    float  diffuseFGD, reflectivity;
    GetPreIntegratedFGD(ld.NoV, sd.perceptualRoughness, sd.fresnel0,
                        specularFGD, diffuseFGD, reflectivity);

    // Stage 2: 帧.035 energyCompensation — Kulla-Conty 多重散射修正
    // 运算.015 DIVIDE : 1.0 / reflectivity
    // 运算.013 SUBTRACT : (1/r) − 1.0 = ecFactor
    float  invR     = 1.0 / max(reflectivity, 1e-4);   // 运算.015（防除零）
    float  ecFactor = invR - 1.0;                       // 运算.013 [帧.035]

    // Stage 3A: energyCompFactor（→ Reroute.110）修正 directSpecular
    // Vector Math.012 MULTIPLY : F0 × ecFactor
    // Vector Math.013 ADD      : (F0 × ecFactor) + 1.0
    // 节点图中 Reroute.110 将此系数送回乘以 Frame.004 的输出，此处在函数内内联完成
    float3 energyCompFactor   = sd.fresnel0 * ecFactor + float3(1, 1, 1); // VM.012 + VM.013
    float3 correctedSpecular  = directSpecular * energyCompFactor;          // Reroute.110 乘法

    // Stage 3B: directLighting = correctedSpecular + directDiffuse（根节点 VM.015 ADD）
    float3 directLighting = correctedSpecular + directDiffuse;              // VM.015

    // Stage 4: 间接镜面能量补偿（indirectSpecComp = ecFactor × specFGD × strength）
    // 混合.025 MULTIPLY : specularFGD × _specularFGDStrength
    // 混合.010 MULTIPLY : ecFactor × weighted_specFGD
    float3 weightedSpecFGD  = specularFGD * _specularFGDStrength;   // 混合.025
    float3 indirectSpecComp = ecFactor    * weightedSpecFGD;         // 混合.010

    // Stage 5: 帧.036 ambientCombined（AmbientTint × AmbientLighting）
    // 混合.013 MULTIPLY；_AmbientLighting = SHADERINFO.Ambient Lighting（Goo Engine 专有）
    // Unity URP 替换：SampleSH(normalWS) 或 unity_AmbientSky.rgb
    float3 ambientCombined = _AmbientLightColorTint.rgb * _AmbientLighting; // 混合.013 [帧.036]

    // Stage 6: 间接漫反射（diffuseColor × diffuseFGD × ambientCombined）
    // 混合.007 MULTIPLY : diffuseColor × diffuseFGD
    // 混合.008 MULTIPLY : × ambientCombined
    float3 indirectDiffuse = sd.diffuseColor * diffuseFGD * ambientCombined; // 混合.007+008

    // Stage 7: 汇合
    // 混合.011 ADD : directLighting + indirectSpecComp = totalSpecular
    // 混合.009 ADD : totalSpecular + indirectDiffuse   = totalLighting → 混合.004
    float3 totalSpecular = directLighting  + indirectSpecComp;  // 混合.011
    return  totalSpecular  + indirectDiffuse;                   // 混合.009 → 混合.004
}

// =============================================================================
// Frame.008 — ToonFresnel（Toon 风格边缘色叠加）
// 溯源：docs/analysis/01_shader_arch.md#frame008
// =============================================================================
float3 Frame008_ToonFresnel(LightingData ld)
{
    // LayerWeight Fresnel 因子（基于 NoV，模拟 Blender 的 LAYER_WEIGHT 节点）
    float toonFresnelFactor = pow(1.0 - ld.NoV, _ToonfresnelPow);
    toonFresnelFactor = SmoothStepCustom(_ToonfresnelSMO_L, _ToonfresnelSMO_H,
                                         toonFresnelFactor);

    // LayerWeight Value + Offset 控制混合强度
    float layerWeight = saturate(toonFresnelFactor * _LayerWeightValue + _LayerWeightValueOffset);

    // 内/外颜色混合
    float3 toonFresnelColor = lerp(_fresnelInsideColor.rgb, _fresnelOutsideColor.rgb, layerWeight);

    return toonFresnelColor * layerWeight;
}

// =============================================================================
// Frame.009 — Rim（屏幕空间深度边缘光）
// 溯源：docs/analysis/Frames/Frame009_Rim.md
// =============================================================================
float3 Frame009_Rim(SurfaceData sd, LightingData ld, Varyings input)
{
    // 屏幕空间 UV
    float2 screenUV = input.screenPos.xy / input.screenPos.w;

    // 法线视空间分量（近似：使用世界空间法线 XY 作为偏移方向）
    float3 normalVS = float3(ld.N.x, ld.N.y, 0); // 概念性转换

    // ── Stage 1: 遮罩四因子 ──────────────────────────────────────────────

    // 帧.045 — DirectionalLightAttenuation（群组.013）
    // lerp(Rim_DirLightAtten, 1.0, saturate(NoL))，背光侧保留量
    float dirLightAtten = DirectionalLightAttenuation(ld.NoL, _Rim_DirLightAtten);

    // 帧.042 — FresnelAttenuation（群组.014）
    // (1−NoV)⁴，grazing angle 处 Rim 最强
    float fresnelAtten = FresnelAttenuation(ld.NoV);

    // 帧.043 — VerticalAttenuation（群组.015）
    // saturate(normalWS.y)，顶部强底部弱
    float verticalAtten = VerticalAttenuation(ld.N);

    // 帧.041 — DepthRim（群组.016）
    // 屏幕空间法线偏移深度差，输出 [0,1] 边缘遮罩
    float depthRim = DepthRim(screenUV, normalVS, _Rim_width_X, _Rim_width_Y);

    // ── Stage 2: 遮罩合并 ────────────────────────────────────────────────

    // 运算.026 MULTIPLY：DirLightAtten × FresnelAtten
    float maskDF = dirLightAtten * fresnelAtten;

    // 运算.027 MULTIPLY：× VerticalAtten
    float maskDFV = maskDF * verticalAtten;

    // 运算.029 MINIMUM：将 DepthRim 贡献上限截断为 0.5，防止过曝
    float depthRimCapped = min(depthRim, 0.5);

    // 运算.028 MULTIPLY：最终 rimMask = D×F×V × min(DepthRim, 0.5)
    float rimMask = maskDFV * depthRimCapped;

    // ── Stage 3: 边缘光颜色（帧.046 Rim_Color，群组.018）────────────────

    float3 rimColor = RimColor(sd.albedo, ld.lightColor,
                               _Rim_Color.rgb, _Rim_ColorStrength, ld.LoV);

    // ── Stage 4: 颜色 × 遮罩（混合.018 MIX MULTIPLY RGBA）──────────────

    return rimColor * rimMask;
}

// =============================================================================
// Frame.011 — ThinFilmFilter（RS 彩虹/薄膜干涉效果）
// 溯源：docs/analysis/Frames/Frame011_ThinFilmFilter.md
// 贴图 Aurora: T_actor_aurora_cloth_03_RS.png (Linear / Extend)
// 贴图 Yvonne: T_actor_yvonne_cloth_05_RS.png (sRGB)
// =============================================================================
float3 Frame011_ThinFilmFilter(float3 color, SurfaceData sd, LightingData ld,
                                float clampedNdotL, float shadowScene, Varyings input)
{
    // ── Step 1: 视角菲涅耳 Facing（层权重 LAYER_WEIGHT）──────────────────
    // Facing ≈ pow(1 - saturate(dot(N, V)), 1 / _LayerWeightValue)
    float NdotV  = saturate(dot(ld.N, ld.V));
    float facing = pow(1.0 - NdotV, 1.0 / max(_LayerWeightValue, 0.001));

    // ── Step 2: Facing 偏移 + 钳制（运算.004 ADD → 钳制.001 CLAMP）──────
    float facingAdj = saturate(facing + _LayerWeightValueOffset);

    // ── Step 3: 构造 RS 贴图 UV（合并 XYZ.004: X=facingAdj, Y=0.5 固定）──
    float2 rsUV = float2(facingAdj, 0.5);

    // ── Step 4: 采样双 RS 贴图并混合（混合.032 MIX）──────────────────────
    float4 rsAurora = SAMPLE_TEXTURE2D(_RS_Tex_Aurora, sampler_RS, rsUV);
    float4 rsYvonne = SAMPLE_TEXTURE2D(_RS_Tex_Yvonne, sampler_RS, rsUV);
    float4 rsBlend  = lerp(rsAurora, rsYvonne, _RS_Index);

    // ── Step 5: 色调 × 强度调制 ──────────────────────────────────────────
    // 混合.036 MULTIPLY：RS × RS_ColorTint
    float4 rsTinted = rsBlend * _RS_ColorTint;
    // 混合.023 MULTIPLY：× RS_Strength
    float4 rsStrength = rsTinted * _RS_Strength;

    // ── Step 6: 光照调制（Fresnel 路径完整执行）──────────────────────────
    // 混合.027 MULTIPLY：× clampedNdotL
    float4 rsLit = rsStrength * clampedNdotL;
    // 混合.028 MULTIPLY：× shadowScene
    float4 rsShadowed = rsLit * shadowScene;

    // ── Step 7: 双路径分叉 ───────────────────────────────────────────────
    float4 mTex = SAMPLE_TEXTURE2D(_M, sampler_M, input.uv);

    // Fresnel 路径（RS_Model=0）：混合.033 MULTIPLY：rsShadowed × _M 遮罩
    float4 pathA = rsShadowed * mTex;

    // Model 路径（RS_Model=1）：混合.038 MULTIPLY：_M × RS_ColorTint_B
    float4 pathB = mTex * _RS_ColorTint_B;

    // ── Step 8: RS_Model 开关选择（混合.037 MIX）─────────────────────────
    float4 thinFilmColor = lerp(pathA, pathB, _RS_Model);

    // ── 下游：帧.048 RS EFF ──────────────────────────────────────────────
    // 混合.029 LIGHTEN（Factor=_RS_MultiplyValue）：逐通道取最大值
    float3 lightened = color + (max(color, thinFilmColor.rgb) - color) * _RS_MultiplyValue;
    // 混合.030 MIX（Factor=_UseRSEff）：全局 RS 效果开关
    color = lerp(color, lightened, _UseRSEff);

    return color;
}

// =============================================================================
// 主片元函数（Fragment Shader）
// 按 Frame 顺序逐步组装最终颜色
// =============================================================================
float4 PBRToonBase_Frag(Varyings input) : SV_Target
{
    // Frame.013 + Frame.012
    SurfaceData  sd = GetSurfaceData(input);
    LightingData ld = InitLightingData(input, sd);

    // Frame.069 — SimpleTransmission：透射修改 albedo（前置，影响后续所有漫反射计算）
    sd.albedo       = Frame069_SimpleTransmission(sd, ld, input);
    sd.diffuseColor = ComputeDiffuseColor(sd.albedo, sd.metallic); // albedo 变，diffuseColor 重算

    // Frame.005 — DiffuseBRDF
    float rampAlpha;
    float3 directDiffuse  = Frame005_DiffuseBRDF(sd, ld, rampAlpha);

    // Frame.007 — ShadowAdjust（rampAlpha 驱动全局阴影亮度）
    directDiffuse = Frame007_ShadowAdjust(directDiffuse, rampAlpha);

    // Frame.004 — Specular（未修正，energyCompFactor 在 Frame.006 内部应用）
    float3 directSpecular = Frame004_SpecularBRDF(sd, ld);

    // Frame.006 — IndirectLighting
    // 内部完成：directSpecular × energyCompFactor(Reroute.110) + directDiffuse(VM.015)
    //            + indirectSpecComp(混合.011) + indirectDiffuse(混合.009) = totalLighting
    float3 color = Frame006_IndirectLighting(sd, ld, directSpecular, directDiffuse);

    // Frame.008 — ToonFresnel
    color += Frame008_ToonFresnel(ld);

    // Frame.009 — Rim
    color += Frame009_Rim(sd, ld, input);

    // Frame.010 — Emission
    color += sd.emission;

    // Frame.011 — ThinFilmFilter（RS 彩虹）
    // clampedNdotL 来自 Frame.012 Init（帧.029 clampedNdotL）
    // shadowScene 来自 Frame.005 DiffuseBRDF（帧.019 SigmoidSharp(castShadow)）
    float clampedNdotL = saturate(ld.NoL);                                          // 帧.029
    float shadowScene  = SigmoidSharp(ld.castShadow, _CastShadow_center, _CastShadow_sharp); // 帧.019
    color = Frame011_ThinFilmFilter(color, sd, ld, clampedNdotL, shadowScene, input);

    // Frame.014 — Alpha
    return float4(color, sd.alpha * _Alpha);
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
