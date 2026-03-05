// =============================================================================
// PBRToonTest.hlsl
// 主 Shader 函数 — 按物理渲染层次重新组装（重构版）
// 溯源材质：M_actor_pelica_cloth_04
// 溯源群组：Arknights: Endfield_PBRToonBase（437节点，15个Frame）
// 参考基准：PBRToonBase.hlsl（Frame顺序版）
// 重构目标：光照数据初始化 → 直接光 → 间接光 → 自发光，每层内部细分
// 注：本文件为伪代码级 HLSL，供理解渲染流程使用，非可直接编译版本
// =============================================================================

#ifndef PBRTOONTEST_MAIN_INCLUDED
#define PBRTOONTEST_MAIN_INCLUDED

#include "PBRToonBase_Input.hlsl"
#include "SubGroups/SubGroups.hlsl"

#ifndef PI
#define PI 3.14159265358979323846
#endif

// =============================================================================
// GetSurfaceData — 贴图采样 + 表面参数计算
// 对应 PBRToonBase.hlsl: Frame.013
// =============================================================================
SurfaceData GetSurfaceData(Varyings input)
{
    SurfaceData s;

    // --- Albedo (_D.RGB) + Alpha (_D.A) ---
    float4 dTex   = SAMPLE_TEXTURE2D(_D, sampler_D, input.uv);
    s.albedo       = dTex.rgb;
    s.alpha        = dTex.a;

    // --- 法线贴图 XY（切线空间，Z 由 DecodeNormal 重建）---
    float4 nTex    = SAMPLE_TEXTURE2D(_N, sampler_N, input.uv);
    s.normalTS     = float3(nTex.xy, 0); // 占位，DecodeNormal 在 InitLightingData 内处理

    // --- 参数贴图拆通道 (_P) ---
    float4 pTex    = SAMPLE_TEXTURE2D(_P, sampler_P, input.uv);
    float  metallic_raw   = pTex.r;    // R: Metallic
    float  ao_raw         = pTex.g;    // G: AO / directOcclusion
    float  smoothness_raw = pTex.b;    // B: Smoothness
    s.rampUV              = pTex.a;    // A: RampUV（Toon Ramp 行选择）

    // --- Metallic / AO ---
    s.metallic = metallic_raw * _MetallicMax;
    s.ao       = ao_raw;

    // --- Smoothness → perceptualRoughness → roughness（等向）---
    s.smoothness          = smoothness_raw * _SmoothnessMax;
    s.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(s.smoothness);
    s.roughness           = PerceptualRoughnessToRoughness(s.perceptualRoughness);

    // --- 各向异性 T 轴 ---
    float smoothnessT      = smoothness_raw * _Aniso_SmoothnessMaxT;
    s.perceptualRoughnessT = PerceptualSmoothnessToPerceptualRoughness(smoothnessT);
    s.roughnessT           = PerceptualRoughnessToRoughness(s.perceptualRoughnessT);

    // --- 各向异性 B 轴 ---
    float smoothnessB      = smoothness_raw * _Aniso_SmoothnessMaxB;
    s.perceptualRoughnessB = PerceptualSmoothnessToPerceptualRoughness(smoothnessB);
    s.roughnessB           = PerceptualRoughnessToRoughness(s.perceptualRoughnessB);

    // --- diffuseColor / fresnel0 ---
    s.diffuseColor = ComputeDiffuseColor(s.albedo, s.metallic);
    s.fresnel0     = ComputeFresnel0(s.albedo, s.metallic, float3(0.04, 0.04, 0.04));

    // --- 自发光 (_E.RGB) ---
    s.emission = SAMPLE_TEXTURE2D(_E, sampler_E, input.uv).rgb;

    return s;
}

