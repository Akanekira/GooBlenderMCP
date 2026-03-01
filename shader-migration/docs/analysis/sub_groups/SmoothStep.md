# SmoothStep

> 溯源：`docs/raw_data/SmoothStep_20260227.json` | 节点数：17
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `SmoothStep()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `min` | Float |
| 输入 | `max` | Float |
| 输入 | `x` | Float |
| 输出 | `输出` | Float |

## 内部节点

`GROUP_INPUT` → 3×`REROUTE`(min/max/x) → `MATH`(归一化) → `MATH.001` → `MATH.002` → `CLAMP` → `REROUTE.003` → `MATH.003/004/005/006` → `GROUP_OUTPUT`

## 等价公式

```
t = clamp((x - min) / (max - min), 0, 1)
smoothstep = t * t * (3 - 2 * t)
```

标准三次 Hermite 插值 SmoothStep，与 GLSL/HLSL 内置 `smoothstep` 等价。

## HLSL 等价

```hlsl
float SmoothStepCustom(float minVal, float maxVal, float x)
{
    float t = clamp((x - minVal) / (maxVal - minVal), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
```

> 注：Unity HLSL 中直接使用内置 `smoothstep(min, max, x)` 即可，无需自定义。

## 用途

在主群组中调用两次，用于：
- Toon Fresnel 的 `_ToonfresnelSMO_L / _H` 平滑边缘
- 其他需要软边缘过渡的区域
