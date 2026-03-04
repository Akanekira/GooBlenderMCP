# ComputeDiffuseColor

> 溯源：`docs/raw_data/ComputeDiffuseColor_20260227.json` · 5 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `ComputeDiffuseColor()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `albedo` | Color | — |
| `metallic` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `输出` | Color | — |

---

## 🔗 内部节点

`GROUP_INPUT` → `REROUTE.045`(albedo) + `MATH`(1-metallic) → `VECT_MATH`(MULTIPLY) → `GROUP_OUTPUT`

---

## 🧮 等价公式

```
diffuseColor = albedo * (1 - metallic)
```

标准 PBR 金属工作流：金属部分不产生漫反射，`metallic=1` 时漫反射为 0。

---

## 💻 HLSL 等价

```cpp
float3 ComputeDiffuseColor(float3 albedo, float metallic)
{
    return albedo * (1.0 - metallic);
}
```

---

## 📝 备注

与 HDRP `GetDiffuseColor(BSDFData)` 逻辑相同。在材质中：
- `albedo` = `_D.RGB`
- `metallic` = `_P.R × MetallicMax`

---

## 📌 主群组中的输出流向

> 追踪范围：`Arknights: Endfield_PBRToonBase` 主群组，节点 `群组.009`（ComputeDiffuseColor）输出后的完整路径。
> 数据来源：2026-02-28 Blender MCP 实时追踪。

### 分叉点：两条并行路径

`群组.009.输出` 经过 REROUTE 链（转接点.048 → Reroute.056 → Reroute.054 → Reroute.094 → Reroute.012）后，**同时输入两个目标**：

| 目标节点 | 所属 Frame | 接收 socket | 语义 |
|----------|-----------|------------|------|
| `群组.019` (directLighting_diffuse) | Frame.005 DiffuseBRDF | `diffuseColor` | 直接光漫反射 |
| `混合.007` (MIX MULTIPLY) | Frame.006 IndirectLighting | `A` | 间接光漫反射 |

---

### 路径 A — 直接光 (DiffuseBRDF)

```
群组.009.输出 (diffuseColor)
  └─→ 群组.019 (directLighting_diffuse) [socket: diffuseColor]
        输出: directLighting_diffuse
        └─→ Vector Math.015 (ADD)
              ← 同时接收 Vector Math.014 (MULTIPLY)
                  Vector Math.014 的输入：
                    - Vector Math.007 (MULTIPLY)：混合.005(directOcclusionColor MIX) × Vector Math.005
                    - Vector Math.013 (ADD, IndirectLighting)：SH 间接漫反射修正项
              └─→ 混合.011 (ADD)
                    B ← 混合.010 (MULTIPLY, IndirectLighting)
                          A ← 运算.013 (SUBTRACT)
                          B ← 混合.025 (MULTIPLY)：specularFGD_Strength × GetPreIntegratedFGD.Output
                    └─→ 混合.009 (ADD)  ← 直接+间接汇合点 [A 端]
```

`群组.019` 的职责：将 `diffuseColor` 乘以经 Toon Ramp 调制后的直接光颜色，见 [directLighting_diffuse.md](directLighting_diffuse.md)。

---

### 路径 B — 间接光 (IndirectLighting)

```
群组.009.输出 (diffuseColor)
  └─→ 混合.007 (MULTIPLY, Frame.006 IndirectLighting)
        A = diffuseColor
        B = 群组.005.Output (GetPreIntegratedFGDGGXAndDisneyDiffuse)
            ↑ FGD 预积分 LUT 中的 Disney Diffuse 项
        └─→ 混合.008 (MULTIPLY)
              B = 混合.013 (MULTIPLY)
                    A = AmbientLightColorTint  (Group Input)
                    B = Shader Info            (SHADERINFO 节点, GetSurfaceData frame)
              └─→ 混合.009 (ADD)  ← 直接+间接汇合点 [B 端]
```

等价计算：
```
indirectDiffuse = diffuseColor
                × FGD_DisneyDiffuse(NdotV, perceptualRoughness)
                × (AmbientLightColorTint × ShaderInfo)
