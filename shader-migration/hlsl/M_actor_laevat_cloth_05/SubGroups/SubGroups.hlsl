// =============================================================================
// SubGroups.hlsl（M_actor_laevat_cloth_05）
// 所有子群组函数 — 完全复用 pelica_cloth_04 的实现
// 溯源：docs/analysis/sub_groups/ 各子群组文档
// 注：本文件通过 #include 引用基础共享版本，无新增函数
// =============================================================================

#ifndef PBRTOONBASE_CLOTH05_SUBGROUPS_INCLUDED
#define PBRTOONBASE_CLOTH05_SUBGROUPS_INCLUDED

// 复用基础共享 SubGroups（20个已分析子群组的 HLSL 实现）
// pelica_cloth_04 的 SubGroups.hlsl 位于 hlsl/SubGroups/SubGroups.hlsl
#include "../../SubGroups/SubGroups.hlsl"

// -----------------------------------------------------------------------------
// laevat_cloth_05 无新增子群组
// 材质层新增的 SmoothStep 调用复用上方 include 中已有的 SmoothStep 函数：
//
// float SmoothStep(float minVal, float maxVal, float x)
// {
//     float t = saturate((x - minVal) / (maxVal - minVal));
//     return t * t * (3.0 - 2.0 * t);
// }
//
// 在 GetSurfaceData 中调用：
//   mMask.r = SmoothStep(0.0, 1.0, mTex.r);
//   mMask.g = SmoothStep(0.0, 1.0, mTex.g);
//   mMask.b = SmoothStep(0.0, 1.0, mTex.b);
// -----------------------------------------------------------------------------

#endif // PBRTOONBASE_CLOTH05_SUBGROUPS_INCLUDED
