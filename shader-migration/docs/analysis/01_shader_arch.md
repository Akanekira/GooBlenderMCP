# 01 — 主群组架构分析：Arknights: Endfield_PBRToonBase

> 溯源：`docs/raw_data/PBRToonBase_full_20260227.json`
> 提取日期：2026-02-27 | **版本 2（基于 Frame 模块结构重写）**

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 437 |
| 连线数 | 410 |
| FRAME 模块节点 | 82（80 个有标签） |
| 顶级模块（Frame.xxx） | 15 |
| 实际逻辑节点 | ~184 |
| 子群组调用数 | 26（20 个唯一群组） |

---

## 顶级模块（Frame）一览

作者通过 Frame 将整个 Shader 拆分为 15 个顶级功能模块：

| Frame | 模块名 | 节点数 | 作用 |
|-------|--------|--------|------|
| `Frame.012` | **Init** | 29 | 几何向量初始化（N/V/L/T/B/NoV/NoL/LoV...） |
| `Frame.013` | **GetSurfaceData** | 24 | 贴图采样与表面参数计算 |
| `Frame.004` | **SpecularBRDF** | 12 | 各向异性 GGX 高光 |
| `Frame.005` | **DiffuseBRDF** | 11 | Toon 漫反射（halfLambert + Ramp） |
| `Frame.006` | **IndirectLighting** | 12 | 间接光照（预积分 FGD + 环境光） |
| `Frame.007` | **ShadowAdjust** | 3 | 阴影过渡调整 |
| `Frame.008` | **ToonFresnel** | 8 | Toon 风格 Fresnel 边缘色 |
| `Frame.009` | **Rim** | 15 | 屏幕空间 Rim 边缘光 |
| `Frame.010` | **Emission** | 3 | 自发光叠加 |
| `Frame.011` | **ThinFilmFilter** | 22 | 视角色变效果（类薄膜/彩虹光） |
| `Frame` | TdotH | — | 各向异性切线半角点积 |
| `Frame.001` | BdotH | — | 各向异性副切线半角点积 |
| `Frame.002` | B from Normalmap | — | 法线贴图副切线重建 |
| `Frame.003` | B(form Normalmap)dotV | — | 副切线·视角点积 |
| `Frame.014` | **Alpha** | 4 | 最终 Alpha 输出 |

其他子级 Frame（框.xxx，约 69 个）为上述模块内部的变量分组标注，详见下方各模块说明。

---

## 整体数据流（基于 Frame 顺序）

```
贴图输入(_D / _N / _P / _E / _M)
        │
        ▼
┌─────────────────────────────────┐
│  Frame.012  Init                │
│  几何向量：N, V, L, T, B        │
│  点积：NoV, NoL, LoV            │
│  子群组：DecodeNormal           │
│          Get_NoH_LoH_ToH_BoH    │
└─────────────┬───────────────────┘
              ▼
┌─────────────────────────────────┐
│  Frame.013  GetSurfaceData      │
│  贴图拆通道：P_R(M)/P_G(AO)/   │
│            P_B(S)/P_A(RampUV)  │
│  子群组：ComputeDiffuseColor    │
│          ComputeFresnel0        │
│          PerceptualSmoothness×3 │
│          PerceptualRoughness×3  │
│          (+SHADERINFO 光照信息) │
└──────┬────────────────┬─────────┘
       │                │
       ▼                ▼
┌────────────┐   ┌──────────────────┐
│Frame.005   │   │  Frame.004        │
│DiffuseBRDF │   │  SpecularBRDF     │
│            │   │                  │
│SigmoidSharp│   │DV_SmithJointGGX  │
│(halfLambert│   │    _Aniso         │
│ CastShadow)│   │F_Schlick          │
│RampSelect  │   └──────┬───────────┘
│directLight │          │
│  _diffuse  │   ┌──────▼───────────┐
└──────┬─────┘   │  Frame.006        │
       │         │  IndirectLighting │
       │         │GetPreIntegratedFGD│
       │         └──────┬───────────┘
       │                │
       └────────┬────────┘
                │
        ┌───────▼──────────┐
        │  Frame.007        │
        │  ShadowAdjust     │
        │  SmoothStep(阴影) │
        └───────┬──────────┘
                │
        ┌───────▼──────────┐
        │  Frame.008        │
        │  ToonFresnel      │
        │  SmoothStep +     │
        │  LayerWeight混合  │
        └───────┬──────────┘
                │
        ┌───────▼──────────┐
        │  Frame.009  Rim   │
        │  DepthRim         │
        │  FresnelAtten     │
        │  VerticalAtten    │
        │  Rim_Color        │
        │  DirLight_Atten   │
        └───────┬──────────┘
                │
        ┌───────▼──────────┐
        │  Frame.010 Emit   │
        │  Emission 叠加    │
        └───────┬──────────┘
                │
        ┌───────▼──────────┐
        │ Frame.011         │
        │ ThinFilmFilter    │
        │ LayerWeight +     │
        │ TEX_IMAGE(LUT) +  │
        │ Fresnel色变       │
        └───────┬──────────┘
                │
        ┌───────▼──────────┐
        │  Frame.014 Alpha  │
        │  ShaderOutput     │
        │  Transparent混合  │
        └───────┬──────────┘
                │
        GROUP_OUTPUT → Result / Debug
```

