# GetPreIntegratedFGD（子群组 Remap01ToHalfTexelCoord）

> 溯源：在 `GetPreIntegratedFGDGGXAndDisneyDiffuse_20260227.json` 中发现，第三层子群组
> 本群组 JSON 尚未单独提取（Phase 1.4）

## 功能描述

将 [0, 1] 范围内的 UV 坐标重映射到纹理有效像素中心范围，避免双线性插值时采样到纹理边界外的像素。

## 等价公式

```
// 设 LUT 分辨率为 N（如 512）
remap(u, N) = u * (1 - 1/N) + 0.5/N
            = u * (N-1)/N + 0.5/N
```

## HLSL 等价

```hlsl
float Remap01ToHalfTexelCoord(float u, float texSize)
{
    return u * ((texSize - 1.0) / texSize) + (0.5 / texSize);
}
// 通常 texSize = 512.0（FGD LUT 标准分辨率）
```

---

# GetinvLenLV

> 溯源：在 `Get_NoH_LoH_ToH_BoH_20260227.json` 中发现，第三层子群组
> 本群组 JSON 尚未单独提取（Phase 1.4）

## 功能描述

计算 `1 / |L + V|`，用于从已知点积推导半角向量 H 的各点积。

## 等价公式

```
|L + V|² = |L|² + 2·LoV + |V|² = 2 + 2·LoV （单位向量）
invLenLV = 1 / sqrt(2 + 2·LoV) = rsqrt(2·(1 + LoV))
```

## HLSL 等价

```hlsl
float GetInvLenLV(float LoV)
{
    return rsqrt(max(2.0 * (1.0 + LoV), FLT_EPS));
}
```
