# ComputeFresnel0

> 溯源：`docs/raw_data/ComputeFresnel0_20260227.json` | 节点数：4
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `ComputeFresnel0()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `BaseColor` | Color |
| 输入 | `metallic` | Float |
| 输入 | `dielectricF0` | Color |
| 输出 | `输出` | Color |

## 内部节点

`GROUP_INPUT` → `MIX`(dielectricF0, BaseColor, metallic) → `REROUTE.012` → `GROUP_OUTPUT`

## 等价公式

```
F0 = lerp(dielectricF0, BaseColor, metallic)
```

标准 PBR F0 计算：
- 非金属（metallic=0）：F0 = dielectricF0（通常为 0.04）
- 金属（metallic=1）：F0 = BaseColor（金属直接将反射率编码为颜色）

## HLSL 等价

```hlsl
float3 ComputeFresnel0(float3 baseColor, float metallic, float3 dielectricF0 = 0.04)
{
    return lerp(dielectricF0, baseColor, metallic);
}
```

## 备注

`dielectricF0` 对应折射率约 1.5（玻璃/皮肤/布料等常见介电体）。
与 HDRP `GetFresnel0(BSDFData)` 逻辑相同。