---

## 各模块详解

### Frame.012 — Init（初始化）

**职责**：从 Blender 几何节点获取所有向量，计算各点积。

| 子框（框.xxx） | 变量 | 来源/计算 |
|--------------|------|-----------|
| `框.002` N | 法线 | `DecodeNormal`(_N.XY, NormalStrength) |
| `框.003` V | 视角方向 | `NEW_GEOMETRY.Incoming`(取反归一化) |
| `框.020` L | 光方向 | `SHADERINFO` |
| `框.022` T | 切线方向 | `TANGENT` |
| `框.055` B | 副切线 | `B from Normalmap`(N×T 叉积重建) |
| `框.004` NoV | dot(N,V) | `VECT_MATH.DOT` |
| `框.005` ClampNdotV | saturate(NoV) | `CLAMP` |
| `框.` NoL_Unsaturate | dot(N,L) | `VECT_MATH.DOT` |
| `框.021` LoV | dot(L,V) | `VECT_MATH.DOT` |
| `框.023/024/025` NdotH/LdotH | 半角点积 | `Get_NoH_LoH_ToH_BoH` |
| `框.056~059` TdotL/BdotL/TdotV/BdotV | 各向异性点积 | `VECT_MATH.DOT` ×4 |

---

### Frame.013 — GetSurfaceData（表面数据）

**职责**：拆解贴图通道，计算物理表面参数。

| 子框 | 变量 | 计算 |
|------|------|------|
| `框.001` albedo | 漫反射基础色 | `_D.RGB`（sRGB） |
| `框.006` P_R | Metallic | `_P.R × MetallicMax` |
| `框.007` P_G | AO/directOcclusion | `_P.G` |
| `框.008` P_B | Smoothness | `_P.B × SmoothnessMax` |
| `框.009` P_A | RampUV | `_P.A` |
| `框.049` AO | 最终 AO | `P_G` 叠加处理 |
| `框.012` metallic | 金属度 | `P_R`（已乘Max） |
| `框.031` diffuseColor | 漫反射色 | `ComputeDiffuseColor(albedo, metallic)` |
| `框.013` fresnel0 | F0 | `ComputeFresnel0(albedo, metallic, 0.04)` |
| `框.010` perceptualRoughness | 感知粗糙度 | `PerceptualSmoothnessToPerceptualRoughness` |
| `框.011` roughness | 物理粗糙度 | `PerceptualRoughnessToRoughness` |
| `框.060~064` roughnessT/B | 各向异性粗糙度 | ×2套（T轴/B轴） |

---

### Frame.005 — DiffuseBRDF（漫反射）

**职责**：计算 Toon 风格直接光漫反射。

```
NoL_Unsaturate
    → SigmoidSharp(RemaphalfLambert_center/sharp) [框.014 RemaphalfLambert]
    → 搭配 CastShadow → shadowArea [框.018]
    → shadowScene [框.019]（投影阴影）
    → RampSelect(RampUV=P_A, RampIndex) → shadowRampColor [框.032]
    → directLighting_diffuse(rampColor, occlusion, diffuseColor, L)
    → directLighting_diffuse [框.033]
```

