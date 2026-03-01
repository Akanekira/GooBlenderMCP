// =============================================================================
// PBRToonBaseHair.hlsl
// 主函数：M_actor_laevat_hair_01 / Arknights: Endfield_PBRToonBaseHair
// 按 Frame 顺序组装：GetSurfaceData → Init → Specular/Diffuse/Hair → IndirectLighting
//                    → ShadowAjust → ToonFresnel → Rim&Outline → 最终混合
// 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#include "PBRToonBaseHair_Input.hlsl"
#include "SubGroups/SubGroups.hlsl"

// =============================================================================
// SurfaceData GetSurfaceData(Varyings input)
// 对应 Frame.014 — GetSurfaceData
// =============================================================================
SurfaceData GetSurfaceData(Varyings input)
{
    SurfaceData sd;

    // -------------------------------------------------------------------------
    // Frame.014 — GetSurfaceData
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame014
    // -------------------------------------------------------------------------

    // 采样 _D (Diffuse/Albedo, sRGB)
    float4 D = SAMPLE_TEXTURE2D(_D, sampler_D, input.uv);
    float3 albedoRaw = D.rgb * _BaseColor.rgb;   // 帧.001 albedo

    // 可选面部颜色融合
    albedoRaw = lerp(albedoRaw, _FusionFaceColor.rgb, _UseFusionFaceColor);
    sd.albedo = albedoRaw;
    sd.alpha  = D.a;

    // 采样 _P (PBR 参数, Non-Color)
    float4 P = SAMPLE_TEXTURE2D(_P, sampler_P, input.uv);
    float p_r = P.r;    // 帧.006 P_R
    float p_g = P.g;    // 帧.051 P_G
    float p_b = P.b;    // 帧.008 P_B
    float p_a = P.a;    // 帧.009 P_A

    sd.metallic            = p_r * _MetallicMax;           // 帧.012 metallic
    sd.ao                  = p_g;                           // 帧.049 AO
    sd.smoothness          = p_b * _SmoothnessMax;          // 帧.008 P_B
    sd.directOcclusion     = p_g;                           // 帧.030
    sd.rampUV              = p_a;                           // RampUV

    // 粗糙度转换
    sd.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(sd.smoothness);  // 帧.010
    sd.roughness           = PerceptualRoughnessToRoughness(sd.perceptualRoughness);    // 帧.011

    // 衍生 PBR 量
    sd.diffuseColor = ComputeDiffuseColor(sd.albedo, sd.metallic);   // 帧.031
    sd.fresnel0     = ComputeFresnel0(sd.albedo, sd.metallic);        // 帧.013

    // 采样 _HN 用于法线解码（DecodeNormal 由 Init 处理，此处记录采样）
    float4 HN_tex = SAMPLE_TEXTURE2D(_HN, sampler_HN, input.uv);
    sd.normalTS      = float3(HN_tex.rg, 1.0) * _NormalStrength;     // 待 DecodeNormal 解算
    sd.hairTangentTS = float3(HN_tex.rg, 1.0) * _HNormalStrength;    // 发丝切线方向（待 DecodeNormal）

    return sd;
}

