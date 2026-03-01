// =============================================================================
// PBRToonBaseHair_Input.hlsl
// 贴图声明 + 材质属性 + 顶点/表面/光照数据结构体
// 溯源：docs/analysis/M_actor_laevat_hair_01/00_material_overview.md
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#ifndef PBRTOONBASEHAIR_INPUT_INCLUDED
#define PBRTOONBASEHAIR_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// -----------------------------------------------------------------------------
// 贴图声明
// -----------------------------------------------------------------------------

// _D: Diffuse / Albedo (sRGB)
//   RGB = 发丝颜色  A = Alpha
TEXTURE2D(_D);          SAMPLER(sampler_D);

// _HN: Hair Normal (Non-Color)
//   RGB = 发丝切线法线方向（各向异性方向编码）  A = 保留
TEXTURE2D(_HN);         SAMPLER(sampler_HN);

// _P: PBR 参数 (Non-Color)
//   R = Metallic  G = AO/directOcclusion  B = Smoothness  A = RampUV/保留
TEXTURE2D(_P);          SAMPLER(sampler_P);

// 内嵌 Ramp 贴图（发丝阴影 Ramp 查找表，在 Frame.007 内部直接采样）
TEXTURE2D(_HairRampTex); SAMPLER(sampler_HairRampTex);
// 实际文件：T_actor_common_hair_01_RD.png

// DepthRim 所需深度图（URP 相机深度，供 DepthRim 子群组采样）
TEXTURE2D(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

// FGD 预积分贴图（GetPreIntegratedFGDGGXAndDisneyDiffuse 所需）
TEXTURE2D(_FGDTexture);  SAMPLER(sampler_FGDTexture);

// -----------------------------------------------------------------------------
// 材质属性 CBUFFER
// -----------------------------------------------------------------------------

CBUFFER_START(UnityPerMaterial)

    // [Header(Textures)] — 在 Unity 中由 ShaderLab Properties 传入，此处对应接口

    // [Header(Base Color)]
    float4 _BaseColor;                  // BaseColor
    float4 _FusionFaceColor;            // Fusion face color
    float  _UseFusionFaceColor;         // Use Fusion face color? (0/1)

    // [Header(Roughness Metallic)]
    float  _SmoothnessMax;              // SmoothnessMax
    float  _MetallicMax;                // MetallicMax

    // [Header(Normal)]
    float  _NormalStrength;             // NormalStrength
    float  _HNormalStrength;            // HNormalStrength（发丝切线法线强度）

    // [Header(Shadow Diffuse)]
    float  _RemapHalfLambertCenter;     // RemaphalfLambert_center
    float  _RemapHalfLambertSharp;      // RemaphalfLambert_sharp
    float  _CastShadowCenter;           // CastShadow_center
    float  _CastShadowSharp;            // CastShadow_sharp
    float  _GlobalShadowBrightness;     // GlobalShadowBrightnessAdjustment
    float4 _DirectOcclusionColor;       // directOcclusionColor
    float  _ColorDesatInShadow;         // Color desaturation in shaded areas attenuation

    // [Header(Specular)]
    float4 _SpecularColor;              // SpecularColor
    float4 _DirLightColor;              // dirLight_lightColor

    // [Header(Fresnel ToonFresnel)]
    float4 _FresnelInsideColor;         // fresnelInsideColor
    float4 _FresnelOutsideColor;        // fresnelOutsideColor
    float  _ToonFresnelPow;             // ToonfresnelPow
    float  _ToonFresnelSMO_L;           // _ToonfresnelSMO_L
    float  _ToonFresnelSMO_H;           // _ToonfresnelSMO_H

    // [Header(Rim Light)]
    float4 _RimColor;                   // Rim_Color
    float  _RimColorStrength;           // Rim_ColorStrength
    float  _RimDirLightAtten;           // Rim_DirLightAtten
    float  _RimWidthX;                  // Rim_width_X
    float  _RimWidthY;                  // Rim_width_Y
    float  _UseRimLimitation;           // Use Rimlimitation? (0/1)

    // [Header(Hair Anisotropic Highlight)]
    float4 _HighLightColorA;            // HighLightColorA
    float4 _HighLightColorB;            // HighLightColorB
    float  _FHighLightPos;              // FHighLightPos（高光位置偏移）
    float  _HighlightLength;            // Highlight length
    float  _FinalBrightness;            // Final brightness
    float  _HairHLColorLerpSMOMin;      // Hair HighLight Color Lerp SMO Min
    float  _HairHLColorLerpSMOMax;      // Hair HighLight Color Lerp SMO Max
    float  _HairHLColorLerpSMOOffset;   // Hair HighLight Color Lerp SMO Offset

CBUFFER_END

// -----------------------------------------------------------------------------
// 顶点输入结构体
// -----------------------------------------------------------------------------

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 uv           : TEXCOORD0;
    float4 color        : COLOR;        // 顶点色（备用）
};

