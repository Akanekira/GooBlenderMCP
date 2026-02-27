# Rim_Color

> 溯源：`docs/raw_data/Rim_Color_20260227.json` | 节点数：11

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `albedo` | Color |
| 输入 | `dirLight_lightColor` | Color |
| 输入 | `Rim_Color` | Color |
| 输入 | `Rim_ColorStrength` | Float |
| 输入 | `LoV` | Float |
| 输出 | `结果` | Color |

## 内部节点

```
GROUP_INPUT
    LoV ──→ MATH.030 → CLAMP.004 → MIX.014(Factor)
    Rim_Color + dirLight_lightColor → MIX.015
    albedo → MIX.016
    Rim_ColorStrength → MIX.017
```

## 等价公式

```
// LoV 衰减（LoV = dot(L, V)，正面受光时 Rim 减弱）
loV_factor = clamp(f(LoV), 0, 1)

// 色彩混合：Rim 颜色与平行光颜色混合
rimColorMixed = lerp(Rim_Color, dirLight_lightColor, ...)

// albedo 混合：让 Rim 带上表面颜色
colorWithAlbedo = lerp(rimColorMixed, albedo, ...)

// 强度缩放
result = colorWithAlbedo * Rim_ColorStrength
```

## HLSL 等价

```hlsl
float3 RimColor(
    float3 albedo,
    float3 dirLightColor,
    float3 rimColor,
    float rimColorStrength,
    float LoV)
{
    // LoV 影响：当光从正面照射时降低 Rim 强度
    float loVFactor = saturate(LoV * 0.5 + 0.5); // 推测映射

    // Rim 颜色 = Rim_Color 与平行光颜色混合
    float3 blendedColor = lerp(rimColor, dirLightColor, loVFactor);

    // 带上 albedo 染色
    blendedColor = lerp(blendedColor, albedo * blendedColor, 0.5); // 系数待确认

    return blendedColor * rimColorStrength;
}
```

## 备注

- `LoV` = `dot(L, V)`，用于区分光源方向与视角方向的关系，防止 Rim 在光照正面过亮
- 该 Rim 颜色会与 `DepthRim × FresnelAttenuation × VerticalAttenuation` 组成的遮罩相乘
- 具体 MIX 系数需从节点默认值确认（此版本为逻辑推断）
