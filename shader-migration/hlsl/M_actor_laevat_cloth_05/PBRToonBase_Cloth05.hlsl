// =============================================================================
// PBRToonBase_Cloth05.hlsl
// 主 Shader 函数 — 按 Frame 顺序组装（M_actor_laevat_cloth_05）
// 溯源：docs/analysis/M_actor_laevat_cloth_05/01_shader_arch.md
// 注：伪代码级 HLSL，供理解渲染流程使用，非可直接编译版本
//
// 与 PBRToonBase.hlsl（pelica_cloth_04）的主要差异：
//   1. GetSurfaceData — 新增 _M 贴图采样 → SmoothStep → sd.mMask
//   2. GetSurfaceData — _E 未连线，sd.emission = 0
//   3. Frame.011 ThinFilmFilter — _M 遮罩参与（推断）
//   4. Frame.010 Emission — 无效（emission = 0）
// =============================================================================

#ifndef PBRTOONBASE_CLOTH05_MAIN_INCLUDED
#define PBRTOONBASE_CLOTH05_MAIN_INCLUDED

#include "PBRToonBase_Cloth05_Input.hlsl"
#include "SubGroups/SubGroups.hlsl"

#ifndef PI
#define PI 3.14159265358979323846
#endif

// =============================================================================
// Frame.013 — GetSurfaceData（贴图采样 + 表面参数）
// 溯源：docs/analysis/M_actor_laevat_cloth_05/01_shader_arch.md
// 差异：新增 _M 贴图 SmoothStep 预处理；_E 贴图未连线
// =============================================================================
SurfaceData GetSurfaceData(Varyings input)
{
    SurfaceData s;

    // --- 框.001 albedo：_D 贴图采样 ---
    float4 dTex  = SAMPLE_TEXTURE2D(_D, sampler_D, input.uv);
    s.albedo     = dTex.rgb;
    s.alpha      = dTex.a;

    // --- 法线贴图采样（框.002 N，在 InitLightingData 中解码）---
    float4 nTex  = SAMPLE_TEXTURE2D(_N, sampler_N, input.uv);
    s.normalTS   = float3(nTex.xy, 0);  // Z 由 DecodeNormal 重建

    // --- 参数贴图拆通道 ---
    float4 pTex          = SAMPLE_TEXTURE2D(_P, sampler_P, input.uv);
    float  metallic_raw  = pTex.r;     // 框.006 P_R
    float  ao_raw        = pTex.g;     // 框.007 P_G（directOcclusion）
    float  smooth_raw    = pTex.b;     // 框.008 P_B（Smoothness）
    s.rampUV             = pTex.a;     // 框.009 P_A（RampUV）

    // --- 框.012 metallic / 框.049 AO ---
    s.metallic = metallic_raw * _MetallicMax;
    s.ao       = ao_raw;

    // --- 框.008 Smoothness → 粗糙度转换 ---
    s.smoothness           = smooth_raw * _SmoothnessMax;
    s.perceptualRoughness  = PerceptualSmoothnessToPerceptualRoughness(s.smoothness);
    s.roughness            = PerceptualRoughnessToRoughness(s.perceptualRoughness);

    // --- 各向异性 T 轴（框.060~062）：MaxT=0.2197 → 切线方向较粗糙 ---
    float smoothT             = smooth_raw * _Aniso_SmoothnessMaxT;
    s.perceptualRoughnessT    = PerceptualSmoothnessToPerceptualRoughness(smoothT);
    s.roughnessT              = PerceptualRoughnessToRoughness(s.perceptualRoughnessT);

    // --- 各向异性 B 轴（框.063~065）：MaxB=0.6689 → 副切线方向较光滑 ---
    float smoothB             = smooth_raw * _Aniso_SmoothnessMaxB;
    s.perceptualRoughnessB    = PerceptualSmoothnessToPerceptualRoughness(smoothB);
    s.roughnessB              = PerceptualRoughnessToRoughness(s.perceptualRoughnessB);

    // --- 框.031 diffuseColor / 框.013 fresnel0 ---
    s.diffuseColor = ComputeDiffuseColor(s.albedo, s.metallic);
    s.fresnel0     = ComputeFresnel0(s.albedo, s.metallic, float3(0.04, 0.04, 0.04));

    // --------------------------------------------------------------------------
    // _M 贴图预处理（laevat_cloth_05 特有）
    // 材质层：UV 贴图 → T_actor_laevat_cloth_03_M.png → SmoothStep(0,1) → _M槽
    // --------------------------------------------------------------------------
    // 注：UV 贴图节点使用的 UV 通道待确认（推测为 UV0 = input.uv）
    float3 mTex  = SAMPLE_TEXTURE2D(_M, sampler_M, input.uv).rgb;
    // SmoothStep(min=0, max=1) — 由 SmoothStep 子群组实现
    s.mMask.r = SmoothStepCustom(0.0, 1.0, mTex.r);
    s.mMask.g = SmoothStepCustom(0.0, 1.0, mTex.g);
    s.mMask.b = SmoothStepCustom(0.0, 1.0, mTex.b);
    // mMask 送入 _M 槽 → 群组内部消费（最可能：RS EFF 遮罩 / ThinFilmFilter 遮罩）

    // --------------------------------------------------------------------------
    // Frame.010 Emission — _E 未连线，本材质无自发光
    // --------------------------------------------------------------------------
    s.emission = float3(0.0, 0.0, 0.0);

    return s;
}

