# FresnelAttenuation

> 溯源：`docs/raw_data/Fresnel_attenuation_20260227.json` | 节点数：6
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `FresnelAttenuation()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `NoV` | Float |
| 输出 | `Fresnel attenuation` | Float |

## 内部节点

`GROUP_INPUT.NoV` → `MATH.022` → `REROUTE.093` → `MATH.019`(×自身) → `MATH.021`(×自身) → `GROUP_OUTPUT`

连线模式：019 和 021 均以同一值同时接入 A 和 B → 实现连续平方。

## 等价公式

```
// MATH.022 推测为 ONE_MINUS：(1 - NoV)
t = 1 - NoV
// MATH.019 = t * t = (1-NoV)²
// MATH.021 = t² * t² = (1-NoV)⁴
result = (1 - NoV)^4
```

近似 Schlick Fresnel 幂次项，用于 Rim 光的视角衰减（grazing angle 处 Rim 最强）。

## HLSL 等价

```hlsl
float FresnelAttenuation(float NoV)
{
    float t = 1.0 - NoV;
    float t2 = t * t;
    return t2 * t2; // (1-NoV)^4
}
```

## 备注

- 与 `F_Schlick` 中的 Fresnel 不同：这里是近似 Rim 强度的简化形式，不需要 f0/f90
- 结合 `VerticalAttenuation` 和 `DepthRim` 三路叠加形成最终 Rim 遮罩
