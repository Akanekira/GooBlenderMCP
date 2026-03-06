// =============================================================================
// SubGroups.hlsl (Face)
// M_actor_pelica_face_01 的子群组函数集合
// 复用共享子群组 + 面部新增函数
// 溯源：docs/analysis/sub_groups/
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#ifndef PBRTOONBASEFACE_SUBGROUPS_INCLUDED
#define PBRTOONBASEFACE_SUBGROUPS_INCLUDED

// 复用共享子群组（SigmoidSharp, SmoothStep, ComputeDiffuseColor, ComputeFresnel0,
// PerceptualSmoothnessToPerceptualRoughness, PerceptualRoughnessToRoughness,
// F_Schlick, Get_NoH_LoH_ToH_BoH, DV_SmithJointGGX_Aniso,
// GetPreIntegratedFGD, DirectLightingDiffuse, DeSaturation）
#include "../../SubGroups/SubGroups.hlsl"

// =============================================================================
// Face 新增子群组
// =============================================================================

// -----------------------------------------------------------------------------
// RecalculateNormal
// 面部球面法线重映射：将面部法线球面化以获得柔和平滑的光影过渡
// 溯源：sub_groups/Recalculate_normal.md
// -----------------------------------------------------------------------------
float3 RecalculateNormal(
    float  sphereNormalStrength,  // 球面法线混合强度 [0,1]
    float3 headCenter,            // 头部中心世界坐标（骨骼驱动）
    float3 posWS,                 // 顶点世界坐标
    float3 normalWS,              // 原始世界空间法线
    float  chinMask               // 下巴遮罩（1 = 保留原始法线）
)
{
    // Step 1: 球面法线 = 顶点到头部中心方向
    float3 sphereNormal = normalize(posWS - headCenter);

    // Step 2: 原始法线与球面法线混合
    float3 blended = lerp(normalWS, sphereNormal, sphereNormalStrength);

    // Step 3: 下巴区域还原原始法线
    return lerp(blended, normalWS, chinMask);
}

// -----------------------------------------------------------------------------
// CalculateAngleThreshold
// 光源相对头部水平旋转角度（用于 SDF 阴影采样）
// 溯源：sub_groups/calculateAngel.md
// 注：函数已在 iris 材质的 SubGroups 中定义，此处为 Face 可直接复用的声明
// -----------------------------------------------------------------------------
struct AngleThresholdResult
{
    float AngleThreshold;  // 光源水平方位角映射值 [0,1]
    float FlipThreshold;   // = sX，左右分量
};

AngleThresholdResult CalculateAngleThreshold(
    float3 lightDirection,
    float3 headUp,
    float3 headRight,
    float3 headForward
)
{
    AngleThresholdResult result;

    // 光源水平投影
    float  sY         = dot(lightDirection, headUp);
    float3 L_hor      = lightDirection - headUp * sY;
    float3 L_hor_norm = normalize(L_hor);

    // 头部坐标系分量
    float sX = dot(headRight, L_hor_norm);
    float sZ = dot(-headForward, L_hor_norm);

    // 方位角计算与区间映射
    float angle      = atan2(sX, sZ);
    float angleNorm  = angle / 3.14159265;
    float isPositive = angleNorm > 0.0 ? 1.0 : 0.0;

    result.AngleThreshold = lerp(angleNorm + 1.0, angleNorm - 1.0, isPositive);
    result.FlipThreshold  = sX;

    return result;
}

// -----------------------------------------------------------------------------
// FrontTransparentRed
// 面部皮肤次表面散射近似：正面透红效果
// 溯源：sub_groups/Front_transparent_red.md
// 内部调用：SmoothStepCustom（已在共享 SubGroups.hlsl 中定义）
// -----------------------------------------------------------------------------
float4 FrontTransparentRed(
    float  smoMax,              // SmoothStep 上限（Front R Smo）
    float  positiveAttenuation, // 正面衰减因子
    float4 sideColor,           // 透红颜色
    float  D_R,                 // Diffuse 贴图红通道
    float  frontPow             // 衰减指数（Front R Pow, 默认 2.0）
)
{
    // Step 1: 红通道幂次衰减
    float rawFactor = pow(D_R, frontPow);

    // Step 2: 平滑阶梯过渡
    float factor = SmoothStepCustom(0.0, smoMax, rawFactor);

    // Step 3: 颜色混合
    float4 redColor = sideColor * factor;

    // Step 4: 正面衰减
    return redColor * positiveAttenuation;
}

#endif // PBRTOONBASEFACE_SUBGROUPS_INCLUDED
