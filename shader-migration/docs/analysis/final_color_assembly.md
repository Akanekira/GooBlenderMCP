# 最终颜色汇总流程（Final Color Assembly）

> 溯源：`Arknights: Endfield_PBRToonBase` 主群组
> 数据来源：2026-02-28 Blender MCP 实时追踪
> 关联文档：[01_shader_arch.md](01_shader_arch.md)、[ComputeDiffuseColor.md](sub_groups/ComputeDiffuseColor.md)

---

## 概览

所有光照分量以**串行 ADD/MULTIPLY** 依次叠加，最终经 `色相/饱和度/明度`（HSV）节点做阴影去饱和处理后输出。

```
Direct Diffuse ──┐
Specular        ─┤ ADD → Vector Math.015
Indirect Spec   ─┘
                        ↓
Indirect Diffuse Compensate ─ ADD → 混合.011
                                      ↓
Indirect Diffuse (FGD×Ambient) ── ADD → 混合.009  ← 光照全部汇合
                                                ↓
                                    × ShadowMask   混合.004  (Frame.007)
                                                ↓
                                    × ToonFresnel  混合.012  (Frame.008)
                                                ↓
                                    + Rim          混合.019  (Frame.009)
                                                ↓
                                    + Emission     混合.026  (Frame.010)
                                                ↓
                                    LIGHTEN RS     混合.029  (帧.048 RS EFF)
                                    MIX RS         混合.030
                                                ↓
                                    HSV Saturation 色相/饱和度/明度  (帧.071)
                                                ↓
                                         ShaderOutput → Result
```

---

## 各分量合入位置

| 分量 | 合入节点 | 操作 | 来源 Frame |
|------|---------|------|-----------|
| Direct Diffuse | `Vector Math.015` | ADD | Frame.005 DiffuseBRDF |
| Specular (iso) | `Vector Math.015` | ADD | Frame.004 SpecularBRDF |
| Specular (aniso) | `Vector Math.015` | ADD | Frame.004 SpecularBRDF |
| AO / directOcclusion | specular 路径内 | 调制 directOcclusionColor | Frame.013 GetSurfaceData |
| 间接镜面补偿 (energyCompensation) | `混合.011` | ADD | Frame.006 IndirectLighting |
| Indirect Diffuse (FGD × Ambient) | `混合.009` | ADD | Frame.006 IndirectLighting |
| ShadowMask (RampAlpha) | `混合.004` | MULTIPLY | Frame.007 ShadowAdjust |
| ToonFresnel 颜色 | `混合.012` | MULTIPLY | Frame.008 ToonFresnel |
| Rim 边缘光 | `混合.019` | ADD | Frame.009 Rim |
| Emission 自发光 | `混合.026` | ADD | Frame.010 Emission |
| RS EFF 特效 | `混合.029/030` | LIGHTEN + MIX | 帧.048 RS EFF |
| 阴影去饱和 | `色相/饱和度/明度` | HSV.Saturation | 帧.071 |

---

## 关键汇合节点详解

### Vector Math.015 (ADD) — 直接光 + Specular 首次汇合

```
A = directLighting_diffuse 输出        ← 群组.019 (Frame.005)
B = specular × SpecularColor × dirLight × SH修正项
    └ 路径：DV×F → iso/aniso混合 → ×SpecularColor → ×directOcclusion → ×ShaderInfo → ×energyComp
```

> Specular 与 Direct Diffuse **在同一个 ADD 节点合并**，不是后期分开叠加。

### 混合.011 (ADD) — 叠加间接镜面补偿

```
A = Vector Math.015 (direct + specular)
B = 混合.010 (MULTIPLY)
      = (1 - reflectivity/FGD) × specFGD_Strength
      语义：能量守恒补偿，避免高光区漫反射过亮
```

### 混合.009 (ADD) — 直接光 + 间接光全部汇合

