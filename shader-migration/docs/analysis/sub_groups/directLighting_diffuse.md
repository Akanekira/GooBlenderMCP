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
// VALUE 节点 = 0.31831（1/π，Lambertian 归一化系数）
directLighting_diffuse = (shadowRampColor × (1/π)) × diffuseColor × 矢量 × directOcclusion
```

展开为串行乘积（与节点拓扑一致）：
```
temp = shadowRampColor × 0.31831   // VectorMath.008：乘 1/π，保证漫反射能量守恒
temp = temp × diffuseColor         // VectorMath.009
temp = temp × dirLightColor        // VectorMath.010（矢量 = dirLight_lightColor）
result = temp × directOcclusion    // VectorMath.011
```

---

## 💻 HLSL 等价

```cpp
float3 DirectLightingDiffuse(
    float3 shadowRampColor,
    float3 directOcclusion,
    float3 diffuseColor,
    float3 dirLightColor)
{
    // 1/π 归一化：Lambertian BRDF = albedo/π，保证半球积分能量守恒
    // 即使是 Toon 风格，PBRToon 仍在漫反射项保留此物理系数
    return (shadowRampColor * (1.0 / 3.14159265)) * diffuseColor * dirLightColor * directOcclusion;
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

- ✅ ~~`VALUE` 节点的数值~~ ← 已确认 = **0.31831（1/π，Lambertian 归一化系数）**（2026-03-05）
- ✅ ~~`矢量` 插槽的具体含义~~ ← 已确认 = `dirLight_lightColor`（2026-03-04）