调用子群组：`SigmoidSharp` ×2、`RampSelect`、`directLighting_diffuse`

---

### Frame.004 — SpecularBRDF（高光）

**职责**：各向异性 GGX 高光计算。

```
(NdotH, Abs_NdotL, NdotV, roughness, TdotH, BdotH, TdotL, BdotL, TdotV, BdotV, roughT, roughB)
    → DV_SmithJointGGX_Aniso → DV项 [框.026 DV / 框.065 AnisoDV]
    → F_Schlick(F0, 1.0, LdotH) → F项 [框.027 F]
    → D×V×F → specTerm [框.028] / specTermAniso [框.066]
    → 等向/各向异性混合 [框.068 Toon Aniso]
    → directLighting_specular [框.034]
```

调用子群组：`DV_SmithJointGGX_Aniso`、`F_Schlick`

---

### Frame.006 — IndirectLighting（间接光照）

**职责**：预积分 FGD 查找 + 环境光叠加。

```
(NdotV, perceptualRoughness, F0)
    → GetPreIntegratedFGDGGXAndDisneyDiffuse(LUT采样)
    → specularFGD [框.038], diffuseFGD [框.037]
    → energyCompensation [框.035] = 1 - reflectivity（能量守恒补偿）
    → indirectLighting.diffuse [框.036] = diffuseColor × diffuseFGD × AmbientLightColorTint
```

调用子群组：`GetPreIntegratedFGDGGXAndDisneyDiffuse`

---

### Frame.007 — ShadowAdjust（阴影调整）

**职责**：全局阴影亮度调整。

```
SmoothStep(GlobalShadowBrightnessAdjustment) → 作用于漫反射阴影区域亮度
```

调用子群组：`SmoothStep`

---

### Frame.008 — ToonFresnel（Toon 边缘色）

**职责**：视角边缘的渐变颜色叠加（内/外侧不同颜色）。

```
LayerWeight(blend=Layer weight Value + Offset) → Fresnel 因子
    → SmoothStep(SMO_L, SMO_H) → 平滑化
    → MIX(fresnelInsideColor, fresnelOutsideColor, factor)
    → pow(ToonfresnelPow) → Toon Fresnel 颜色
```

调用子群组：`SmoothStep`

---

### Frame.009 — Rim（边缘光）

**职责**：屏幕空间深度边缘光，三重遮罩叠加。

```
DepthRim(Rim_width_X/Y) → 深度差遮罩 [框.041]
FresnelAttenuation(NoV) → Fresnel 遮罩 [框.042]
VerticalAttenuation()   → 垂直遮罩 [框.043]
    ↓ 三路相乘
Rim_Color(albedo, dirLight, Rim_Color, Rim_ColorStrength, LoV) → Rim颜色 [框.046]
DirectionalLightAttenuation(NoL, adjust) → 光源方向调制 [框.045]
    ↓ 合并 → Rim [框.047]
```

调用子群组：`DepthRim`、`FresnelAttenuation`、`VerticalAttenuation`、`Rim_Color`、`DirectionalLightAttenuation`

---

### Frame.010 — Emission（自发光）

**职责**：`_E` 贴图自发光叠加。

```
_E.RGB × Emission Color → MIX(ADD 模式) → 叠加到最终输出
```

---

### Frame.011 — ThinFilmFilter（薄膜/彩虹光）

**职责**：视角依赖的颜色变化效果（类薄膜干涉 / 布料光泽 / 金属彩虹光）。

```
LAYER_WEIGHT(blend) → 视角 Fresnel 因子
    → CLAMP → 驱动多个 MIX 节点
TEX_IMAGE → 彩虹 LUT（颜色随视角变化）
fresnelInsideColor + fresnelOutsideColor → 混合
    → ThinFilm 颜色叠加
```

**关键参数**：`fresnelInsideColor`、`fresnelOutsideColor`、`ToonfresnelPow`、`_ToonfresnelSMO_L/H`、`Layer weight Value/Offset`、`RS ColorTint`

