// =============================================================================
// PBRToonBase_Input.hlsl
// 输入结构体、贴图声明、材质属性
// 对应 Blender 材质 M_actor_pelica_cloth_04 的顶层接口
// 溯源：docs/analysis/00_material_overview.md
// =============================================================================

#ifndef PBRTOONBASE_INPUT_INCLUDED
#define PBRTOONBASE_INPUT_INCLUDED

// -----------------------------------------------------------------------------
// 贴图声明
// -----------------------------------------------------------------------------

// _D : Diffuse/Albedo (sRGB)  RGB=颜色 A=遮罩
TEXTURE2D(_D);          SAMPLER(sampler_D);

// _N : 法线贴图 (Non-Color)   切线空间 XY 通道
TEXTURE2D(_N);          SAMPLER(sampler_N);

// _P : 参数贴图 (Non-Color)
//   R = Metallic
//   G = AO / directOcclusion
//   B = Smoothness
//   A = RampUV（Toon 阴影色带采样坐标）
TEXTURE2D(_P);          SAMPLER(sampler_P);

// _E : 自发光贴图 (Non-Color 标注，实际含颜色)
TEXTURE2D(_E);          SAMPLER(sampler_E);

// _M : 遮罩贴图 (Non-Color) — 部分材质使用，本材质未连线
TEXTURE2D(_M);          SAMPLER(sampler_M);

// Toon 阴影色带 LUT（5条 Ramp，建议合并为竖向 5xN 贴图）
// 对应 RampSelect 内部 5 张 TEX_IMAGE
TEXTURE2D(_RampLUT);    SAMPLER(sampler_RampLUT);

// 预积分 FGD LUT（GGX + Disney Diffuse）
// 对应 GetPreIntegratedFGDGGXAndDisneyDiffuse 内嵌贴图
TEXTURE2D(_FGD_LUT);    SAMPLER(sampler_FGD_LUT);

// RS 效果贴图（彩虹/光泽视角色变）
// 对应 Frame.011 ThinFilmFilter 内嵌两张贴图（材质特定）
// M_actor_pelica_cloth_04: T_actor_yvonne_cloth_05_RS / T_actor_aurora_cloth_03_RS
TEXTURE2D(_RS_Tex_A); SAMPLER(sampler_RS_Tex_A);   // sRGB
TEXTURE2D(_RS_Tex_B); SAMPLER(sampler_RS_Tex_B);   // Linear / Extend

// URP 深度贴图（DepthRim 使用）
TEXTURE2D(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

// -----------------------------------------------------------------------------
// 材质属性（对应群组 51 个接口输入）
// -----------------------------------------------------------------------------

// --- 开关 ---
float _IsSkin;                  // Is Skin?
float _UseAnisotropy;           // Use anisotropy?
float _UseToonAniso;            // Use Toonaniso?
float _UseNormalTex;            // Use NormalTex?
float _UseRSEff;                // Use RS_Eff?
float _UseSimpleTransmission;   // Use Simple transmission
float _RSModel;                 // RS Model

// --- 粗糙度/金属度 ---
float _SmoothnessMax;
float _Aniso_SmoothnessMaxT;
float _Aniso_SmoothnessMaxB;
float _MetallicMax;

// --- 阴影/漫反射控制 ---
float _RemaphalfLambert_center;
float _RemaphalfLambert_sharp;
float _CastShadow_center;
float _CastShadow_sharp;
float _RampIndex;
float4 _dirLight_lightColor;
float4 _directOcclusionColor;
float4 _AmbientLightColorTint;
float _GlobalShadowBrightnessAdjustment;
float _ColorDesaturationAttenuation;    // Color desaturation in shaded areas

// --- 高光 ---
float4 _SpecularColor;
float _NormalStrength;
float _specularFGDStrength;

// --- Fresnel / ToonFresnel ---
float4 _fresnelInsideColor;
float4 _fresnelOutsideColor;
float _ToonfresnelPow;
float _ToonfresnelSMO_L;
float _ToonfresnelSMO_H;
float _LayerWeightValue;
float _LayerWeightValueOffset;

// --- Rim ---
float _Rim_DirLightAtten;
float _Rim_width_X;
float _Rim_width_Y;
float4 _Rim_Color;
float _Rim_ColorStrength;

// --- RS Effect ---
float _RS_Index;
float _RS_Strength;
float _RS_MultiplyValue;
float4 _RS_ColorTint;

// --- 其他 ---
float _Alpha;
float _AnisotropicMask;
float _SimpleTransmissionValue;
float _RS_Index2;               // RS_Index

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
    float3 normalTS;        // 解码后切线空间法线
    float  metallic;        // _P.R × MetallicMax
    float  ao;              // _P.G
    float  smoothness;      // _P.B × SmoothnessMax
    float  rampUV;          // _P.A
    float3 emission;        // _E.RGB

    // 计算得出
    float3 diffuseColor;    // albedo × (1 - metallic)
    float3 fresnel0;        // lerp(0.04, albedo, metallic)
    float  perceptualRoughness;
    float  roughness;
    float  perceptualRoughnessT;  // 各向异性 T
    float  roughnessT;
    float  perceptualRoughnessB;  // 各向异性 B
    float  roughnessB;
};

// -----------------------------------------------------------------------------
// 光照数据中间结构（Init 输出）
// -----------------------------------------------------------------------------

struct LightingData
{
    float3 N;       // 法线（世界空间）
    float3 V;       // 视角方向
    float3 L;       // 光方向
    float3 T;       // 切线（世界空间）
    float3 B;       // 副切线（世界空间）

    float NoV;      // dot(N, V)，clamped
    float NoL;      // dot(N, L)，unsaturated
    float LoV;      // dot(L, V)

    // 各向异性点积
    float ToL, BdotL;
    float ToV, BdotV;

    // 半角点积（Get_NoH_LoH_ToH_BoH）
    float NdotH, LdotH, TdotH, BdotH;

    // 来自 SHADERINFO（URP 侧用 MainLight）
    float3 lightColor;
    float  castShadow;      // 投影阴影值
};

#endif // PBRTOONBASE_INPUT_INCLUDED