// =============================================================================
// InitLightingData — 几何向量初始化
// 对应 PBRToonBase.hlsl: Frame.012
// =============================================================================
LightingData InitLightingData(Varyings input, SurfaceData sd)
{
    LightingData ld;

    // --- TBN 矩阵 ---
    float3 N_geo = normalize(input.normalWS);
    float3 T_geo = normalize(input.tangentWS);
    float3 B_geo = normalize(input.bitangentWS);
    float3x3 TBN = float3x3(T_geo, B_geo, N_geo);

    // --- N：世界空间法线（DecodeNormal 解码切线空间 XY）---
    float4 nTex = SAMPLE_TEXTURE2D(_N, sampler_N, input.uv);
    ld.N = (_UseNormalTex > 0.5)
         ? DecodeNormal(nTex.x, nTex.y, _NormalStrength, TBN)
         : N_geo;

    // --- V：视角方向 ---
    ld.V = normalize(-GetWorldSpaceViewDir(input.positionWS));

    // --- L：主光方向 + 颜色 + 阴影衰减 ---
    Light mainLight   = GetMainLight();
    ld.L              = normalize(mainLight.direction);
    ld.lightColor     = mainLight.color * mainLight.distanceAttenuation;
    ld.castShadow     = mainLight.shadowAttenuation;

    // --- 切线 / 副切线 ---
    ld.T = T_geo;
    ld.B = B_geo;

    // --- 基础点积 ---
    ld.NoV  = saturate(dot(ld.N, ld.V));
    ld.NoL  = dot(ld.N, ld.L);    // 允许负值
    ld.LoV  = dot(ld.L, ld.V);

    // --- 各向异性点积 ---
    ld.ToL   = dot(ld.T, ld.L);
    ld.BdotL = dot(ld.B, ld.L);
    ld.ToV   = dot(ld.T, ld.V);
    ld.BdotV = dot(ld.B, ld.V);

    // --- 半角点积（NoH / LdotH / TdotH / BdotH）---
    Get_NoH_LoH_ToH_BoH(
        ld.NoL, ld.NoV, ld.LoV,
        ld.ToV, ld.ToL, ld.BdotV, ld.BdotL,
        ld.NdotH, ld.LdotH, ld.TdotH, ld.BdotH);

    return ld;
}

// =============================================================================
// ComputeDiffuseDirect — Toon 漫反射直接光
// 对应 PBRToonBase.hlsl: Frame.005 + Frame.007(ShadowAdjust)
// =============================================================================
float3 ComputeDiffuseDirect(SurfaceData sd, LightingData ld)
{
    // selfShadow：halfLambert 重映射 + SigmoidSharp 锐化
    float halfLambert  = SigmoidSharp(ld.NoL, _RemaphalfLambert_center, _RemaphalfLambert_sharp);

    // castShadow：投射阴影 × halfLambert → SigmoidSharp → shadowFactor
    float shadowFactor = SigmoidSharp(halfLambert * ld.castShadow, _CastShadow_center, _CastShadow_sharp);

    // ShadowAdjust：全局阴影亮度调整，作用于漫反射暗部（Frame.007 前移至此）
    float shadowAdj        = SmoothStepCustom(0.0, 1.0, _GlobalShadowBrightnessAdjustment);
    float shadowBrightness = lerp(shadowAdj, 1.0, shadowFactor);

    // Toon Ramp：shadowFactor 驱动 Ramp U 轴，rampUV 选行（RampIndex）
    float3 rampCurrent; float rampA;
    RampSelect(shadowFactor, _RampIndex, rampCurrent, rampA);

    // directLighting_diffuse：漫反射合色（含 AO directOcclusion）
    float3 directOcclusion = lerp(_directOcclusionColor.rgb, 1.0, sd.ao);
    float3 lightFactor     = ld.lightColor * _dirLight_lightColor.rgb;
    float3 diffuseDirect   = DirectLightingDiffuse(rampCurrent, directOcclusion, sd.diffuseColor, lightFactor);

    // DeSaturation：暗部去饱和（Toon 压色，阴影区强度最大）
    diffuseDirect = DeSaturation(_ColorDesaturationAttenuation * (1.0 - shadowFactor), diffuseDirect);

    // 应用 ShadowAdjust
    return diffuseDirect * shadowBrightness;
}

// =============================================================================
// ComputeSpecularDirect — 各向异性 GGX 高光直接光
// 对应 PBRToonBase.hlsl: Frame.004
// =============================================================================
float3 ComputeSpecularDirect(SurfaceData sd, LightingData ld)
{
    float absNdotL = saturate(ld.NoL);

    // DV_ISO / DV_ANISO：等向 & 各向异性 GGX 分布 × Visibility 项
    float DV_ISO, DV_ANISO;
    DV_SmithJointGGX_Aniso(
        ld.NdotH, absNdotL, ld.NoV, max(sd.roughness, 0.001),
        ld.TdotH, ld.BdotH, ld.ToL, ld.BdotL,
        ld.ToV, ld.BdotV, sd.roughnessT, sd.roughnessB,
        DV_ISO, DV_ANISO);

    // 等向 / 各向异性开关（UseAnisotropy → UseToonAniso）
    float dv = (_UseAnisotropy > 0.5) ? DV_ANISO : DV_ISO;
    dv       = (_UseToonAniso  > 0.5) ? DV_ANISO : dv;

    // F_Schlick + 高光项：DV × F × NoL × π × lightColor
    float3 F = F_Schlick(sd.fresnel0, float3(1, 1, 1), ld.LdotH);
    return F * dv * absNdotL * PI * _SpecularColor.rgb * ld.lightColor;
}

