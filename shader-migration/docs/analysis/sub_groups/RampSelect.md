# RampSelect

> 溯源：`docs/raw_data/RampSelect_20260227.json` | 节点数：41
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `RampSelect()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `RampUV` | Float |
| 输入 | `RampIndex` | Float |
| 输出 | `RampColor` | Color |
| 输出 | `RampAlpha` | Float |

## 内部节点结构

```
GROUP_INPUT.RampUV ──→ 5 × TEX_IMAGE（5条色带贴图）
GROUP_INPUT.RampIndex → MATH×4（生成各段 [0,1] 权重）→ MIX×6（逐步混合）
TEX_IMAGE × 5 .Color/Alpha → MIX 混合链 → GROUP_OUTPUT
```

### 贴图节点（5 张色带 LUT）

| 节点 | 用途 |
|------|------|
| `图像纹理` | Ramp #0（默认/基础阴影） |
| `图像纹理.001` | Ramp #1 |
| `图像纹理.004` | Ramp #2 |
| `图像纹理.005` | Ramp #3 |
| `图像纹理.006` | Ramp #4 |

> **注**：5 张贴图均为**内嵌贴图**（打包在 .blend 中），图像名称未在 JSON 中暴露。实际文件可能是 `TPLK_*_RD.png` 系列的多张 Ramp。

## 混合逻辑（RampIndex 选择）

```
// RampIndex 范围 [0, 4]，对应 5 条色带
// MATH 节点生成各 Ramp 的混合系数（类似 if-else 分段）
weight_0 = step(RampIndex, 0.5)
weight_1 = clamp(RampIndex - 0.5, 0, 1) * step(...)
...

// 每条 Ramp 采样（RampUV 为横向）
color_n = tex2D(ramp_n, float2(RampUV, 0.5))

// 线性混合
RampColor = lerp(color_0, lerp(color_1, lerp(color_2, lerp(color_3, color_4, w4), w3), w2), w1)
```

## HLSL 等价

```hlsl
// Unity 侧建议：将5条 Ramp 合并为一张竖向 LUT
// 每行对应一条 Ramp，用 RampIndex/4 作为 V 坐标
TEXTURE2D(_RampLUT);
SAMPLER(sampler_RampLUT);

void RampSelect(float rampUV, float rampIndex,
                out float3 rampColor, out float rampAlpha)
{
    float v = (rampIndex + 0.5) / 5.0; // 5行 LUT
    float4 sample = SAMPLE_TEXTURE2D(_RampLUT, sampler_RampLUT, float2(rampUV, v));
    rampColor = sample.rgb;
    rampAlpha = sample.a;
}
```

## 备注

- RampUV 输入来源：`_P.A`（材质参数贴图 Alpha 通道）
- RampIndex 来源：材质参数 `RampIndex`（Float 控制器，决定用哪条色带表现阴影）
- 实际色带贴图内容需从 Blender 导出确认（5 条对应不同材质类型：皮肤/布料/金属/发丝等）
- **Unity 迁移建议**：将 5 张 1D Ramp 合并为 5×N 的 2D LUT 贴图，减少纹理采样次数
