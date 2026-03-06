// =============================================================================
// PBRToonBaseFace.hlsl
// 主 Shader 函数 — 按逻辑模块顺序组装面部渲染管线
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md
// 注：本文件为伪代码级 HLSL，供理解渲染流程使用，非可直接编译版本
// =============================================================================

#ifndef PBRTOONBASEFACE_MAIN_INCLUDED
#define PBRTOONBASEFACE_MAIN_INCLUDED

#include "PBRToonBaseFace_Input.hlsl"
#include "SubGroups/SubGroups.hlsl"

#ifndef PI
#define PI 3.14159265358979323846
#endif

// =============================================================================
// Module 2 — GetSurfaceData（贴图采样 + 表面参数计算）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-2
// =============================================================================
SurfaceData GetSurfaceData(Varyings input)
{
    SurfaceData s;

    // --- 帧.albedo ---
    // Face 的 _D 通过 Group Input 传入 RGB 和 A
    s.albedo = _D_RGB;  // 伪代码：来自群组输入 _D(sRGB)R.G.B
    s.alpha  = _D_A;    // 伪代码：来自群组输入 _D(sRGB).A

    // --- 参数贴图拆通道 ---
    // Face 中 _P 贴图在群组内部采样
    float4 pTex = SAMPLE_TEXTURE2D(_P, sampler_P, input.uv);
    float metallic_raw   = pTex.r;    // 帧.metallic
    float ao_raw         = pTex.g;    // 帧.030 directOcclusion
    float smoothness_raw = pTex.b;

    // --- metallic / AO ---
    s.metallic  = metallic_raw * _MetallicMax;
    s.ao        = ao_raw;

    // --- Smoothness → perceptualRoughness → roughness ---
    s.smoothness          = smoothness_raw * _SmoothnessMax;
    s.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(s.smoothness);
    s.roughness           = PerceptualRoughnessToRoughness(s.perceptualRoughness);

    // --- diffuseColor / fresnel0 ---
    s.diffuseColor = ComputeDiffuseColor(s.albedo, s.metallic);
    s.fresnel0     = ComputeFresnel0(s.albedo, s.metallic, float3(0.04, 0.04, 0.04));

    // --- SDF / 下巴遮罩 / 高光遮罩 ---
    // SDF 贴图采样需要 AngleThreshold 作为 UV，在 SDFShadow 函数中完成
    s.sdfValue      = 0.0; // 占位，实际在 SDFShadow 中采样
    s.chinMask      = SAMPLE_TEXTURE2D(_ChinMask, sampler_ChinMask, input.uv).r;
    s.highlightMask = SAMPLE_TEXTURE2D(_HighlightMask, sampler_HighlightMask, input.uv).r;

    return s;
}

// =============================================================================
// Module 1 — InitLightingData（几何向量初始化）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-1
// 核心差异：Recalculate normal 替代 DecodeNormal
// =============================================================================
LightingData InitLightingData(Varyings input, SurfaceData sd)
{
    LightingData ld;

    // --- 帧.002 N：球面法线重映射（Recalculate normal）---
    float3 N_geo = normalize(input.normalWS);
    ld.N = RecalculateNormal(
        _sphereNormal_Strength,
        input.headCenter,
        input.positionWS,
        N_geo,
        sd.chinMask
    );

    // --- 帧.003 V：视角方向（Incoming 取反）---
    ld.V = normalize(_WorldSpaceCameraPos - input.positionWS);

    // --- 帧.020 L：主光方向 ---
    // 面部使用骨骼写入的 LightDirection 或 SHADERINFO
    Light mainLight = GetMainLight();
    ld.L = normalize(mainLight.direction);
    ld.lightColor   = mainLight.color * mainLight.distanceAttenuation;
    ld.castShadow   = mainLight.shadowAttenuation;

    // --- 基础点积 ---
    ld.NoV = saturate(dot(ld.N, ld.V));     // 帧.004 NoV → 帧.005 ClampNdotV
    ld.NoL = dot(ld.N, ld.L);               // 帧.NoL_Unsaturate
    ld.LoV = dot(ld.L, ld.V);               // 帧.021 LoV

    // --- 半角点积（Get_NoH_LoH_ToH_BoH）---
    // 面部无各向异性，TdotH/BdotH 忽略
    float TdotH_unused, BdotH_unused;
    Get_NoH_LoH_ToH_BoH(
        ld.NoL, ld.NoV, ld.LoV,
        0.0, 0.0, 0.0, 0.0,   // T/B 点积全部置零
        ld.NdotH, ld.LdotH, TdotH_unused, BdotH_unused);

    return ld;
}

