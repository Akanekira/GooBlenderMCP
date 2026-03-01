// =============================================================================
// PBRToon_irisBase_Input.hlsl
// 虹膜高光材质 — 贴图声明 + 材质属性 + 结构体定义
// 溯源：docs/analysis/M_actor_laevat_iris_01/00_material_overview.md
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#ifndef PBRTOON_IRISBASE_INPUT_INCLUDED
#define PBRTOON_IRISBASE_INPUT_INCLUDED

// =============================================================================
// 贴图声明
// =============================================================================

// 主 Matcap 高光贴图 — 视空间法线 UV 采样
// RGB: 高光颜色/强度
TEXTURE2D(_MatcapMain);    SAMPLER(sampler_MatcapMain);    // T_actor_common_matcap_05_D

// 辅助 Matcap 高光贴图 — 固定强度 0.7 叠加
// RGB: 高光颜色/强度
TEXTURE2D(_MatcapSub);     SAMPLER(sampler_MatcapSub);     // T_actor_common_matcap_07_D

// =============================================================================
// 材质属性（对应群组接口输入 + 内部固定参数）
// =============================================================================

CBUFFER_START(UnityPerMaterial)

    // --- 虹膜颜色输入（由外部材质传入，不在本 Shader 中采样 _D 贴图） ---
    float4 _IrisColor;          // 对应群组输入 D_RGB（虹膜 Diffuse 颜色）
    float  _IrisAlpha;          // 对应群组输入 D_Alpha（虹膜遮罩，来自 _D.a）

    // --- 亮度控制 ---
    float  _EyesBrightness;         // 对应 Eyes brightness（基础最低亮度）
    float  _EyesHighlightBrightness;// 对应 Eyes HightLight brightness（峰值亮度倍率）

    // --- 辅助 Matcap 强度（对应自发光节点 Strength=0.7，可选暴露） ---
    float  _MatcapSubStrength;      // 默认 0.7

    // --- 主 Emission 基础强度（Blender 节点默认 Strength=2.0） ---
    float  _EmissionBaseStrength;   // 默认 2.0（外层 Emission 节点的 Strength 默认值）

    // --- Matcap ADD 混合权重（混合.002 factor=0.567） ---
    float  _MatcapBlendFactor;      // 默认 0.567

CBUFFER_END

// =============================================================================
// 骨骼方向向量（由 CPU/骨骼控制器每帧更新，通过 MaterialPropertyBlock 传入）
// =============================================================================

float3 _HeadUp;          // headUp 骨骼轴（世界空间）
float3 _HeadRight;       // headRight 骨骼轴（世界空间）
float3 _HeadForward;     // headForward 骨骼轴（世界空间）
float3 _LightDirection;  // 主光源方向（世界空间，由自定义系统写入顶点属性后传入）

// =============================================================================
// 顶点输入输出结构体
// =============================================================================

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 uv0          : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS   : SV_POSITION;
    float2 uv           : TEXCOORD0;
    float3 normalWS     : TEXCOORD1;    // 世界空间法线（用于 Matcap UV 计算）
    float3 positionWS   : TEXCOORD2;
};

// =============================================================================
// 表面数据结构体
// =============================================================================

struct IrisSurfaceData
{
    float3 irisColor;           // 虹膜底色（来自 D_RGB 群组输入）
    float  irisAlpha;           // 虹膜遮罩（来自 D_Alpha 群组输入）
    float2 matcapUV;            // Matcap UV（视空间法线 × 0.5 + 0.5）
    float3 matcapMain;          // 主 Matcap 采样结果（matcap_05）
    float3 matcapSub;           // 辅助 Matcap 采样结果（matcap_07）
};

#endif // PBRTOON_IRISBASE_INPUT_INCLUDED
