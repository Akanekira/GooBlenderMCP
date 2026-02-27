# PerceptualRoughnessToRoughness

> 溯源：`docs/raw_data/PerceptualRoughnessToRoughness_20260227.json` | 节点数：5

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `perceptualRoughness` | Float |
| 输出 | `roughness` | Float |

## 内部节点

`GROUP_INPUT` → `MATH.002`(x×x，同一值接入 A 和 B) → `REROUTE.009` → `GROUP_OUTPUT`

## 等价公式

```
roughness = perceptualRoughness²
```

将感知粗糙度转换为物理（GGX）粗糙度。感知粗糙度是线性的，物理粗糙度是其平方。

## HLSL 等价

```hlsl
float PerceptualRoughnessToRoughness(float perceptualRoughness)
{
    return perceptualRoughness * perceptualRoughness;
}
```

## 用途

在主群组中调用 3 次，分别对应：
1. 等向性 roughness（送入 `DV_SmithJointGGX_Aniso.clampedRoughness`）
2. 各向异性 T 轴 roughnessT
3. 各向异性 B 轴 roughnessB