// =============================================================================
// Module 3 — SDFShadow（SDF 面部阴影系统）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-3
// 节点：calculateAngel / SDF 贴图采样 / SigmoidSharp ×3 / 下巴阴影 / 投影阴影
// =============================================================================
float SDFShadow(Varyings input, LightingData ld, SurfaceData sd)
{
    // ── 帧.AngelUV / 帧.AngleThreshold ──────────────────────────────────────
    // calculateAngel：计算光源相对头部的水平方位角
    AngleThresholdResult angleResult = CalculateAngleThreshold(
        input.lightDir,     // 骨骼写入的 LightDirection
        input.headUp,
        input.headRight,
        input.headForward
    );

    // ── 帧.SDFShadow ────────────────────────────────────────────────────────
    // SDF 贴图采样：U = AngleThreshold, V = 固定（翻转处理）
    float flipSign = angleResult.FlipThreshold > 0.0 ? 1.0 : -1.0;
    float sdfU = angleResult.AngleThreshold;
    // 根据 FlipThreshold 翻转 SDF UV（面部左右对称）
    float2 sdfUV = float2(sdfU, 0.5);
    float sdfRaw = SAMPLE_TEXTURE2D(_SDF, sampler_SDF, sdfUV).r;

    // SDF 值通过 SigmoidSharp 锐化
    float sdfShadow = SigmoidSharp(sdfRaw,
                                    _SDF_RemaphalfLambert_center,
                                    _SDF_RemaphalfLambert_sharp);

    // ── 帧.chinLambertShaodow ────────────────────────────────────────────────
    // 下巴区域使用独立的 Lambert 阴影
    float chinShadow = SigmoidSharp(ld.NoL,
                                     _chin_RemaphalfLambert_center,
                                     _chin_RemaphalfLambert_sharp);

    // 通过 ChinMask 混合：ChinMask=0 使用 SDF 阴影，ChinMask=1 使用下巴 Lambert 阴影
    float faceShadow = lerp(sdfShadow, chinShadow, sd.chinMask);

    // ── 帧.shadowScene ───────────────────────────────────────────────────────
    // 投影阴影独立 SigmoidSharp
    float shadowScene = SigmoidSharp(ld.castShadow,
                                      _CastShadow_center,
                                      _CastShadow_sharp);

    // ── 帧.shadowArea ────────────────────────────────────────────────────────
    // 双路阴影取暗合并
    float shadowArea = min(faceShadow, shadowScene);

    return shadowArea;
}

// =============================================================================
// Module 4 — DiffuseBRDF（Toon 漫反射 + 鼻影）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-4
// =============================================================================
float3 DiffuseBRDF(SurfaceData sd, LightingData ld, float shadowArea)
{
    // ── 帧.032 shadowRampColor ───────────────────────────────────────────────
    // Ramp 贴图采样：U = shadowArea（阴影强度），V = 固定行
    float2 rampUV = float2(shadowArea, 0.5);
    float3 rampColor = SAMPLE_TEXTURE2D(_RampLUT, sampler_RampLUT, rampUV).rgb;

    // ── 帧.033 directLighting_diffuse ────────────────────────────────────────
    float3 directOcclusion = float3(sd.ao, sd.ao, sd.ao);
    float3 diffuseDirect = DirectLightingDiffuse(rampColor, directOcclusion,
                                                  sd.diffuseColor,
                                                  _dirLight_lightColor.rgb);

    // ── nose shadow color 叠加 ───────────────────────────────────────────────
    // 鼻影颜色通过阴影区域加权叠加
    float noseShadowFactor = 1.0 - shadowArea; // 阴影越深鼻影越明显
    diffuseDirect += _nose_shadow_Color.rgb * noseShadowFactor * sd.ao;

    return diffuseDirect;
}

