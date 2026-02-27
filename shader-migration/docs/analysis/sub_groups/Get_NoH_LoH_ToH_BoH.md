# Get_NoH_LoH_ToH_BoH

> 溯源：`docs/raw_data/Get_NoH_LoH_ToH_BoH_20260227.json` | 节点数：17

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `NoL_Unsaturate` | Float |
| 输入 | `NoV` | Float |
| 输入 | `LoV` | Float |
| 输入 | `ToV` | Float |
| 输入 | `ToL` | Float |
| 输入 | `BoV` | Float |
| 输入 | `BoL` | Float |
| 输出 | `NdotH` | Float |
| 输出 | `LdotH` | Float |
| 输出 | `TdotH` | Float |
| 输出 | `BdotH` | Float |

## 内部节点

包含子群组 `GetinvLenLV`（第三层，用于计算 `1/|L+V|`）：

```
NoL + NoV → 求和 → × (1/|L+V|) → NdotH
LoV + 1 → 求和 → × (1/|L+V|) → LdotH（注：非标准，推导见下）
ToL + ToV → 求和 → × (1/|L+V|) → TdotH
BoL + BoV → 求和 → × (1/|L+V|) → BdotH
```

## 等价公式

半角向量 H 的各点积，利用输入的已知点积推导（避免重建向量）：

```
// H = normalize(L + V)，|L+V| = sqrt(2 + 2*LoV)
invLenLV = 1 / sqrt(2 + 2 * LoV)  // GetinvLenLV 子群组

NdotH = (NoL + NoV) * invLenLV
LdotH = (LoV + 1) * invLenLV       // dot(L, H) = (1 + LoV) / |L+V|
TdotH = (ToL + ToV) * invLenLV
BdotH = (BoL + BoV) * invLenLV
```

## HLSL 等价

```hlsl
void Get_NoH_LoH_ToH_BoH(
    float NoL, float NoV, float LoV,
    float ToV, float ToL, float BoV, float BoL,
    out float NdotH, out float LdotH, out float TdotH, out float BdotH)
{
    float invLenLV = rsqrt(max(2.0 * LoV + 2.0, FLT_EPS));
    NdotH = saturate((NoL + NoV) * invLenLV);
    LdotH = saturate((LoV + 1.0) * invLenLV);
    TdotH = (ToL + ToV) * invLenLV;
    BdotH = (BoL + BoV) * invLenLV;
}
```

## 备注

- 这是 HDRP 标准的半角向量点积计算方法（避免 `normalize(L+V)` 的显式向量运算）
- 与 HDRP `GetBSDFAngle(V, L, NdotL, NdotV)` 思路完全一致
- `GetinvLenLV` 子群组（第三层）需单独提取分析
- 部分输出（TdotH/BdotH）无 clamp，因为切线/副切线方向允许负值（各向异性高光需要）
