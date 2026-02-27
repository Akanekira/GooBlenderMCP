# SigmoidSharp

> 溯源：`docs/raw_data/SigmoidSharp_20260227.json` | 节点数：8

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `x` | Float |
| 输入 | `center` | Float |
| 输入 | `sharp` | Float |
| 输出 | `值(明度)` | Float |

## 内部节点

`GROUP_INPUT` → `MATH.004`(减法 x-center) → `MATH.005`(乘法 ×sharp) → `MATH.002` → `MATH.006` → `MATH.007` → `GROUP_OUTPUT`

`MATH.003`(处理 sharp) 并联进 `MATH.005`

## 等价公式

```
t = sharp * (x - center)
sigmoid_sharp = 1 / (1 + exp(-t))
```

标准 Sigmoid 的可控版本：`sharp` 控制过渡陡峭程度，`center` 控制过渡中心点。

## HLSL 等价

```hlsl
float SigmoidSharp(float x, float center, float sharp)
{
    float t = sharp * (x - center);
    return 1.0 / (1.0 + exp(-t));
}
```

## 用途

在主群组中调用两次：
1. halfLambert 阴影边缘过渡（参数：`RemaphalfLambert_center/sharp`）
2. CastShadow 投影阴影过渡（参数：`CastShadow_center/sharp`）

## 备注

与标准 smoothstep 不同，Sigmoid 曲线两端趋近于 0/1 但不裁剪，适合做可控的软边缘 Toon 过渡。
