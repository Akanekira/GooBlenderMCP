# ComputeDiffuseColor

> 溯源：`docs/raw_data/ComputeDiffuseColor_20260227.json` | 节点数：5

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `albedo` | Color |
| 输入 | `metallic` | Float |
| 输出 | `输出` | Color |

## 内部节点

`GROUP_INPUT` → `REROUTE.045`(albedo) + `MATH`(1-metallic) → `VECT_MATH`(MULTIPLY) → `GROUP_OUTPUT`

## 等价公式

```
diffuseColor = albedo * (1 - metallic)
```

标准 PBR 金属工作流：金属部分不产生漫反射，`metallic=1` 时漫反射为 0。

## HLSL 等价

```hlsl
float3 ComputeDiffuseColor(float3 albedo, float metallic)
{
    return albedo * (1.0 - metallic);
}
```

## 备注

与 HDRP `GetDiffuseColor(BSDFData)` 逻辑相同。在材质中：
- `albedo` = `_D.RGB`
- `metallic` = `_P.R × MetallicMax`