// =============================================================================
// ComputeRimLight — 屏幕空间深度边缘光
// 对应 PBRToonBase.hlsl: Frame.009
// =============================================================================
float3 ComputeRimLight(SurfaceData sd, LightingData ld, float2 screenUV)
{
    float3 normalVS = float3(ld.N.x, ld.N.y, 0); // 概念性视空间法线 XY

    // ① DepthRim：屏幕空间深度差遮罩
    float rimDepthMask    = DepthRim(screenUV, normalVS, _Rim_width_X, _Rim_width_Y);

    // ② FresnelAttenuation：(1 - NoV)^4 Fresnel 遮罩
    float rimFresnelMask  = FresnelAttenuation(ld.NoV);

    // VerticalAttenuation：法线垂直分量遮罩
    float rimVerticalMask = VerticalAttenuation(ld.N);

    // 三路遮罩 × 光源方向调制
    float rimMask      = rimDepthMask * rimFresnelMask * rimVerticalMask;
    float rimDirAtten  = DirectionalLightAttenuation(ld.NoL, _Rim_DirLightAtten);

    // Rim_Color 合色 → ADD
    float3 rimColor = RimColor(sd.albedo, ld.lightColor, _Rim_Color.rgb, _Rim_ColorStrength, ld.LoV);
    return rimColor * rimMask * rimDirAtten;
}

// =============================================================================
// ComputeIndirectLighting — 间接漫反射 + 间接高光
// 对应 PBRToonBase.hlsl: Frame.006
// =============================================================================
float3 ComputeIndirectLighting(SurfaceData sd, LightingData ld)
{
    float3 specularFGD;
    float  diffuseFGD, reflectivity;
    GetPreIntegratedFGD(ld.NoV, sd.perceptualRoughness, sd.fresnel0,
                        specularFGD, diffuseFGD, reflectivity);

    // 间接漫反射：diffuseColor × diffuseFGD × ambientTint
    float3 indirectDiffuse  = sd.diffuseColor * diffuseFGD * _AmbientLightColorTint.rgb;

    // 间接高光：specularFGD × strength（概念性；完整实现需反射探针/SkyBox）
    float3 indirectSpecular = specularFGD * _specularFGDStrength;

    return indirectDiffuse + indirectSpecular;
}

// =============================================================================
// ApplyToonFresnel — Toon 边缘色 MULTIPLY 修饰层（ADD 叠加）
// 对应 PBRToonBase.hlsl: Frame.008
// =============================================================================
float3 ApplyToonFresnel(float3 color, LightingData ld)
{
    float factor = pow(1.0 - ld.NoV, _ToonfresnelPow);
    factor = SmoothStepCustom(_ToonfresnelSMO_L, _ToonfresnelSMO_H, factor);
    float  layerWeight = saturate(factor * _LayerWeightValue + _LayerWeightValueOffset);
    float3 fresnelColor = lerp(_fresnelInsideColor.rgb, _fresnelOutsideColor.rgb, layerWeight);
    return color + fresnelColor * layerWeight;
}