// =============================================================================
// Module 5 — SpecularBRDF（各向同性 GGX 高光）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-5
// 与 Cloth 版差异：仅各向同性，无 T/B 分离
// =============================================================================
float3 SpecularBRDF(SurfaceData sd, LightingData ld)
{
    float clampedRoughness = max(sd.roughness, 0.001);
    float absNdotL = abs(ld.NoL);

    // ── 帧.026 DV ───────────────────────────────────────────────────────────
    // 仅使用各向同性输出
    float dvIsotropic, dvAnisotropic_unused;
    DV_SmithJointGGX_Aniso(
        ld.NdotH, absNdotL, ld.NoV, clampedRoughness,
        0.0, 0.0, 0.0, 0.0,       // TdotH, BdotH, TdotL, BdotL = 0
        0.0, 0.0,                   // TdotV, BdotV = 0
        clampedRoughness, clampedRoughness,  // roughnessT = roughnessB = roughness
        dvIsotropic, dvAnisotropic_unused);

    // ── 帧.027 F ─────────────────────────────────────────────────────────────
    float3 F = F_Schlick(sd.fresnel0, float3(1, 1, 1), ld.LdotH);

    // ── 帧.028 specTerm ──────────────────────────────────────────────────────
    float3 specTerm = F * dvIsotropic;

    // ── 帧.034 directLighting_specular ───────────────────────────────────────
    // 面部使用 SpecularColor（HDR）调制高光
    float3 specularColor = specTerm * _SpecularColor.rgb * ld.lightColor;

    return specularColor;
}

// =============================================================================
// Module 6 — IndirectLighting（间接光照 + 能量补偿）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-6
// 与 Cloth 版流程一致
// =============================================================================
float3 IndirectLighting(SurfaceData sd, LightingData ld,
                        float3 directSpecular, float3 directDiffuse)
{
    // Stage 1: FGD LUT 查询
    float3 specularFGD;
    float  diffuseFGD, reflectivity;
    GetPreIntegratedFGD(ld.NoV, sd.perceptualRoughness, sd.fresnel0,
                        specularFGD, diffuseFGD, reflectivity);

    // Stage 2: 帧.035 energyCompensation
    float invR     = 1.0 / max(reflectivity, 1e-4);
    float ecFactor = invR - 1.0;

    // Stage 3A: energyCompFactor 修正 directSpecular
    float3 energyCompFactor  = sd.fresnel0 * ecFactor + float3(1, 1, 1);
    float3 correctedSpecular = directSpecular * energyCompFactor;

    // Stage 3B: directLighting 合并
    float3 directLighting = correctedSpecular + directDiffuse;

    // Stage 4: 帧.038 间接镜面能量补偿
    float3 weightedSpecFGD  = specularFGD * _specularFGDStrength;
    float3 indirectSpecComp = ecFactor * weightedSpecFGD;

    // Stage 5: 帧.036 ambientCombined
    // Unity URP：替换为 SampleSH(normalWS) 或 unity_AmbientSky.rgb
    float3 ambientCombined = _AmbientLightColorTint.rgb * _AmbientLighting;

    // Stage 6: 间接漫反射
    float3 indirectDiffuse = sd.diffuseColor * diffuseFGD * ambientCombined;

    // Stage 7: 汇合
    float3 totalSpecular = directLighting + indirectSpecComp;
    return totalSpecular + indirectDiffuse;
}

// =============================================================================
// Module 7 — FaceEffects（面部特效）
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md#module-7
// =============================================================================

// -------------------------------------------------------------------------
// 帧.040 — 屏幕空间 Rim（概念性实现）
// 注：SCREENSPACEINFO 为 Goo Engine 专有；Unity 需自定义实现
// -------------------------------------------------------------------------
float3 FaceScreenSpaceRim(LightingData ld, Varyings input)
{
    // 概念性：使用屏幕空间信息检测面部轮廓边缘
    // Goo Engine 中通过 SCREENSPACEINFO 节点获取屏幕空间法线/深度差
    // Unity URP 替换方案：
    //   1. 使用 _CameraDepthTexture 做深度差边缘检测
    //   2. 或使用 _CameraOpaqueTexture 做颜色差边缘检测

    float2 screenUV = input.screenPos.xy / input.screenPos.w;

    // 简化 Rim 遮罩计算（概念性）
    float rimFresnel = pow(1.0 - ld.NoV, 4.0);
    float rimMask    = rimFresnel * 0.5;

    return _Rim_Color.rgb * rimMask;
}

// -------------------------------------------------------------------------
// 帧.041 — 高光贴图叠加
// -------------------------------------------------------------------------
float3 FaceHighlightOverlay(SurfaceData sd, float3 color)
{
    // 使用 hl_M 高光遮罩贴图叠加面部高光细节
    return color + sd.highlightMask * _LipsHighlightColor.rgb;
}

