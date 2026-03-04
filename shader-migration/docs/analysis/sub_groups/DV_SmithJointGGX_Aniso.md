# DV_SmithJointGGX_Aniso

> 溯源：`docs/raw_data/DV_SmithJointGGX_Aniso_20260227.json` · 22 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `DV_SmithJointGGX_Aniso()` 函数
> 第三层详细分析：`docs/analysis/sub_groups/DV_SmithJointGGX_Aniso_L3.md`（2026-03-04）

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `NdotH` | Float | — |
| `Abs_NdotL` | Float | — |
| `clampedNdotV` | Float | — |
| `clampedRoughness` | Float | — |
| `TdotH` | Float | — |
| `BdotH` | Float | — |
| `TdotL` | Float | — |
| `BdotL` | Float | — |
| `TdotV` | Float | — |
| `BdotV` | Float | — |
| `roughnessT` | Float | — |
| `roughnessB` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `original` | Float | — |
| `anisotropy` | Float | — |
| `DeBug` | Float | — |

---

## 🔗 内部节点（第三层子群组）

| 本地节点名 | 调用群组 | 功能 |
|-----------|---------|------|
| `群组` | `GetSmithJointGGXPartLambdaV` | 等向 GGX Lambda_V 项 |
| `群组.001` | `DV_SmithJointGGX.IN` | 等向 D×V 最终计算 |
| `群组.002` | `GetSmithJointGGXAnisoPartLambdaV` | 各向异性 GGX Lambda_V 项 |
| `群组.003` | `DV_SmithJointGGXAniso` | 各向异性 D×V 最终计算 |

---

## 📊 计算流程

```
// 等向性分支（original 输出）
lambdaV_iso = GetSmithJointGGXPartLambdaV(NdotV, roughness)
original    = DV_SmithJointGGX.IN(NdotH, Abs_NdotL, lambdaV_iso, roughness)

// 各向异性分支（anisotropy 输出）
lambdaV_aniso = GetSmithJointGGXAnisoPartLambdaV(TdotV, BdotV, NdotV, roughT, roughB)
anisotropy    = DV_SmithJointGGXAniso(NdotH, Abs_NdotL, lambdaV_aniso,
                                       TdotH, BdotH, TdotL, BdotL, roughT, roughB)

// 混合：由主群组 "Use anisotropy?" 控制选择 original 或 anisotropy
```

---

## 🧮 等价公式

**各向异性 GGX NDF（D 项）：**
```
D_GGXAniso(H, roughT, roughB) =
    1 / (PI * roughT * roughB * (TdotH²/roughT² + BdotH²/roughB² + NdotH²)²)
```

**Smith Joint GGX Visibility（V 项）：**
```
Vis_SmithJointGGX = 0.5 / (Abs_NdotL * ΛV + NdotV * ΛL + eps)
ΛV = Abs_NdotL * sqrt((-NdotV * roughness + NdotV) * NdotV + roughness)
ΛL = NdotV  * sqrt((-Abs_NdotL * roughness + Abs_NdotL) * Abs_NdotL + roughness)
```

---

## 💻 HLSL 等价

```cpp
// 各向异性 D 项
float D_GGXAniso(float NdotH, float TdotH, float BdotH, float roughT, float roughB)
{
    float f = TdotH*TdotH/(roughT*roughT) + BdotH*BdotH/(roughB*roughB) + NdotH*NdotH;
    return 1.0 / (UNITY_PI * roughT * roughB * f * f);
}

// Smith Joint GGX V 项（各向异性）
float V_SmithJointGGXAniso(float TdotV, float BdotV, float NdotV,
                            float TdotL, float BdotL, float NdotL,
                            float roughT, float roughB)
{
    float lambdaV = NdotL * length(float3(roughT * TdotV, roughB * BdotV, NdotV));
    float lambdaL = NdotV * length(float3(roughT * TdotL, roughB * BdotL, NdotL));
    return 0.5 / (lambdaV + lambdaL + 1e-5);
}
```

---

## 📝 备注

- 等向和各向异性两路并行计算，主群组根据 `Use anisotropy?` 开关选择
- 各向同性路径：`partLambdaV × NdotL`（**无 sqrt**），与 HDRP 标准版（含 sqrt）存在差异
- 各向异性路径：`AnisoPartLambdaV`（**已含 sqrt**，LENGTH 节点），外层直接 × NdotL
- `DeBug` 输出 = `AnisoPartLambdaV`（各向异性 ΛV 原始值），调试用，Unity 侧忽略
- `clampedRoughness` = 各向同性粗糙度（外层平方得 a2），`roughnessT/B` = 各向异性分量
- **第三层子群组完整分析**：见 `docs/analysis/sub_groups/DV_SmithJointGGX_Aniso_L3.md`

---

## ❓ 待确认

- [ ] 各向同性路径 `partLambdaV × NdotL`（无 sqrt）是引擎近似优化还是节点 bug？
      待与 Goo Engine 源码或 HDRP 近似版本对照