// =============================================================================
// ApplyThinFilmFilter — RS 彩虹/光泽特效（条件 ADD）
// 对应 PBRToonBase.hlsl: Frame.011
// =============================================================================
float3 ApplyThinFilmFilter(float3 color, SurfaceData sd, LightingData ld, float2 uv)
{
    if (_UseRSEff <= 0.5) return color;

    // Step 1: LAYER_WEIGHT Facing ≈ pow(1 − NdotV, 1 / _LayerWeightValue)
    // _LayerWeightValue 为 Blender LAYER_WEIGHT 的 Blend 陡峭度参数（约 0.9）
    float facing = pow(saturate(1.0 - saturate(dot(ld.N, ld.V))),
                       1.0 / max(_LayerWeightValue, 0.001));

    // Step 2: Facing 偏移 + 钳制（运算.004 ADD → 钳制.001 CLAMP）
    float facingAdj = saturate(facing + _LayerWeightValueOffset);

    // Step 3: RS 贴图 UV — U=facingAdj，V 固定 0.5（合并 XYZ.004）
    float2 rsUV = float2(facingAdj, 0.5);

    // Step 4: 采样双 RS 贴图并按 RS_Index 混合（混合.032 MIX）
    float3 rsColorA = SAMPLE_TEXTURE2D(_RS_Tex_A, sampler_RS_Tex_A, rsUV).rgb;
    float3 rsColorB = SAMPLE_TEXTURE2D(_RS_Tex_B, sampler_RS_Tex_B, rsUV).rgb;
    float3 rsMixed  = lerp(rsColorA, rsColorB, _RS_Index);

    // Step 5: 色调 × 强度（混合.036 × 混合.023）
    rsMixed = rsMixed * _RS_ColorTint.rgb * _RS_Strength;

    // Step 6: 光照调制（Fresnel 路径）—— 混合.027 × clampedNdotL，混合.028 × shadowScene
    // shadowScene 理论上来自 Frame.005 DiffuseBRDF（RampSelect 明度输出），
    // 此处以 castShadow 近似（伪代码级）
    float clampedNdotL = saturate(ld.NoL);
    float shadowScene  = ld.castShadow;
    float3 rsLit = rsMixed * clampedNdotL * shadowScene;

    // Step 7: 双路径分叉（RS_Model 开关）
    float3 rsMask = SAMPLE_TEXTURE2D(_M, sampler_M, uv).rgb;
    float3 pathA = rsLit  * rsMask;              // Fresnel 路径（RS_Model=0）：受光照 × _M 遮罩
    float3 pathB = rsMask * _RS_ColorTint.rgb;   // Model   路径（RS_Model=1）：_M × ColorTint，不受光照

    // Step 8: RS_Model lerp 选路 → 帧.048 RS EFF 近似 ADD 叠入
    float3 thinFilmColor = lerp(pathA, pathB, _RSModel);
    return color + thinFilmColor;
}

// =============================================================================
// ApplySimpleTransmission — 背光透射（条件 ADD）
// 对应 PBRToonBase.hlsl: 框.069
// =============================================================================
float3 ApplySimpleTransmission(float3 color, SurfaceData sd, LightingData ld)
{
    if (_UseSimpleTransmission <= 0.5) return color;

    float transmissionFactor = saturate(-ld.NoL) * _SimpleTransmissionValue;
    return color + sd.albedo * ld.lightColor * transmissionFactor;
}

// =============================================================================
// 主片元函数 — 调用骨架
// =============================================================================
float4 PBRToonTest_Frag(Varyings input) : SV_Target
{
    // 1. 表面数据 + 光照初始化
    SurfaceData  sd = GetSurfaceData(input);
    LightingData ld = InitLightingData(input, sd);

    // 2. 直接光
    float2 screenUV    = input.screenPos.xy / input.screenPos.w;
    float3 directLight = ComputeDiffuseDirect(sd, ld)
                       + ComputeSpecularDirect(sd, ld)
                       + ComputeRimLight(sd, ld, screenUV);

    // 3. 间接光
    float3 indirectLight = ComputeIndirectLighting(sd, ld);

    // 4. 累加 + 自发光
    float3 color = directLight + indirectLight + sd.emission;

    // 5. 修饰层（可选）
    color = ApplyToonFresnel(color, ld);
    color = ApplyThinFilmFilter(color, sd, ld, input.uv);
    color = ApplySimpleTransmission(color, sd, ld);

    // 6. Alpha 输出
    return float4(color, sd.alpha * _Alpha);
}

// =============================================================================
// 顶点函数 — 坐标变换 / UV / 法线切线传递
// 对应 PBRToonBase.hlsl: PBRToonBase_Vert（仅改函数名）
// =============================================================================
Varyings PBRToonTest_Vert(Attributes input)
{
    Varyings output;

    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    output.positionCS  = posInputs.positionCS;
    output.positionWS  = posInputs.positionWS;
    output.screenPos   = ComputeScreenPos(posInputs.positionCS);

    output.uv = TRANSFORM_TEX(input.uv, _D);

    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    output.normalWS    = normInputs.normalWS;
    output.tangentWS   = normInputs.tangentWS;
    output.bitangentWS = normInputs.bitangentWS;

    return output;
}

#endif // PBRTOONTEST_MAIN_INCLUDED