// -------------------------------------------------------------------------
// Front transparent red（SSS 近似）
// -------------------------------------------------------------------------
float4 FaceFrontTransparentRed(SurfaceData sd, LightingData ld)
{
    // Positive attenuation = 正面朝向因子
    float positiveAttenuation = saturate(dot(ld.N, ld.V));

    return FrontTransparentRed(
        _FrontRSmo,
        positiveAttenuation,
        _FrontRColor,
        sd.albedo.r,    // D_R = Diffuse 红通道
        _FrontRPow
    );
}

// =============================================================================
// 主片元函数（Fragment Shader）
// 按逻辑模块顺序逐步组装最终颜色
// =============================================================================
float4 PBRToonBaseFace_Frag(Varyings input) : SV_Target
{
    // ── Module 2: GetSurfaceData ─────────────────────────────────────────────
    SurfaceData sd = GetSurfaceData(input);

    // ── Module 1: InitLightingData ───────────────────────────────────────────
    LightingData ld = InitLightingData(input, sd);

    // ── Module 3: SDFShadow ──────────────────────────────────────────────────
    float shadowArea = SDFShadow(input, ld, sd);

    // ── Module 4: DiffuseBRDF ────────────────────────────────────────────────
    float3 directDiffuse = DiffuseBRDF(sd, ld, shadowArea);

    // ── GlobalShadowBrightnessAdjustment ─────────────────────────────────────
    float shadowAdj = SmoothStepCustom(0.0, 1.0, _GlobalShadowBrightnessAdjustment);
    directDiffuse *= lerp(shadowAdj, 1.0, shadowArea);

    // ── DeSaturation（阴影区域去饱和）────────────────────────────────────────
    float desatFactor = (1.0 - shadowArea) * _ColorDesaturationAttenuation;
    directDiffuse = DeSaturation(desatFactor, directDiffuse);

    // ── Module 5: SpecularBRDF ───────────────────────────────────────────────
    float3 directSpecular = SpecularBRDF(sd, ld);

    // ── Module 6: IndirectLighting ───────────────────────────────────────────
    float3 color = IndirectLighting(sd, ld, directSpecular, directDiffuse);

    // ── Module 7: FaceEffects ────────────────────────────────────────────────

    // Front transparent red（SSS 近似）
    float4 frontRed = FaceFrontTransparentRed(sd, ld);
    color += frontRed.rgb;

    // 屏幕空间 Rim（帧.040）
    color += FaceScreenSpaceRim(ld, input);

    // 高光贴图叠加（帧.041）
    color = FaceHighlightOverlay(sd, color);

    // ── Module 8: FinalComposite ─────────────────────────────────────────────

    // Face Final brightness 亮度倍率
    color *= _FaceFinalBrightness;

    // Eyes white brightness（概念性：需要眼白区域遮罩驱动）
    // color = lerp(color, color * _EyesWhiteFinalBrightness, eyeWhiteMask);

    // ── Alpha ────────────────────────────────────────────────────────────────
    return float4(color, sd.alpha);
}

// =============================================================================
// 顶点函数（Vertex Shader）
// 负责变换坐标 + 传递 UV / 法线 / posWS / 骨骼属性
// =============================================================================
Varyings PBRToonBaseFace_Vert(Attributes input)
{
    Varyings output;

    // 坐标变换（URP 宏）
    VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS);
    output.positionCS  = posInputs.positionCS;
    output.positionWS  = posInputs.positionWS;
    output.screenPos   = ComputeScreenPos(posInputs.positionCS);

    // UV
    output.uv = TRANSFORM_TEX(input.uv, _D);

    // 法线（世界空间，面部无切线/副切线需求）
    VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    output.normalWS = normInputs.normalWS;

    // 骨骼属性（伪代码：通过 MaterialPropertyBlock 或自定义 attribute 传入）
    // Unity 中需要 C# 脚本每帧写入骨骼数据
    output.headCenter  = _HeadCenter;   // 从 MaterialPropertyBlock 读取
    output.headUp      = _HeadUp;
    output.headRight   = _HeadRight;
    output.headForward = _HeadForward;
    output.lightDir    = _LightDirection;

    return output;
}

#endif // PBRTOONBASEFACE_MAIN_INCLUDED