// =============================================================================
// Frame.012 — InitLightingData（几何向量初始化）
// 溯源：docs/analysis/01_shader_arch.md#frame012
// 本材质与 pelica 完全相同，直接复用逻辑
// =============================================================================
LightingData InitLightingData(Varyings input, SurfaceData sd)
{
    LightingData ld;

    // --- TBN 矩阵（世界空间）---
    float3 N_geo = normalize(input.normalWS);
    float3 T_geo = normalize(input.tangentWS);
    float3 B_geo = normalize(input.bitangentWS);
    float3x3 TBN = float3x3(T_geo, B_geo, N_geo);

    // --- 框.002 N：DecodeNormal（_N 贴图 XY → 世界空间法线）---
    float4 nTex = SAMPLE_TEXTURE2D(_N, sampler_N, input.uv);
    ld.N = (_UseNormalTex > 0.5)
         ? DecodeNormal(nTex.x, nTex.y, _NormalStrength, TBN)
         : N_geo;

    // --- 框.003 V：视角方向 ---
    ld.V = normalize(GetWorldSpaceViewDir(input.positionWS));

    // --- 框.020 L：主光方向 + 光色 + 阴影（URP MainLight）---
    Light mainLight  = GetMainLight();
    ld.L             = normalize(mainLight.direction);
    ld.lightColor    = mainLight.color * mainLight.distanceAttenuation;
    ld.castShadow    = mainLight.shadowAttenuation;

    // --- 框.022 T / 框.055 B（法线贴图驱动的副切线）---
    ld.T  = T_geo;
    ld.B  = B_geo;

    // --- 基础点积 ---
    ld.NoV  = saturate(dot(ld.N, ld.V));
    ld.NoL  = dot(ld.N, ld.L);         // Unsaturated
    ld.LoV  = dot(ld.L, ld.V);

    // --- 各向异性点积（框.056~059）---
    ld.ToL   = dot(ld.T, ld.L);
    ld.BdotL = dot(ld.B, ld.L);
    ld.ToV   = dot(ld.T, ld.V);
    ld.BdotV = dot(ld.B, ld.V);

    // --- 半角点积（Get_NoH_LoH_ToH_BoH）---
    Get_NoH_LoH_ToH_BoH(
        ld.NoL, ld.NoV, ld.LoV,
        ld.ToV, ld.ToL, ld.BdotV, ld.BdotL,
        ld.NdotH, ld.LdotH, ld.TdotH, ld.BdotH);

    return ld;
}

