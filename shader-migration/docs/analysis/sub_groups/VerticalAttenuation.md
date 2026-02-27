# VerticalAttenuation

> 溯源：`docs/raw_data/Vertical_attenuation_20260227.json` | 节点数：6

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | （无） | — |
| 输出 | `Vertical attenuation` | Float |

## 内部节点

`NEW_GEOMETRY.Normal` → `SeparateXYZ.003.Z` → `MATH.023` → `MATH.024` → `GROUP_OUTPUT`

## 等价公式

```
// 取几何法线的 Z（上方向）分量
normalZ = geometry.normal.z   // Blender Z = 世界空间"上"方向
vertical_atten = f(normalZ)   // 某种映射（推测为 saturate 或 pow）
```

用法线 Z 分量来控制 Rim 光在顶部强、底部弱的衰减效果。

## HLSL 等价

```hlsl
float VerticalAttenuation(float3 normalWS)
{
    float upFactor = normalWS.y; // Unity Y = up（对应 Blender Z）
    return saturate(upFactor);   // 法线朝上时衰减为 1，朝下为 0
    // 实际可能有额外幂次或映射，待精确测量
}
```

## 备注

- Blender `NEW_GEOMETRY` 输出的 `Normal` 是**物体/世界空间**法线（与 `ShaderNodeNormalMap` 不同）
- Unity 中对应 `IN.normalWS.y`（URP）
- 无输入参数，行为完全由曲面法线朝向决定