> **注意**：ThinFilmFilter 与 ToonFresnel(Frame.008) 共享部分参数，两者协同形成最终边缘色效果。Unity 迁移时需理清两者的叠加顺序。

---

### Frame.014 — Alpha

**职责**：Alpha 透明输出。

```
Alpha(_D.A 或参数) → ShaderOutput(着色结果, Alpha)
    → MIX_SHADER(Transparent, Emission) → Result
```

调用子群组：`ShaderOutput`

---

### 附：其他功能块

| 框 | 功能 | 涉及节点 |
|----|------|---------|
| `框.048` RS EFF | RS 特效叠加 | MIX ×2 |
| `框.069` Simple transmission | 简化透射 | SCREENSPACEINFO + CAMERA + FRESNEL + VECT_MATH |
| `框.051` Emission | 自发光处理 | MIX |
| `框.039` GlobalShadowBrightnessAdjustment | 全局阴影亮度 | MIX |

---

## 子群组 ↔ Frame 归属总表

| 子群组 | 归属 Frame |
|--------|-----------|
| `DecodeNormal` | Init |
| `Get_NoH_LoH_ToH_BoH` | Init |
| `ComputeDiffuseColor` | GetSurfaceData |
| `ComputeFresnel0` | GetSurfaceData |
| `PerceptualSmoothnessToPerceptualRoughness` ×3 | GetSurfaceData |
| `PerceptualRoughnessToRoughness` ×3 | GetSurfaceData |
| `SigmoidSharp` ×2 | DiffuseBRDF |
| `RampSelect` | DiffuseBRDF |
| `directLighting_diffuse` | DiffuseBRDF |
| `DV_SmithJointGGX_Aniso` | SpecularBRDF |
| `F_Schlick` | SpecularBRDF |
| `GetPreIntegratedFGDGGXAndDisneyDiffuse` | IndirectLighting |
| `SmoothStep` | ShadowAdjust + ToonFresnel（各一次） |
| `DirectionalLightAttenuation` | Rim |
| `DepthRim` | Rim |
| `FresnelAttenuation` | Rim |
| `VerticalAttenuation` | Rim |
| `Rim_Color` | Rim |
| `DeSaturation` | （无标签 Frame，在 Rim 附近） |
| `ShaderOutput` | Alpha |

---

## 光照模型总结（修订版）

| 模块 | 实现方式 | Unity 迁移难度 |
|------|----------|----------------|
| Init | 几何向量点积 | 🟢 易 |
| GetSurfaceData | 贴图采样 + 标准 PBR 转换 | 🟢 易 |
| DiffuseBRDF | halfLambert + Sigmoid + Toon Ramp | 🟡 中（需导出 Ramp 贴图） |
| SpecularBRDF | 各向异性 Smith-GGX | 🟡 中（公式标准，对应 HDRP） |
| IndirectLighting | FGD LUT 预积分 | 🟡 中（可用 HDRP LUT 替换） |
| ShadowAdjust | SmoothStep | 🟢 易 |
| ToonFresnel | LayerWeight + SmoothStep | 🟢 易 |
| Rim | DepthRim（屏幕空间深度） | 🔴 难（依赖 ScreenspaceInfo） |
| Emission | 直接叠加 | 🟢 易 |
| ThinFilmFilter | LayerWeight + LUT 颜色变化 | 🟡 中（LUT 需导出） |
| Alpha | Transparent 混合 | 🟢 易 |
| Simple transmission | ScreenspaceInfo | 🔴 难（依赖扩展节点） |

---

## 待补充（Phase 1.4）

- [ ] 提取第三层子群组：`GetinvLenLV`、`GetSmithJointGGXPartLambdaV`、`DV_SmithJointGGXAniso`、`GetSmithJointGGXAnisoPartLambdaV`、`Remap01ToHalfTexelCoord`
- [ ] 确认 `ThinFilmFilter` 内嵌 TEX_IMAGE 的内容（导出图像）
- [ ] 确认 `DeSaturation` 所属具体 Frame（连线分析）
- [ ] 分析 `Simple transmission` 详细流程（SCREENSPACEINFO 输出含义）
