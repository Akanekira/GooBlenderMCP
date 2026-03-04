# directLighting_diffuse

> 溯源：`docs/raw_data/directLighting_diffuse_20260227.json` · 7 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `directLighting_diffuse()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `shadowRampColor` | Color | — |
| `directOcclusion` | Color | — |
| `diffuseColor` | Color | — |
| `矢量` | Vector | **已确认 = `dirLight_lightColor`（Group Input，平行光颜色 RGBA）**，非光方向向量 |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `directLighting_diffuse` | Color | — |

---

## 🔗 内部节点

```
VALUE(常量) ──────→ VectorMath.008(MULTIPLY)
shadowRampColor ──→ VectorMath.008
VectorMath.008 ──→ VectorMath.009
diffuseColor ────→ VectorMath.009(MULTIPLY)
矢量 ────────────→ VectorMath.010
VectorMath.009 ──→ VectorMath.010(MULTIPLY)
directOcclusion ─→ VectorMath.011
VectorMath.010 ──→ VectorMath.011(MULTIPLY)
VectorMath.011 ──→ GROUP_OUTPUT
```

---

## 🧮 等价公式

```
// VALUE 节点推测为 1.0（保留原始值）
directLighting_diffuse = shadowRampColor * diffuseColor * 矢量 * directOcclusion
```

或更精确地（考虑到 VALUE 的作用）：
```
temp = shadowRampColor × VALUE_const
temp = temp × diffuseColor
temp = temp × lightDir_factor（矢量）
result = temp × directOcclusion
```

---

## 💻 HLSL 等价

```cpp
float3 DirectLightingDiffuse(
    float3 shadowRampColor,
    float3 directOcclusion,
    float3 diffuseColor,
    float3 lightDirFactor)
{
    return shadowRampColor * diffuseColor * lightDirFactor * directOcclusion;
}
```

---

## 📝 备注

- `shadowRampColor`：来自 `RampSelect` 的 Toon 阴影色带颜色
- `directOcclusion`：来自 `_P.G`（AO 通道），已由 `directOcclusionColor` 叠加（混合.005.Result）
- `矢量`：**已确认 = `dirLight_lightColor`**（Group Input，平行光颜色 Vector）
- `VALUE` 常量可能是光照强度缩放，待从节点默认值确认

---

## ❓ 待确认

- [ ] `VALUE` 节点的数值（光照强度缩放系数？）
- ✅ ~~`矢量` 插槽的具体含义~~ ← 已确认 = `dirLight_lightColor`（2026-03-04）
