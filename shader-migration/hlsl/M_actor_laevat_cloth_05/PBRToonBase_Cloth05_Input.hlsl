// =============================================================================
// PBRToonBase_Cloth05_Input.hlsl
// 输入结构体、贴图声明、材质属性
// 对应 Blender 材质 M_actor_laevat_cloth_05 的顶层接口
// 溯源：docs/analysis/M_actor_laevat_cloth_05/00_material_overview.md
// 注：伪代码级 HLSL，供理解渲染流程使用
//
// 与 PBRToonBase_Input.hlsl（pelica_cloth_04）的差异：
//   - 新增 _M 贴图采样（T_actor_laevat_cloth_03_M.png）并在 GetSurfaceData 中预处理
//   - _E 贴图声明保留但不采样（未连线，Emission=0）
//   - SurfaceData 新增 float3 mMask 字段
// =============================================================================

#ifndef PBRTOONBASE_CLOTH05_INPUT_INCLUDED
#define PBRTOONBASE_CLOTH05_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// -----------------------------------------------------------------------------
// 贴图声明
// -----------------------------------------------------------------------------

// _D : Diffuse/Albedo (sRGB) — T_actor_laevat_cloth_02_D.png
//   RGB = 布料颜色  A = 遮罩/AO
TEXTURE2D(_D);          SAMPLER(sampler_D);

// _N : 法线贴图 (Non-Color) — T_actor_laevat_cloth_02_N.png
//   RG = 切线空间法线 XY
TEXTURE2D(_N);          SAMPLER(sampler_N);

// _P : PBR 参数贴图 (Non-Color) — T_actor_laevat_cloth_02_P.png
//   R = Metallic  G = AO/directOcclusion  B = Smoothness  A = RampUV
TEXTURE2D(_P);          SAMPLER(sampler_P);

// _M : 遮罩贴图 (Non-Color) — T_actor_laevat_cloth_03_M.png  ← laevat 特有（已连线）
//   用途：经 SmoothStep(0,1) 后送入群组 _M 槽
//   最可能用于 RS EFF / ThinFilmFilter 区域遮罩
TEXTURE2D(_M);          SAMPLER(sampler_M);

// _E : 自发光贴图 — laevat_cloth_05 未连线，保留声明，Emission 固定为 0
// TEXTURE2D(_E);       SAMPLER(sampler_E);  // 未使用

// Toon 阴影色带 LUT（5条 Ramp，RampSelect 内部采样）
TEXTURE2D(_RampLUT);    SAMPLER(sampler_RampLUT);

// 预积分 FGD LUT（GetPreIntegratedFGDGGXAndDisneyDiffuse 使用）
TEXTURE2D(_FGD_LUT);    SAMPLER(sampler_FGD_LUT);

// ThinFilm LUT（Frame.011 ThinFilmFilter 使用）
TEXTURE2D(_ThinFilmLUT); SAMPLER(sampler_ThinFilmLUT);