// =============================================================================
// 主片元函数 — 按 Frame 顺序组装
// =============================================================================
float4 PBRToonBase_Cloth05_Frag(Varyings input) : SV_Target
{
    // -------------------------------------------------------------------------
    // Frame.013 + Frame.012 — 贴图采样 + 向量初始化
    // -------------------------------------------------------------------------
    SurfaceData  sd = GetSurfaceData(input);
    LightingData ld = InitLightingData(input, sd);

    // -------------------------------------------------------------------------
    // Frame.005 — DiffuseBRDF（Toon 漫反射）
    // -------------------------------------------------------------------------

    // 框.014 RemaphalfLambert：halfLambert + SigmoidSharp 锐化
    float halfLambert = SigmoidSharp(ld.NoL,
                                     _RemaphalfLambert_center,
                                     _RemaphalfLambert_sharp);

    // 框.018 shadowArea：castShadow 叠加
    float shadowFactor = SigmoidSharp(halfLambert * ld.castShadow,
                                      _CastShadow_center,
                                      _CastShadow_sharp);

    // 框.032 Toon Ramp 采样（RampUV = _P.A, RampIndex = 0.0）
    float3 rampColor; float rampA;
    RampSelect(shadowFactor, _RampIndex, rampColor, rampA);

    // 框.033 directLighting_diffuse
    float3 directOcclusion = lerp(_directOcclusionColor.rgb, float3(1,1,1), sd.ao);
    float3 lightFactor      = ld.lightColor * _dirLight_lightColor.rgb;
    float3 diffuseDirect    = DirectLightingDiffuse(rampColor, directOcclusion,
                                                    sd.diffuseColor, lightFactor);

    // DeSaturation：暗部去饱和（Color desaturation = 0.9）
    float desat = _ColorDesaturationAttenuation * (1.0 - shadowFactor);
    diffuseDirect = DeSaturation(desat, diffuseDirect);

    // -------------------------------------------------------------------------
    // Frame.004 — SpecularBRDF（各向异性 GGX）
    // 特征：MaxT=0.2197(偏粗)，MaxB=0.6689(偏光滑) → 布料高光方向性显著
    // -------------------------------------------------------------------------
    float absNdotL = saturate(ld.NoL);

    float dvIsotropic, dvAnisotropic;
    DV_SmithJointGGX_Aniso(
        ld.NdotH, absNdotL, ld.NoV, sd.roughness,
        ld.TdotH, ld.BdotH, ld.ToL, ld.BdotL,
        ld.ToV, ld.BdotV, sd.roughnessT, sd.roughnessB,
        dvIsotropic, dvAnisotropic);

    // Use anisotropy? = True, Use Toonaniso? = True
    float dv = dvAnisotropic;

    float3 F = F_Schlick(sd.fresnel0, float3(1,1,1), ld.LdotH);
    float3 specularColor = F * dv * absNdotL * PI * _SpecularColor.rgb * ld.lightColor;

    // -------------------------------------------------------------------------
    // Frame.006 — IndirectLighting（间接光照）
    // -------------------------------------------------------------------------
    float3 specFGD;
    float  diffFGD, reflectivity;
    GetPreIntegratedFGD(ld.NoV, sd.perceptualRoughness, sd.fresnel0,
                        specFGD, diffFGD, reflectivity);

    float3 indirectDiffuse  = sd.diffuseColor * diffFGD * _AmbientLightColorTint.rgb;
    float3 indirectSpecular = specFGD * _specularFGDStrength;

    // -------------------------------------------------------------------------
    // Frame.007 — ShadowAdjust（全局阴影亮度调整 = -1.8）
    // 较强阴影压暗，布料暗部明显
    // -------------------------------------------------------------------------
    float shadowAdj = SmoothStepCustom(0.0, 1.0,
                          saturate(_GlobalShadowBrightnessAdjustment + 1.0));
    diffuseDirect *= lerp(shadowAdj, 1.0, shadowFactor);

    float3 color = diffuseDirect + specularColor + indirectDiffuse + indirectSpecular;

    // -------------------------------------------------------------------------
    // Frame.008 — ToonFresnel（Toon 边缘色，Pow=1.7，SMO_H=0.5）
    // -------------------------------------------------------------------------
    float toonFresnelFactor = pow(saturate(1.0 - ld.NoV), _ToonfresnelPow);
    toonFresnelFactor = SmoothStepCustom(_ToonfresnelSMO_L, _ToonfresnelSMO_H,
                                         toonFresnelFactor);
    float layerWeight = saturate(toonFresnelFactor + _LayerWeightValueOffset);
    float3 toonFresnelColor = lerp(_fresnelInsideColor.rgb, _fresnelOutsideColor.rgb, layerWeight);
    color += toonFresnelColor * layerWeight;

    // -------------------------------------------------------------------------
    // Frame.009 — Rim（屏幕空间边缘光）
    // 参数：Rim_width_X=0.042, Rim_width_Y=0.019, Strength=5.0（较亮）
    // -------------------------------------------------------------------------
    float2 screenUV    = input.screenPos.xy / input.screenPos.w;
    float3 normalVS    = float3(ld.N.x, ld.N.y, 0);

    float rimDepthMask   = DepthRim(screenUV, normalVS, _Rim_width_X, _Rim_width_Y);
    float rimFresnelMask = FresnelAttenuation(ld.NoV);
    float rimVertMask    = VerticalAttenuation(ld.N);
    float rimMask        = rimDepthMask * rimFresnelMask * rimVertMask;

    float rimDirAtten    = DirectionalLightAttenuation(ld.NoL, _Rim_DirLightAtten);
    float3 rimFinalColor = RimColor(sd.albedo, ld.lightColor,
                                    _Rim_Color.rgb, _Rim_ColorStrength, ld.LoV);
    color += rimFinalColor * rimMask * rimDirAtten;

    // -------------------------------------------------------------------------
    // Frame.010 — Emission（_E 未连线 → 无自发光）
    // -------------------------------------------------------------------------
    color += sd.emission;  // = float3(0,0,0)，不贡献颜色

    // -------------------------------------------------------------------------
    // 框.048 RS EFF — RS 特效（RSModel=True, Use RS_Eff=True）
    // _M 遮罩参与此处（推断）：mMask 用于限制 RS 效果的区域
    // -------------------------------------------------------------------------
    if (_UseRSEff > 0.5)
    {
        // _M 遮罩推断作用：RS ColorTint 效果只在 _M 非零区域生效
        float3 rsRegionMask = sd.mMask;  // mMask = SmoothStep(_M贴图)
        float3 rsColor = _RS_ColorTint.rgb * _RS_MultiplyValue * _RS_Strength;
        color += rsColor * rsRegionMask;
    }

    // -------------------------------------------------------------------------
    // Frame.011 — ThinFilmFilter（视角色变效果）
    // _M 遮罩次选参与位置（若 RS EFF 已消费 _M，此处不再重复）
    // -------------------------------------------------------------------------
    float thinFilmFresnel = saturate(1.0 - ld.NoV);
    float3 thinFilmColor  = SAMPLE_TEXTURE2D(_ThinFilmLUT, sampler_ThinFilmLUT,
                               float2(thinFilmFresnel, 0.5)).rgb;
    thinFilmColor = lerp(_fresnelInsideColor.rgb, thinFilmColor, thinFilmFresnel);
    thinFilmColor *= _RS_ColorTint.rgb;
    color += thinFilmColor * thinFilmFresnel * _RS_Strength;

    // -------------------------------------------------------------------------
    // Frame.014 — Alpha（不透明，Alpha=1.0）
    // -------------------------------------------------------------------------
    float finalAlpha = sd.alpha * _Alpha;

    return float4(color, finalAlpha);
}

// =============================================================================
// 顶点函数
// =============================================================================
Varyings PBRToonBase_Cloth05_Vert(Attributes input)
{
    Varyings output;

    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    output.positionCS = posInputs.positionCS;
    output.positionWS = posInputs.positionWS;
    output.screenPos  = ComputeScreenPos(posInputs.positionCS);

    output.uv = TRANSFORM_TEX(input.uv, _D);

    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    output.normalWS    = normInputs.normalWS;
    output.tangentWS   = normInputs.tangentWS;
    output.bitangentWS = normInputs.bitangentWS;

    return output;
}

#endif // PBRTOONBASE_CLOTH05_MAIN_INCLUDED