```

---

### 汇合后的后处理链

```
混合.009 (ADD) = directDiffuse + indirectDiffuse
  │
  └─→ 混合.004 (MULTIPLY) [ShadowAdjust]
        B = 钳制.006 (CLAMP MINMAX)
              Max ← 群组.012 (SmoothStep)
                      x   = 群组.011 (RampSelect).RampAlpha
                      min = GlobalShadowBrightnessAdjustment
        语义：shadowMask = clamp(SmoothStep(RampAlpha, GlobalShadowBrightnessAdjustment))
              diffuse *= shadowMask   // 全局阴影亮度下限控制
  │
  └─→ 混合.012 (MULTIPLY) [ToonFresnel 调制]
        B = 混合.006 (MIX, Frame.008 ToonFresnel)
              Factor ← 群组.010 (SmoothStep)   // Fresnel 平滑曲线
              A      ← fresnelInsideColor
              B      ← fresnelOutsideColor
        语义：diffuse *= lerp(fresnelInside, fresnelOutside, fresnelFactor)
  │
  └─→ 混合.019 (ADD) [Rim 叠加]
        B ← 混合.018 (Frame.009 Rim 的最终输出)
        语义：diffuse += rimColor
  │
  └─→ 混合.026 (ADD) [Emission 叠加]
        B = 混合.021 (MULTIPLY, Frame.010 Emission)
              A ← _E (Emission 贴图 RGB)
              B ← Emission Color (Group Input)
        语义：diffuse += _E × EmissionColor
  │
  └─→ RS EFF 分支 (Frame.011 / 框.048)
        ├─→ 混合.029 (LIGHTEN)：取 diffuse 与 RS 效果的较亮值
        └─→ 混合.030 (MIX)：最终 RS 颜色混合
              └─→ ShaderOutput → GROUP_OUTPUT
```

---

### 💻 完整伪代码

```cpp
// GetSurfaceData (Frame.013)
float3 diffuseColor = ComputeDiffuseColor(_D_RGB, _P_R * MetallicMax);

// DiffuseBRDF (Frame.005) — 直接光
float3 directDiff = directLighting_diffuse(diffuseColor, rampColor, occlusion, dirLight);
// + 间接漫反射修正项（directOcclusionColor × SH）
directDiff = directDiff + directOcclusionColor * SH_indirect;

// IndirectLighting (Frame.006) — 间接光
float3 indirectDiff = diffuseColor
                    * FGD_DisneyDiffuse(NdotV, perceptualRoughness)
                    * (AmbientLightColorTint * ShaderInfo);

// 合并
float3 color = directDiff + indirectDiff;

// ShadowAdjust (Frame.007)
float shadowMask = clamp(SmoothStep(RampSelect_RampAlpha, GlobalShadowBrightnessAdjustment), 0, 1);
color *= shadowMask;

// ToonFresnel (Frame.008)
float fresnelFactor = SmoothStep(LayerWeight(...), SMO_L, SMO_H);
color *= lerp(fresnelInsideColor, fresnelOutsideColor, pow(fresnelFactor, ToonfresnelPow));

// Rim (Frame.009)
color += rimColor;  // DepthRim × FresnelAtten × VerticalAtten × Rim_Color × DirLightAtten

// Emission (Frame.010)
color += _E_RGB * EmissionColor;

// RS EFF
color = max(color, RS_eff_color);   // LIGHTEN
color = lerp(color, RS_color, RS_factor);  // MIX

// → ShaderOutput
```

---

### 🗂️ 节点路径索引

| 节点名 | 类型 | 所属 Frame | 语义 |
|--------|------|-----------|------|
| `群组.009` | GROUP (ComputeDiffuseColor) | GetSurfaceData | 计算源 |
| `群组.019` | GROUP (directLighting_diffuse) | DiffuseBRDF | 直接光漫反射 |
| `混合.007` | MIX MULTIPLY | IndirectLighting | diffuseColor × FGD |
| `混合.008` | MIX MULTIPLY | IndirectLighting | × AmbientTint |
| `混合.009` | MIX ADD | — | 直接+间接汇合 |
| `混合.004` | MIX MULTIPLY | — | ShadowAdjust 调制 |
| `钳制.006` | CLAMP | ShadowAdjust | 阴影亮度下限 |
| `混合.012` | MIX MULTIPLY | — | ToonFresnel 调制 |
| `混合.019` | MIX ADD | — | Rim 叠加 |
| `混合.026` | MIX ADD | — | Emission 叠加 |
| `混合.029` | MIX LIGHTEN | RS EFF | RS 效果取亮 |
| `混合.030` | MIX | RS EFF | RS 最终混合 |

---

## ❓ 待确认

- [ ] 待补充
