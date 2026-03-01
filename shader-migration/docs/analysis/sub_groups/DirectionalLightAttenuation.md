# DirectionalLightAttenuation

> 溯源：`docs/raw_data/Directional_light_attenuation_20260227.json` | 节点数：5
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `DirectionalLightAttenuation()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `NoL_Unsaturate` | Float |
| 输入 | `Directional light attenuation adjust` | Float |
| 输出 | `结果` | Float |

## 内部节点

`GROUP_INPUT` → `CLAMP.005`(NoL_Unsaturate) → `MIX.013`(Factor=clamped, A=adjust_value, B=?) → `GROUP_OUTPUT`

`MATH.025`(adjust 处理) → `MIX.013.A`

## 等价公式

```
clamped = clamp(NoL_Unsaturate, 0, 1)
result = lerp(adjust_value, B, clamped)
```

将 NoL（法线点积光向量）截断后，根据调整参数做线性混合，控制平行光在几何背面的衰减行为。

## HLSL 等价

```hlsl
float DirectionalLightAttenuation(float NoL_unsaturate, float attenuationAdjust)
{
    float clamped = saturate(NoL_unsaturate);
    return lerp(attenuationAdjust, 1.0, clamped);
    // B 端推测为 1.0（完全受光），A 端为调整值（背光区保留量）
}
```

## 备注

- `adjust` 参数允许背光面保留少量光照（避免完全黑面），类似 `wrap lighting`
- 与 SigmoidSharp 分支叠加使用，SigmoidSharp 控制过渡曲线形状，本节点控制平行光最终响应系数
