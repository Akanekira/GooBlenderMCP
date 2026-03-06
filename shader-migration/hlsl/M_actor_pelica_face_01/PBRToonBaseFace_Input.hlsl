// =============================================================================
// PBRToonBaseFace_Input.hlsl
// 输入结构体、贴图声明、材质属性
// 对应 Blender 材质 M_actor_pelica_face_01 的顶层接口
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/00_material_overview.md
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#ifndef PBRTOONBASEFACE_INPUT_INCLUDED
#define PBRTOONBASEFACE_INPUT_INCLUDED

// -----------------------------------------------------------------------------
// 贴图声明
// -----------------------------------------------------------------------------

// _D : Diffuse/Albedo (sRGB)  RGB=颜色 A=Alpha
TEXTURE2D(_D);          SAMPLER(sampler_D);

// _P : 参数贴图 (Non-Color)
//   R = Metallic
//   G = AO / directOcclusion
//   B = Smoothness
//   A = （Face 中未使用 RampUV，阴影由 SDF 驱动）
TEXTURE2D(_P);          SAMPLER(sampler_P);

// SDF 面部阴影方向贴图 (Non-Color)
// 对应 T_actor_common_female_face_01_SDF.png
TEXTURE2D(_SDF);        SAMPLER(sampler_SDF);

// 下巴遮罩 (Non-Color)
// 对应 T_actor_common_female_face_01_cm_M.png
TEXTURE2D(_ChinMask);   SAMPLER(sampler_ChinMask);

// 面部高光遮罩 (Non-Color)
// 对应 T_actor_common_face_01_hl_M.png（帧.041）
TEXTURE2D(_HighlightMask); SAMPLER(sampler_HighlightMask);

// Ramp/Diffuse 色带
// 对应 T_actor_common_face_01_RD.png
TEXTURE2D(_RampLUT);    SAMPLER(sampler_RampLUT);

// 预积分 FGD LUT（GGX + Disney Diffuse）
// 对应 GetPreIntegratedFGDGGXAndDisneyDiffuse 内嵌贴图
TEXTURE2D(_FGD_LUT);    SAMPLER(sampler_FGD_LUT);

// 自定义遮罩（帧.040 屏幕空间 Rim 用）
// 对应 CsutmMask
TEXTURE2D(_CustomMask);  SAMPLER(sampler_CustomMask);
TEXTURE2D(_CustomMask2); SAMPLER(sampler_CustomMask2);

// URP 深度贴图（屏幕空间效果使用）
TEXTURE2D(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

// URP 不透明贴图（屏幕空间 Rim 使用）
TEXTURE2D(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture);

// -----------------------------------------------------------------------------
// 材质属性（对应群组 24 个接口输入）
// -----------------------------------------------------------------------------

// --- 粗糙度/金属度 ---
float _SmoothnessMax;
float _MetallicMax;

// --- 阴影 / SDF ---
float _SDF_RemaphalfLambert_center;     // SDF 阴影 SigmoidSharp 中心值 (0.57)
float _SDF_RemaphalfLambert_sharp;      // SDF 阴影 SigmoidSharp 锐度 (0.16)
float _chin_RemaphalfLambert_center;    // 下巴阴影 SigmoidSharp 中心值
float _chin_RemaphalfLambert_sharp;     // 下巴阴影 SigmoidSharp 锐度
float _CastShadow_center;              // 投射阴影 SigmoidSharp 中心值
float _CastShadow_sharp;               // 投射阴影 SigmoidSharp 锐度
float _GlobalShadowBrightnessAdjustment;
float _ColorDesaturationAttenuation;    // 阴影区域去饱和衰减

// --- 光照 ---
float4 _dirLight_lightColor;
float4 _AmbientLightColorTint;

// --- 高光 ---
float4 _SpecularColor;                  // HDR 高光颜色 (3.0, 1.46, 1.34, 1)

// --- 面部特有 ---
float _sphereNormal_Strength;           // 球面法线混合强度
float4 _FrontRColor;                    // 前向透红颜色（SSS 近似）
float _FrontRPow;                       // 透红衰减指数 (默认 2.0)
float _FrontRSmo;                       // 透红 SmoothStep 上限
float4 _nose_shadow_Color;              // 鼻影颜色
float _FaceFinalBrightness;             // 面部最终亮度倍率 (默认 1.15)
float _EyesWhiteFinalBrightness;        // 眼白亮度倍率 (默认 1.3)
float4 _LipsHighlightColor;            // 唇部高光颜色
float4 _Rim_Color;                      // 边缘光颜色

// --- 间接光照 ---
float _specularFGDStrength;

// -----------------------------------------------------------------------------
// 顶点输出 / 片元输入结构体
// -----------------------------------------------------------------------------

struct Varyings
{
    float4 positionCS   : SV_POSITION;
    float2 uv           : TEXCOORD0;
    float3 normalWS     : TEXCOORD1;
    float3 positionWS   : TEXCOORD2;
    float4 screenPos    : TEXCOORD3;    // 供屏幕空间效果使用

    // 骨骼属性（通过顶点 attribute 或 MaterialPropertyBlock 传入）
    float3 headCenter   : TEXCOORD4;    // 头部中心世界坐标
    float3 headUp       : TEXCOORD5;    // 头部上方轴
    float3 headRight    : TEXCOORD6;    // 头部右方轴
    float3 headForward  : TEXCOORD7;    // 头部前向轴
    float3 lightDir     : TEXCOORD8;    // 自定义光方向（骨骼写入）
};

// -----------------------------------------------------------------------------
// 表面数据中间结构（GetSurfaceData 输出）
// -----------------------------------------------------------------------------

struct SurfaceData
{
    // 来自贴图
    float3 albedo;          // _D.RGB
    float  alpha;           // _D.A
    float  metallic;        // _P.R × MetallicMax
    float  ao;              // _P.G (directOcclusion)
    float  smoothness;      // _P.B × SmoothnessMax

    // 计算得出
    float3 diffuseColor;    // albedo × (1 - metallic)
    float3 fresnel0;        // lerp(0.04, albedo, metallic)
    float  perceptualRoughness;
    float  roughness;

    // SDF 相关
    float  sdfValue;        // SDF 贴图采样值
    float  chinMask;        // 下巴遮罩值
    float  highlightMask;   // 高光遮罩值
};

// -----------------------------------------------------------------------------
// 光照数据中间结构（Init 输出）
// -----------------------------------------------------------------------------

struct LightingData
{
    float3 N;       // 法线（世界空间，球面法线重映射后）
    float3 V;       // 视角方向
    float3 L;       // 光方向

    float NoV;      // dot(N, V), clamped
    float NoL;      // dot(N, L), unsaturated
    float LoV;      // dot(L, V)

    // 半角点积（Get_NoH_LoH_ToH_BoH，面部无各向异性 → TdotH/BdotH 忽略）
    float NdotH, LdotH;

    // 来自 SHADERINFO（URP 侧用 MainLight）
    float3 lightColor;
    float  castShadow;      // 投影阴影值
};

#endif // PBRTOONBASEFACE_INPUT_INCLUDED
