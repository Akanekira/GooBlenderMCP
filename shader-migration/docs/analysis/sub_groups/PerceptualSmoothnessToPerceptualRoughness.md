# PerceptualSmoothnessToPerceptualRoughness

> 溯源：`docs/raw_data/PerceptualSmoothnessToPerceptualRoughness_20260227.json` | 节点数：5

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `smoothness` | Float |
| 输出 | `perceptualRoughness` | Float |

## 内部节点

`GROUP_INPUT` → `MATH.001`(1-x) → `REROUTE.010` → `GROUP_OUTPUT`

## 等价公式

```
perceptualRoughness = 1 - smoothness
```

## HLSL 等价

```hlsl
float PerceptualSmoothnessToPerceptualRoughness(float smoothness)
{
    return 1.0 - smoothness;
}
```

## 用途

在主群组中调用 3 次（对应 3 套粗糙度）：
1. 等向性：`smoothness = _P.B × SmoothnessMax`
2. 各向异性 T 轴：`× Aniso_SmoothnessMaxT`
3. 各向异性 B 轴：`× Aniso_SmoothnessMaxB`