// URP 深度贴图（DepthRim 使用）
TEXTURE2D(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

// -----------------------------------------------------------------------------
// 材质属性 CBUFFER（对应群组 51 个接口输入的本材质数值）
// -----------------------------------------------------------------------------

CBUFFER_START(UnityPerMaterial)

    // [Header(Switches)]
    float  _IsSkin;                 // Is Skin? = False
    float  _UseAnisotropy;          // Use anisotropy? = True
    float  _UseToonAniso;           // Use Toonaniso? = True
    float  _UseNormalTex;           // Use NormalTex? = True
    float  _UseRSEff;               // Use RS_Eff? = True
    float  _UseSimpleTransmission;  // Use Simple transmission? = False
    float  _RSModel;                // RS Model = True

    // [Header(Roughness Metallic)]
    float  _SmoothnessMax;          // = 1.0
    float  _Aniso_SmoothnessMaxT;   // = 0.2197（切线方向，较粗糙）
    float  _Aniso_SmoothnessMaxB;   // = 0.6689（副切线方向，较光滑）
    float  _MetallicMax;            // = 1.0

    // [Header(Shadow Diffuse)]
    float  _RemaphalfLambert_center; // = 0.570
    float  _RemaphalfLambert_sharp;  // = 0.180
    float  _CastShadow_center;       // = 0.0
    float  _CastShadow_sharp;        // = 0.170
    float  _RampIndex;               // = 0.0
    float4 _dirLight_lightColor;
    float4 _directOcclusionColor;
    float4 _AmbientLightColorTint;
    float  _GlobalShadowBrightnessAdjustment; // = -1.800
    float  _ColorDesaturationAttenuation;     // = 0.900

    // [Header(Normal Specular)]
    float4 _SpecularColor;
    float  _NormalStrength;          // = 1.446
    float  _specularFGDStrength;     // = 1.0

    // [Header(ToonFresnel)]
    float4 _fresnelInsideColor;
    float4 _fresnelOutsideColor;
    float  _ToonfresnelPow;          // = 1.700
    float  _ToonfresnelSMO_L;        // = 0.0
    float  _ToonfresnelSMO_H;        // = 0.500
    float  _LayerWeightValue;        // = 0.0
    float  _LayerWeightValueOffset;  // = 0.0

    // [Header(Rim Light)]
    float  _Rim_DirLightAtten;       // = 0.962
    float  _Rim_width_X;             // = 0.04185
    float  _Rim_width_Y;             // = 0.01911
    float4 _Rim_Color;
    float  _Rim_ColorStrength;       // = 5.0

    // [Header(RS Effect)]
    float  _RS_Index;                // = 0.0
    float  _RS_Strength;             // = 1.0
    float  _RS_MultiplyValue;        // = 1.0
    float4 _RS_ColorTint;

    // [Header(Other)]
    float  _Alpha;                   // = 1.0
    float  _AnisotropicMask;         // = 0.0
    float  _SimpleTransmissionValue; // = 0.0

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
// 表面数据中间结构（GetSurfaceData 输出）
// -----------------------------------------------------------------------------

struct SurfaceData
{
    // 来自贴图
    float3 albedo;          // _D.RGB
    float  alpha;           // _D.A
    float3 normalTS;        // _N.XY → DecodeNormal 重建
    float  metallic;        // _P.R × MetallicMax
    float  ao;              // _P.G（directOcclusion）
    float  smoothness;      // _P.B × SmoothnessMax
    float  rampUV;          // _P.A（RampSelect 行索引）
    float3 mMask;           // _M.RGB → SmoothStep(0,1) — laevat_cloth_05 特有
    float3 emission;        // = float3(0,0,0)（_E 未连线）

    // 计算衍生量
    float3 diffuseColor;    // ComputeDiffuseColor(albedo, metallic)
    float3 fresnel0;        // ComputeFresnel0(albedo, metallic, 0.04)
    float  perceptualRoughness;
    float  roughness;
    float  perceptualRoughnessT;  // 各向异性 T 轴
    float  roughnessT;
    float  perceptualRoughnessB;  // 各向异性 B 轴
    float  roughnessB;
};

// -----------------------------------------------------------------------------
// 光照数据中间结构（InitLightingData 输出）
// -----------------------------------------------------------------------------

struct LightingData
{
    float3 N;       // 法线（世界空间）
    float3 V;       // 视角方向
    float3 L;       // 主平行光方向
    float3 T;       // 切线（世界空间）
    float3 B;       // 副切线（法线贴图重建后）

    float NoV;      // saturate(dot(N,V))
    float NoL;      // dot(N,L)（unsaturated，用于 halfLambert）
    float LoV;      // dot(L,V)

    // 各向异性点积
    float ToL;      // dot(T,L)
    float BdotL;    // dot(B,L)
    float ToV;      // dot(T,V)
    float BdotV;    // dot(B,V)

    // 半角点积（Get_NoH_LoH_ToH_BoH）
    float NdotH, LdotH, TdotH, BdotH;

    // 光照信息（来自 SHADERINFO / MainLight）
    float3 lightColor;
    float  castShadow;
};

#endif // PBRTOONBASE_CLOTH05_INPUT_INCLUDED
