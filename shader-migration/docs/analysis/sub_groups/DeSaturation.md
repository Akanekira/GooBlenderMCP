# DeSaturation

> 溯源：`docs/raw_data/DeSaturation_20260227.json` · 11 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `DeSaturation()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `DeSaturation` | Float | — |
| `Color` | Color | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `Vector` | Color | — |

---

## 🔗 内部节点

```
Color ──→ REROUTE.159 ──→ VectorMath.004(DOT)  ← CombineXYZ.002(亮度权重)
                     └──→ VectorMath.005
VectorMath.004.Value(亮度) ──→ VectorMath.005
                         └──→ VectorMath.007
DeSaturation ──→ REROUTE.160 ──→ VectorMath.006
VectorMath.005 ──→ VectorMath.006(MULTIPLY/SCALE)
VectorMath.006 ──→ VectorMath.007(ADD/lerp)
VectorMath.007 ──→ GROUP_OUTPUT
```

---

## 🧮 等价公式

```
// 亮度权重（Rec. 709 / 感知亮度）
luma = dot(Color, float3(0.299, 0.587, 0.114))
// 去饱和：线性插值 Color 和 luma.xxx
result = lerp(Color, luma.xxx, DeSaturation)
```

等价于：
```
result = Color + DeSaturation * (luma.xxx - Color)
       = Color * (1 - DeSaturation) + luma * DeSaturation
```

---

## 💻 HLSL 等价

```cpp
float3 DeSaturation(float factor, float3 color)
{
    // CombineXYZ.002 存储亮度权重，推测为 Rec.709 标准
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    return lerp(color, luma.xxx, factor);
}
```

---

## 📌 用途

在主群组中用于暗部去饱和：当区域处于阴影时，颜色趋向灰度，模拟 Toon 卡通风格的暗部色调压缩。

---

## 📝 备注

- `CombineXYZ.002` 存储亮度权重常量（推测为 Rec.709 或 Rec.601，待从节点默认值确认）
- 等价于 Blender `HUE_SAT` 节点的去饱和，但这里用自定义向量运算实现

---

## ❓ 待确认

- [ ] 待补充