// =============================================================================
// LightingData InitLightingData(Varyings input, SurfaceData sd)
// 对应 Frame.013 — Init
// =============================================================================
LightingData InitLightingData(Varyings input, SurfaceData sd)
{
    LightingData ld;

    // -------------------------------------------------------------------------
    // Frame.013 — Init
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame013
    // -------------------------------------------------------------------------

    // 帧.002 N：DecodeNormal(_HN.RGB, NormalStrength)，转换到世界空间
    float3 N_TS  = DecodeNormal(sd.normalTS);
    ld.N = normalize(TransformTangentToWorld(N_TS,
        float3x3(input.tangentWS, input.bitangentWS, input.normalWS)));

    // 帧 "HN"：DecodeNormal(_HN.RGB, HNormalStrength)，发丝切线方向
    float3 HN_TS = DecodeNormal(sd.hairTangentTS);
    ld.HN = normalize(TransformTangentToWorld(HN_TS,
        float3x3(input.tangentWS, input.bitangentWS, input.normalWS)));

    // 帧.003 V
    ld.V = normalize(GetWorldSpaceViewDir(input.positionWS));

    // 帧.020 L（主方向光）
    Light mainLight = GetMainLight();
    ld.L = normalize(mainLight.direction);
    ld.lightColor = _DirLightColor.rgb;

    // 帧.056 biNormal / 帧 "B"：B = cross(N, HN)（发丝副法线）
    ld.T = input.tangentWS;
    ld.B = normalize(cross(ld.N, ld.HN));    // 发丝副法线

    // H（半角向量）
    ld.H = normalize(ld.L + ld.V);

    // 帧.004 NoV
    ld.NoV = max(dot(ld.N, ld.V), 0.0001);

    // 帧 NoL_Unsaturate：未 clamp 的 NdotL
    ld.NoL_unsat = dot(ld.N, ld.L);

    // 帧.025 abs(NdotL)
    ld.absNdotL = abs(ld.NoL_unsat);

    // 帧.029 clampedNdotL
    ld.NoL = saturate(ld.NoL_unsat);

    // 帧.014 RemaphalfLambert：SigmoidSharp(0.5×NoL_unsat+0.5, center, sharp)
    float halfLambertRaw = ld.NoL_unsat * 0.5 + 0.5;
    ld.halfLambert = SigmoidSharp(halfLambertRaw, _RemapHalfLambertCenter, _RemapHalfLambertSharp);

    // 帧.021 LoV
    ld.LoV = dot(ld.L, ld.V);

    // 帧.023 NdotH / 帧.024 LdotH / TdotH / BdotH（via Get_NoH_LoH_ToH_BoH）
    Get_NoH_LoH_ToH_BoH(ld.N, ld.V, ld.L, ld.T, ld.B,
        ld.NdotH, ld.LdotH, ld.TdotH, ld.BdotH);

    // 发丝特有：HNdotV（帧 "HNdotV"）
    ld.HNdotV = dot(ld.HN, ld.V);

    // 发丝特有：MixV（帧 "MixV"） = normalize(V + FHighLightPos 偏移)
    // 实现：MixV = V 与发丝切线混合后的方向（精确做法待确认）
    float3 MixV = normalize(ld.V + ld.HN * _FHighLightPos);

    // BdotMixV（帧 "BdotMixV"）
    ld.BdotMixV = dot(ld.B, MixV);

    // 投影阴影（来自 SHADERINFO GooEngine 节点）
    ld.castShadow = mainLight.shadowAttenuation;   // 近似：URP 阴影衰减

    return ld;
}

