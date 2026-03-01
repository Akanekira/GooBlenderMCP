// =============================================================================
// SubGroups.hlsl
// PBRToonBaseHair 子群组函数集合
// 复用基准：#include 引用 PBRToonBase 的 SubGroups.hlsl，新增 OutlineColor
// 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#ifndef PBRTOONBASEHAIR_SUBGROUPS_INCLUDED
#define PBRTOONBASEHAIR_SUBGROUPS_INCLUDED

// 复用 PBRToonBase 的全部子群组函数（19个共用子群组）
// SigmoidSharp / SmoothStepCustom / PerceptualSmoothnessToPerceptualRoughness /
// PerceptualRoughnessToRoughness / ComputeDiffuseColor / ComputeFresnel0 /
// DecodeNormal / Get_NoH_LoH_ToH_BoH / DV_SmithJointGGX_Aniso / F_Schlick /
// GetPreIntegratedFGDGGXAndDisneyDiffuse / RampSelect / directLighting_diffuse /
// DirectionalLightAttenuation / FresnelAttenuation / VerticalAttenuation /
// DepthRim / Rim_Color / DeSaturation / ShaderOutput
#include "../../SubGroups/SubGroups.hlsl"

// -----------------------------------------------------------------------------
// OutlineColor  [NEW — 首次在 PBRToonBaseHair 中使用]
// 基于 Fresnel 衰减和垂直方向衰减生成描边颜色遮罩
// 溯源：docs/analysis/sub_groups/OutlineColor.md
// 输入：
//   fresnel_attenuation  — 来自 FresnelAttenuation 子群组
//   vertical_attenuation — 来自 VerticalAttenuation 子群组
// 输出：
//   float3 mask（灰度，广播至 RGB，实际为描边可见区域权重）
// -----------------------------------------------------------------------------
float3 OutlineColor(float fresnel_attenuation, float vertical_attenuation)
{
    // ColorRamp.001: 0→white, 0.495→black, 输入 = (1 - fresnel_atten)
    float sub   = 1.0 - fresnel_attenuation;
    float crampA = saturate(1.0 - sub / 0.495);

    // 中间量：crampA × fresnel_atten
    float mid = crampA * fresnel_attenuation;

    // ColorRamp.002: 0→white, 0.295→black, 输入 = vertical_attenuation
    float crampB = saturate(1.0 - vertical_attenuation / 0.295);

    // 最终遮罩 = mid × crampB（仅在边缘 + 下方区域出现描边）
    float mask = mid * crampB;
    return float3(mask, mask, mask);
}

#endif // PBRTOONBASEHAIR_SUBGROUPS_INCLUDED