```
A = 混合.011 (direct diffuse + specular + 间接镜面补偿)
B = 混合.008 (MULTIPLY)
      = diffuseColor × FGD_DisneyDiffuse × (AmbientLightColorTint × ShaderInfo)
      语义：间接漫反射（环境光 × 预积分 FGD）
```

### 混合.004 (MULTIPLY) — ShadowAdjust

```
A = 混合.009
B = clamp(SmoothStep(RampSelect.RampAlpha, GlobalShadowBrightnessAdjustment))
语义：用 Ramp Alpha 驱动全局阴影亮度下限，防止阴影全黑
```

### 混合.012 (MULTIPLY) — ToonFresnel 颜色调制

```
A = 混合.004
B = lerp(fresnelInsideColor, fresnelOutsideColor, SmoothStep(LayerWeight))
语义：视角边缘内/外侧颜色渐变（Toon 风格边缘色）
```

### 混合.019 (ADD) — Rim 叠加

```
A = 混合.012
B = Rim_Color × DirLightAtten × (DepthRim × FresnelAtten × VerticalAtten)
```

### 混合.026 (ADD) — Emission 叠加

```
A = 混合.019
B = _E_RGB × EmissionColor
```

### 混合.029/030 — RS EFF（可选特效）

```
混合.029 (LIGHTEN) : max(混合.026, RS_effect) × RS_Multiply_Value
混合.030 (MIX)     : lerp(混合.026, 混合.029, Use_RS_Eff?)
```

---

## 帧.071 — 阴影去饱和（DeSaturation）

`帧.071` 不参与颜色叠加，只控制 HSV 节点的 **Saturation** 通道：

```
RampSelect.RampAlpha
  → DeSaturation(群组.017)           ← 根据 Ramp 计算去饱和强度
  → ADD(运算.005)
      + Color desaturation in shaded areas attenuation  (Group Input)
  → CLAMP(钳制.004)
  → 色相/饱和度/明度 [Saturation]    ← 阴影区饱和度压低
```

HSV 节点的 Color 输入来自 `混合.030`（完整累积色），输出直接进 `ShaderOutput`。

**效果**：RampAlpha 低（深阴影）时 Saturation 降低，实现日式卡通渲染常见的**阴影区色彩变灰**效果。

---

## 等价伪代码

```hlsl
// ① 直接光 + Specular 合并（Frame.005 + Frame.004）
float3 directSpec  = (DV_iso_or_aniso × F_Schlick) × SpecularColor;
float3 directDiff  = directLighting_diffuse(diffuseColor, rampColor, occlusion, dirLight);
float3 color       = (directDiff + directSpec) × directOcclusion × ShaderInfo;

// ② 间接镜面补偿（Frame.006）
float energyComp   = 1.0 - reflectivity / FGD;
color             += energyComp × specFGD_Strength;

// ③ 间接漫反射（Frame.006）
float3 indirectDiff = diffuseColor × FGD_DisneyDiffuse × (AmbientLightColorTint × ShaderInfo);
color              += indirectDiff;

// ④ ShadowAdjust（Frame.007）
float shadowMask   = clamp(SmoothStep(RampAlpha, GlobalShadowBrightnessAdjustment));
color             *= shadowMask;

// ⑤ ToonFresnel（Frame.008）
float3 fresnelCol  = lerp(fresnelInsideColor, fresnelOutsideColor,
                          SmoothStep(LayerWeight(blend), SMO_L, SMO_H));
color             *= fresnelCol;

// ⑥ Rim（Frame.009）
color += rimColor;

// ⑦ Emission（Frame.010）
color += _E_RGB * EmissionColor;

// ⑧ RS EFF（帧.048，可选）
color = lerp(color, max(color, RS_eff) * RS_strength, Use_RS_Eff);

// ⑨ 阴影去饱和（帧.071）
float sat = clamp(DeSaturation(RampAlpha) + color_desaturation_attenuation);
color = HueSaturationValue(color, hue=0.5, saturation=sat, value=1.0);

// → ShaderOutput
```