// -----------------------------------------------------------------------------
// 顶点输出 / 片元输入结构体
// -----------------------------------------------------------------------------

struct Varyings
{
    float4 positionCS   : SV_POSITION;
    float2 uv           : TEXCOORD0;
    float3 normalWS     : TEXCOORD1;
    float3 tangentWS    : TEXCOORD2;
    float3 bitangentWS  : TEXCOORD3;
    float3 positionWS   : TEXCOORD4;
    float4 screenPos    : TEXCOORD5;    // 供 DepthRim 使用
};

// -----------------------------------------------------------------------------
// 表面数据结构体（Frame.014 GetSurfaceData 的输出）
// -----------------------------------------------------------------------------

struct SurfaceData
{
    // 基础 PBR
    float3 albedo;              // _D.RGB × BaseColor.RGB
    float  alpha;               // _D.A
    float  metallic;            // _P.R × MetallicMax
    float  ao;                  // _P.G（AO / directOcclusion）
    float  smoothness;          // _P.B × SmoothnessMax
    float  perceptualRoughness; // PerceptualSmoothnessToPerceptualRoughness(smoothness)
    float  roughness;           // PerceptualRoughnessToRoughness(perceptualRoughness)
    float  rampUV;              // _P.A（RampUV，用于发丝 Ramp 采样）
    // 衍生量
    float3 diffuseColor;        // ComputeDiffuseColor(albedo, metallic)
    float3 fresnel0;            // ComputeFresnel0(albedo, metallic)
    float  directOcclusion;     // _P.G
    // 法线（切线空间，由 Init 在 WS 下解算）
    float3 normalTS;            // DecodeNormal(_HN.RGB) — 表面法线（切线空间）
    float3 hairTangentTS;       // DecodeNormal(_HN.RGB × HNormalStrength) — 发丝切线方向
};

// -----------------------------------------------------------------------------
// 光照数据结构体（Frame.013 Init 的输出）
// -----------------------------------------------------------------------------

struct LightingData
{
    // 世界空间向量
    float3 N;               // 表面法线（世界空间，来自 _HN DecodeNormal）
    float3 HN;              // 发丝切线法线（世界空间，各向异性方向）
    float3 V;               // 视线方向
    float3 L;               // 主方向光方向
    float3 T;               // 切线（Tangent，来自顶点 TBN）
    float3 B;               // 发丝副法线 = cross(N, HN)
    float3 H;               // 半角向量

    // 标准点积
    float  NoV;             // clamp(dot(N, V), 0.0001, 1)
    float  NoL;             // saturate(dot(N, L))
    float  NoL_unsat;       // dot(N, L)（未 saturate，用于半 Lambert）
    float  halfLambert;     // RemapHalfLambert(NoL_unsat)（SigmoidSharp Toon 化）
    float  LoV;             // dot(L, V)
    float  LdotH;           // dot(L, H)
    float  NdotH;           // dot(N, H)
    float  absNdotL;        // abs(dot(N, L))

    // 各向异性点积（供 GGX Aniso 使用）
    float  TdotH;           // dot(T, H)
    float  BdotH;           // dot(B, H)（B=发丝副法线）

    // 发丝各向异性高光专用
    float  HNdotV;          // dot(HN, V)
    float  BdotMixV;        // dot(B, MixV)，MixV = V 偏移后的视角向量

    // 光照颜色 / 阴影
    float3 lightColor;      // dirLight_lightColor
    float  castShadow;      // 来自 SHADERINFO 的投影阴影值（Toon 化前）
};

#endif // PBRTOONBASEHAIR_INPUT_INCLUDED
