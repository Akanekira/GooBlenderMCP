# DV_SmithJointGGX_Aniso

> 溯源：`docs/raw_data/DV_SmithJointGGX_Aniso_20260227.json` | 节点数：22
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `DV_SmithJointGGX_Aniso()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `NdotH` | Float |
| 输入 | `Abs_NdotL` | Float |
| 输入 | `clampedNdotV` | Float |
| 输入 | `clampedRoughness` | Float |
| 输入 | `TdotH` | Float |
| 输入 | `BdotH` | Float |
| 输入 | `TdotL` | Float |
| 输入 | `BdotL` | Float |
| 输入 | `TdotV` | Float |
| 输入 | `BdotV` | Float |
| 输入 | `roughnessT` | Float |
| 输入 | `roughnessB` | Float |
| 输出 | `original` | Float |
| 输出 | `anisotropy` | Float |
| 输出 | `DeBug` | Float |

## 内部节点（第三层子群组）

| 本地节点名 | 调用群组 | 功能 |
|-----------|---------|------|
| `群组` | `GetSmithJointGGXPartLambdaV` | 等向 GGX Lambda_V 项 |
| `群组.001` | `DV_SmithJointGGX.IN` | 等向 D×V 最终计算 |
| `群组.002` | `GetSmithJointGGXAnisoPartLambdaV` | 各向异性 GGX Lambda_V 项 |
| `群组.003` | `DV_SmithJointGGXAniso` | 各向异性 D×V 最终计算 |

## 计算流程

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

## 等价公式

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

## HLSL 等价

```hlsl
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

## 备注

- 等向和各向异性两路并行计算，主群组根据 `Use anisotropy?` 开关选择
- 与 HDRP `D_GGXAniso` / `V_SmithJointGGXAniso` 实现基本一致
- **第三层子群组**（`GetSmithJointGGXPartLambdaV` 等）尚未提取，后续需补充 Phase 1.4

## 待确认

- [ ] 第三层子群组的具体实现（`GetSmithJointGGXAnisoPartLambdaV`、`DV_SmithJointGGXAniso`）
- [ ] `DeBug` 输出的含义（推测为中间值调试输出，Unity 侧可忽略）
- [ ] `clampedRoughness` 与 `roughnessT/B` 的关系（是否为各向同性 roughness 还是夹紧后的版本）