// =============================================================================
// float4 PBRToonBaseHair_Frag(Varyings input) : SV_Target
// 主片元函数，按 Frame 顺序组装最终颜色
// =============================================================================
float4 PBRToonBaseHair_Frag(Varyings input) : SV_Target
{
    SurfaceData  sd = GetSurfaceData(input);
    LightingData ld = InitLightingData(input, sd);

    // -------------------------------------------------------------------------
    // Frame.014 — GetSurfaceData（roughness_T / roughness_B 各向异性参数）
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame014
    // -------------------------------------------------------------------------
    // 注：发丝 GGX 各向异性可用 roughness 作各向同性近似，
    //     实际各向异性高光由 Frame.008 Kajiya-Kay 提供
    float roughnessT = sd.roughness;
    float roughnessB = sd.roughness;

    // -------------------------------------------------------------------------
    // Frame.006 — Specular BRDF
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame006
    // -------------------------------------------------------------------------
    float DV = DV_SmithJointGGX_Aniso(
        ld.absNdotL, ld.NoV, ld.NdotH,
        ld.TdotH, ld.BdotH,
        roughnessT, roughnessB);

    float3 F       = F_Schlick(sd.fresnel0, ld.LdotH);
    float3 specBRDF = DV * F * _SpecularColor.rgb * PI * ld.lightColor;
    // 帧.028 specTerm（乘以 clampedNdotL 在最终组装）
    float3 specTerm = specBRDF * ld.NoL;

    // -------------------------------------------------------------------------
    // Frame.007 — Diffuse BRDF
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame007
    // -------------------------------------------------------------------------

    // 帧.015 shadowNdotL：SigmoidSharp(NoL_unsat, CastShadow_center, CastShadow_sharp)
    float shadowNdotL = SigmoidSharp(ld.NoL_unsat, _CastShadowCenter, _CastShadowSharp);

    // 帧.019 shadowScene：投影阴影 Toon 化（Frame.010 已处理，见下方）
    // 此处先记录投影阴影原始值 ld.castShadow，在 Frame.010 后使用

    // 帧.032 shadowRampColor：采样内嵌 RD 贴图（发丝阴影 Ramp）
    float rampU    = ld.halfLambert;
    float rampV    = sd.rampUV;
    float3 shadowRampColor = SAMPLE_TEXTURE2D(_HairRampTex, sampler_HairRampTex,
                                               float2(rampU, rampV)).rgb;

    // directLighting_diffuse 子群组（与 PBRToonBase 相同）
    float3 diffuseDirect = directLighting_diffuse(
        shadowRampColor,
        _DirectOcclusionColor.rgb,
        sd.directOcclusion,
        sd.diffuseColor,
        ld.lightColor);

    // -------------------------------------------------------------------------
    // Frame.008 — Anisotropic HighLight（发丝各向异性高光，Kajiya-Kay）
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame008
    // -------------------------------------------------------------------------

    // sqrt(1 - (B·MixV)²) = sinT — 高光带强度
    float BdotV_sq = ld.BdotMixV * ld.BdotMixV;
    float sinT_sq  = saturate(1.0 - BdotV_sq);           // 运算.010 1-x²
    float sinT     = sqrt(sinT_sq);                       // 运算.010 SQRT
    float absSinT  = abs(sinT);                           // 运算.004 ABSOLUTE

    // 高光形状
    float hlRaw = sinT * absSinT;                         // 运算.007 MULTIPLY
    hlRaw = hlRaw * -1.0 + 0.0;                           // 运算.016 ADD（偏移）
    // 注：偏移值由 FHighLightPos / Highlight length 控制

    // SmoothStep A：Highlight length 控制纵向延展（SmoothStep 群组.021）
    float smA = SmoothStepCustom(0.0, _HighlightLength, hlRaw);

    // SmoothStep B：颜色插值边界（SmoothStep 群组.023）
    float smB = SmoothStepCustom(
        _HairHLColorLerpSMOMin,
        _HairHLColorLerpSMOMax,
        hlRaw + _HairHLColorLerpSMOOffset);

    // 双色插值
    float3 colorAB = lerp(_HighLightColorA.rgb, _HighLightColorB.rgb, smB);   // 混合.001

    // HNdotV(Fresnel)：pow(HNdotV, 5.0)（帧.022）
    float fresnelHair = pow(saturate(ld.HNdotV), 5.0);                        // 运算.005

    // 最终发丝高光
    float3 hairHighlight = smA * colorAB * fresnelHair * _FinalBrightness;    // 混合.014 / 混合.016

    // -------------------------------------------------------------------------
    // Frame.009 — IndirectLighting
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame009
    // -------------------------------------------------------------------------
    float3 diffuseFGD, specularFGD;
    float  energyCompensation;
    GetPreIntegratedFGDGGXAndDisneyDiffuse(
        ld.NoV, sd.perceptualRoughness, sd.fresnel0,
        diffuseFGD, specularFGD, energyCompensation);

    float3 indirectDiffuse  = diffuseFGD * sd.diffuseColor * sd.ao;    // 帧.036
    float3 indirectSpecular = specularFGD * sd.fresnel0;               // 帧.038
    // energyCompensation 在最终高光组合时应用                           // 帧.035

    // -------------------------------------------------------------------------
    // Frame.010 — ShadowAjust（投影阴影 Toon 化）
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame010
    // -------------------------------------------------------------------------
    float shadowAdj = clamp(
        SmoothStepCustom(_CastShadowCenter - _CastShadowSharp * 0.5,
                         _CastShadowCenter + _CastShadowSharp * 0.5,
                         ld.castShadow),
        0.0, 1.0);                                                     // 钳制.006

    // 将投影阴影合并到 diffuse（shadowNdotL × shadowAdj）
    float  shadowArea  = shadowNdotL * shadowAdj;                      // 帧.018 shadowArea
    float3 diffuseFinal = diffuseDirect * shadowArea;                  // 帧.019 shadowScene 组合

    // GlobalShadowBrightnessAdjustment（帧.039，顶层最终混合）
    diffuseFinal *= _GlobalShadowBrightness;

    // -------------------------------------------------------------------------
    // Frame.011 — ToonFresnel
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame011
    // -------------------------------------------------------------------------
    float fresnelRaw    = pow(saturate(1.0 - ld.NoV), _ToonFresnelPow);           // 运算.014
    float fresnelSmooth = SmoothStepCustom(_ToonFresnelSMO_L, _ToonFresnelSMO_H, fresnelRaw); // 群组.010
    float3 fresnelColor = lerp(_FresnelInsideColor.rgb, _FresnelOutsideColor.rgb, fresnelSmooth); // 混合.006

    // -------------------------------------------------------------------------
    // Frame.012 — Rim & Outline
    // 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md#frame012
    // -------------------------------------------------------------------------

    // 方向光衰减（帧.045）
    float dirLightAtten = DirectionalLightAttenuation(ld.N, ld.L, _RimDirLightAtten);

    // Fresnel 衰减（帧.042）
    float fresnelAtten = FresnelAttenuation(ld.NoV, _RimWidthX);

    // 垂直方向衰减（帧.043）
    // V.y（世界空间视角方向 Y 分量）近似为 VerticalAttenuation 输入
    float viewDirY = ld.V.y;
    float vertAtten = VerticalAttenuation(viewDirY, _RimWidthY, _UseRimLimitation > 0.5);

    // DepthRim（帧.041）
    float depthRim = DepthRim(_CameraDepthTexture, sampler_CameraDepthTexture,
                               input.screenPos, input.positionWS, ld.N, _RimWidthX, _RimWidthY);

    // Rim_Color（帧.046）
    float3 rimColorFinal = Rim_Color(_RimColor.rgb, _RimColorStrength,
                                     fresnelAtten, vertAtten, depthRim, dirLightAtten);

    // OutlineColor（帧.048 — Hair 专属）
    float3 outlineMask = OutlineColor(fresnelAtten, vertAtten);

    // Rim 最终合成（混合.018 / 混合.025 / 运算.026-028）
    // outlineMask 作为描边遮罩叠加到 rim
    float3 rimFinal = rimColorFinal + outlineMask * _RimColor.rgb * _RimColorStrength;

    // -------------------------------------------------------------------------
    // 最终颜色组装
    // -------------------------------------------------------------------------

    // 直接光照
    float3 directLight = diffuseFinal + specTerm * energyCompensation;

    // 间接光照
    float3 indirectLight = indirectDiffuse + indirectSpecular;

    // 发丝各向异性高光
    float3 hairHL = hairHighlight;

    // ToonFresnel 叠加
    float3 colorWithFresnel = directLight + indirectLight + hairHL + fresnelColor;

    // Rim & Outline 叠加
    float3 finalColor = colorWithFresnel + rimFinal;

    // DeSaturation（帧.071）：阴影区域去饱和
    // 通过 shadowArea 插值 → 在暗部降低饱和度
    float3 desatColor = DeSaturation(finalColor, _ColorDesatInShadow);
    finalColor = lerp(finalColor, desatColor, 1.0 - shadowArea);

    return float4(finalColor, sd.alpha);
}

// =============================================================================
// Varyings PBRToonBaseHair_Vert(Attributes input)
// 顶点变换
// =============================================================================
Varyings PBRToonBaseHair_Vert(Attributes input)
{
    Varyings output;

    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs   nrmInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.positionCS   = posInputs.positionCS;
    output.positionWS   = posInputs.positionWS;
    output.uv           = input.uv;
    output.normalWS     = nrmInputs.normalWS;
    output.tangentWS    = nrmInputs.tangentWS;
    output.bitangentWS  = nrmInputs.bitangentWS;
    output.screenPos    = ComputeScreenPos(posInputs.positionCS);

    return output;
}
