// =============================================================================
// SubGroups.hlsl
// 虹膜高光材质 — 子群组 HLSL 函数
// 溯源：docs/analysis/sub_groups/calculateAngel.md
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================

#ifndef IRISBASE_SUBGROUPS_INCLUDED
#define IRISBASE_SUBGROUPS_INCLUDED

// =============================================================================
// --- calculateAngel ---
// 计算主光源相对于角色头部坐标系的水平方位角
// 用于虹膜高光的角度强度控制
//
// 溯源：docs/raw_data/calculateAngel_20260302.json
// Blender 群组名：calculateAngel
//
// 算法概述：
//   1. 将光源方向投影到头部水平面（去掉垂直分量）
//   2. 计算水平投影与头部前向/右向的 atan2 方位角
//   3. 将 [-π, π] 角度映射到 [0,1] 区间（折叠映射）
// =============================================================================

struct AngleThresholdResult
{
    float AngleThreshold;   // 光源水平方位角映射值 ∈ (-1, 1]
    float FlipThreshold;    // = sX，光源左右分量（正=右侧光，负=左侧光）
};

AngleThresholdResult CalculateAngleThreshold(
    float3 lightDirection,  // 主光源方向（世界空间）
    float3 headUp,          // 头部向上轴（世界空间骨骼坐标）
    float3 headRight,       // 头部向右轴（世界空间骨骼坐标）
    float3 headForward      // 头部前向轴（世界空间骨骼坐标）
)
{
    AngleThresholdResult result;

    // --- Frame: lightDirectionProjHeadWS ---
    // 光源方向在头部水平面的投影（归一化）
    float  sY         = dot(lightDirection, headUp);         // VecMath.008 DOT
    float3 sY_proj    = headUp * sY;                         // VecMath.009 MULTIPLY
    float3 L_hor      = lightDirection - sY_proj;            // VecMath.010 SUBTRACT
    float3 L_hor_norm = normalize(L_hor);                    // VecMath.011 NORMALIZE

    // --- Frame: sX ---
    float sX = dot(headRight, L_hor_norm);                   // VecMath.017 DOT

    // --- Frame: sZ ---
    float3 negHeadForward = headForward * (-1.0);            // VecMath.019 MULTIPLY (×-1)
    float  sZ             = dot(negHeadForward, L_hor_norm); // VecMath.020 DOT

    // --- Frame: angleThreshold ---
    float angle     = atan2(sX, sZ);                         // 运算.003 ARCTAN2
    float angleNorm = angle / 3.14159265358979;              // 运算.004 DIVIDE ÷π → [-1, 1]

    float isPositive = (float)(angleNorm > 0.0);             // 运算.005 GREATER_THAN
    float angleA     = angleNorm + 1.0;                      // 运算.006 ADD  (负角区间 → [0,1])
    float angleB     = angleNorm - 1.0;                      // 运算.007 SUBTRACT (正角区间 → (-1,0])

    // 混合.001 MIX FLOAT: lerp(A, B, isPositive)
    result.AngleThreshold = lerp(angleA, angleB, isPositive);

    // --- Frame: Flip threshold ---
    result.FlipThreshold = sX;                               // 光源左右分量（未在本材质中使用）

    return result;
}

#endif // IRISBASE_SUBGROUPS_INCLUDED
