# 01 — 主群组架构分析：Arknights: Endfield_PBRToonBaseHair

> 溯源：`docs/raw_data/Arknights__Endfield_PBRToonBaseHair_20260301.json`
> 提取日期：20260301 | 材质：`M_actor_laevat_hair_01`
> 相关文件：`hlsl/M_actor_laevat_hair_01/PBRToonBaseHair.hlsl` | `hlsl/M_actor_laevat_hair_01/SubGroups/SubGroups.hlsl`

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 388 |
| 连线数 | 356 |
| 功能 Frame 数 | 10 |
| 内部 Frame（子框）数 | ~55（帧.xxx 命名） |
| 唯一子群组数 | 19 |
| 子群组总调用次数 | 25 |

---

## 顶级模块（Frame）一览

| Frame | 模块名 | 节点数（非FRAME/REROUTE） | 作用 |
|-------|--------|--------------------------|------|
| Frame.013 | **Init** | 34 | 几何向量初始化（N/V/L/H/T/B/各点积），发丝特有计算 |
| Frame.014 | **GetSurfaceData** | 30 | 贴图采样 + 表面参数计算（albedo/metallic/AO/smoothness/fresnel0） |
| Frame.006 | **Specular BRDF** | 7 | GGX 高光 BRDF 主计算（DV+F+specTerm） |
| Frame.007 | **Diffuse BRDF** | 11 | Toon Diffuse：Half-Lambert Ramp + directOcclusion |
| Frame.008 | **Anisotropic HighLight** | 19 | 发丝各向异性高光（Kajiya-Kay 风格，双色插值） |
| Frame.009 | **IndirectLighting** | 9 | 间接光照（FGD 预积分 + diffuseColor + energyCompensation） |
| Frame.010 | **ShadowAjust** | 3 | 投影阴影 SmoothStep 调整 |
| Frame.011 | **ToonFresnel** | 8 | Toon Fresnel 菲涅尔效果（POWER + SmoothStep + Mix） |
| Frame.012 | **Rim & Outline** | 22 | Rim 光（方向/Fresnel/Vertical/DepthRim 衰减）+ OutlineColor 遮罩 |
| Frame.015 | **directLighting_diffuse** | 0（仅 Reroute） | 信号路由（diffuse BRDF 结果的传递节点） |

> **注意**：Frame.015 仅含 Reroute 节点，为数据路由用，不含独立计算逻辑。

---

## 整体数据流（ASCII 流程图）

```
外部传入贴图数据
  _D.RGB / _D.A           _HN.RGB / _HN.A        _P.RGB / _P.A
       │                        │                       │
       ▼                        ▼                       ▼
┌─────────────────────────────────────────────────────────────┐
│ Frame.014  GetSurfaceData                                    │
│  albedo←_D×BaseColor  metallic←_P.R×MetallicMax             │
│  AO←_P.G  smoothness←_P.B×SmoothnessMax                     │
│  perceptualRoughness←PerceptualSmoothnessToPerceptualRoughness│
│  roughness←PerceptualRoughnessToRoughness                    │
│  diffuseColor←ComputeDiffuseColor(albedo,metallic)           │
│  fresnel0←ComputeFresnel0(albedo,metallic)                   │
│  directOcclusion←_P.G                                       │
└───────────────────────────────┬─────────────────────────────┘
                                │ (surface params)
┌───────────────────────────────▼─────────────────────────────┐
│ Frame.013  Init                                              │
│  N←DecodeNormal(_HN)×NormalStrength   （表面法线）           │
│  HN←DecodeNormal(_HN)×HNormalStrength （发丝切线法线）       │
│  B←cross(N, HN)                        （发丝副法线）        │
│  V←normalize(viewDir)                                       │
│  L←normalize(lightDir)                                      │
│  NoV←clamp(dot(N,V))   NoL←clamp(dot(N,L))                  │
│  halfLambert←remapHalfLambert(NoL)                          │
│  {NdotH,LdotH,TdotH,BdotH}←Get_NoH_LoH_ToH_BoH            │
│  HNdotV←dot(HN, V)     BdotMixV←dot(B, MixV)               │
└──────────┬──────────────┬────────────────┬──────────────────┘
           │              │                │
    ┌──────▼──────┐  ┌────▼────────┐  ┌───▼──────────────────┐
    │ Frame.006   │  │ Frame.007   │  │ Frame.008            │
    │Specular BRDF│  │Diffuse BRDF │  │Anisotropic HighLight  │
    │ DV_GGX_Aniso│  │halfLambert  │  │Kajiya-Kay 双色高光    │
    │ F_Schlick   │  │RampTex(RD)  │  │SmoothStep×2+Mix      │
    │ specTerm    │  │directOcclu. │  │HighLightColorA/B      │
    └──────┬──────┘  └────┬────────┘  └───┬──────────────────┘
           │              │                │
    ┌──────▼──────────────▼────────────────▼──────────────────┐
    │ Frame.009  IndirectLighting                              │
    │  FGD←GetPreIntegratedFGDGGXAndDisneyDiffuse             │
    │  indirectDiffuse←FGD.diffuseFGD×diffuseColor×AO        │
    │  indirectSpecular←FGD.specularFGD×fresnel0              │
    │  energyCompensation←FGD.energyCompensation              │
    └──────────────────────────┬──────────────────────────────┘
                               │
    ┌──────────────────────────▼──────────────────────────────┐
    │ Frame.010  ShadowAjust                                  │
    │  shadowScene←SmoothStep(castShadow_center/sharp)        │
    │  （对 ShaderInfo 的投影阴影做 Toon 化处理）               │
    └──────────────────────────┬──────────────────────────────┘
                               │
    ┌──────────────────────────▼──────────────────────────────┐
    │ Frame.011  ToonFresnel                                  │
    │  fresnelVal←pow(1-NoV, ToonfresnelPow)                  │
    │  smoothed←SmoothStep(fresnelVal, L_H)                   │
    │  fresnelColor←lerp(fresnelInsideColor,fresnelOutside,t) │
    └──────────────────────────┬──────────────────────────────┘
                               │
    ┌──────────────────────────▼──────────────────────────────┐
    │ Frame.012  Rim & Outline                                │
    │  dirLightAtten←DirectionalLightAttenuation(...)         │
    │  fresnelAtten←FresnelAttenuation(NoV,...)               │
    │  vertAtten←VerticalAttenuation(V.y,...)                 │
    │  depthRim←DepthRim(screenPos,normal,...)                │
    │  rimColor←Rim_Color(rim_params)                         │
    │  outlineMask←OutlineColor(fresnelAtten,vertAtten) [NEW] │
    │  finalRim←dirLightAtten×rimColor + outlineMask          │
    └──────────────────────────┬──────────────────────────────┘
                               │
                          最终混合组装
                    (direct+indirect+hair+rim+toonFresnel)
                               │
                          ┌────▼────┐
                          │ Result  │
                          └─────────┘
```

---

## 各模块详解

### Frame.013 — Init（几何初始化）

**职责**：从 Geometry / Attribute 节点获取几何数据，计算所有渲染所需的向量和点积。

**标准向量（与 PBRToonBase 共用）**：
- `N`（帧.002）：DecodeNormal(_HN.RGB, NormalStrength) — 解码表面法线
- `V`（帧.003）：normalize(viewDir)
- `L`（帧.020）：normalize(lightDir)
- `NoV`（帧.004）：clamp(dot(N, V), 0.0001, 1)
- `RemaphalfLambert`（帧.014）：SigmoidSharp(halfLambert, center, sharp) — Toon 化 NdotL
- `NdotH`（帧.023）/ `LdotH`（帧.024）：由 `Get_NoH_LoH_ToH_BoH` 子群组计算
- `abs(NdotL)`（帧.025）：ABSOLUTE(dot(N, L))

**发丝特有向量（Hair-Specific）**：
- `HN`（Frame sub-frame "HN"）：DecodeNormal(_HN.RGB, HNormalStrength) — 发丝切线方向法线
- `B`（Frame sub-frame "B"）：cross(N, HN) — 发丝副法线（Bitangent）
- `HairAera`（帧.060）：发丝遮罩区域（来自 _HN.A 或属性）
- `biNoraml`（帧.056）：副法线方向（Bitangent）
- `MixV`（Frame.003）：混合后的 View 向量（Kajiya-Kay 偏移）
- `HNdotV`（Frame.004）：dot(HairNormal, V)
- `BdotMixV`（Frame.005）：dot(B, MixV)

**调用子群组**：DecodeNormal ×2、Get_NoH_LoH_ToH_BoH、SigmoidSharp（通过 RemaphalfLambert）

---

### Frame.014 — GetSurfaceData（表面参数提取）

**职责**：从传入的贴图通道数据计算标准 PBR 表面参数。

| 子框 | 来源 | 计算 |
|------|------|------|
| `albedo`（帧.001） | `_D.RGB × BaseColor` | 基础反照率 |
| `P_R`（帧.006） | `_P.RGB.x × MetallicMax` | Metallic |
| `P_G`（帧.051） | `_P.RGB.y` | AO / directOcclusion |
| `P_B`（帧.008） | `_P.RGB.z × SmoothnessMax` | Smoothness |
| `P_A`（帧.009） | `_P.A` | Alpha / RampUV |
| `perceptualRoughness`（帧.010） | PerceptualSmoothnessToPerceptualRoughness(P_B) | 感知粗糙度 |
| `roughness`（帧.011） | PerceptualRoughnessToRoughness(perceptualRoughness) | 物理粗糙度 |
| `metallic`（帧.012） | P_R | 最终金属度 |
| `fresnel0`（帧.013） | ComputeFresnel0(albedo, metallic) | F0 |
| `diffuseColor`（帧.031） | ComputeDiffuseColor(albedo, metallic) | 漫反射颜色 |
| `directOcclusion`（帧.030） | P_G | AO 遮蔽 |
| `AO`（帧.049） | P_G（或衍生） | 环境遮蔽 |

**调用子群组**：PerceptualSmoothnessToPerceptualRoughness、PerceptualRoughnessToRoughness、ComputeFresnel0、ComputeDiffuseColor

---

### Frame.006 — Specular BRDF

**职责**：GGX 各向异性高光 BRDF 主计算。

流程：
1. `DV` ← DV_SmithJointGGX_Aniso(NdotL, NdotV, NdotH, TdotH, BdotH, roughness_T, roughness_B)
2. `F` ← F_Schlick(fresnel0, LdotH)
3. `specTerm`（帧.028）← DV × F × specularColor × π × dirLight_lightColor

**调用子群组**：DV_SmithJointGGX_Aniso、F_Schlick

---

### Frame.007 — Diffuse BRDF

**职责**：Toon 风格漫反射计算，使用 Half-Lambert Ramp + 直接遮蔽。

流程：
1. 从 SHADERINFO 节点获取投影阴影（shadowScene）
2. `shadowRampColor`（帧.032）← 采样内嵌 `T_actor_common_hair_01_RD.png`（以 halfLambert/RampUV 为 U 坐标）
3. `shadowNdotL`（帧.015）← SigmoidSharp(NdotL, center, sharp)
4. `shadowArea`（帧.018）← shadowNdotL × shadowScene
5. `shadowScene`（帧.019）← 最终阴影混合
6. `directLighting_diffuse` 子群组 ← (shadowRampColor, directOcclusionColor, directOcclusion, ...)

**调用子群组**：directLighting_diffuse、SigmoidSharp ×2

---

### Frame.008 — Anisotropic HighLight（发丝各向异性高光）

**职责**：Kajiya-Kay 风格发丝高光，无 GGX，直接用 B·V 投影计算高光带。

**子框结构**：
- `帧.022 HNdotV(Fresnel)`：POWER(HNdotV, 5.0) — 计算视角相关的发丝 Fresnel 项
- `Frame.001 HighLight`：（路由 Reroute 节点）

**计算流程**：

```
BdotMixV = dot(B, MixV)          // MixV = V + FHighLightPos 方向偏移
sinT²  = 1 - BdotMixV²           // Kajiya-Kay 正弦平方
sinT   = sqrt(sinT²)             // sqrt(1 - (B·V)²)
highlight = sinT^n × |sinT|      // 高光形状 (ABSOLUTE + MULTIPLY)

// SmoothStep A 通道: 控制高光纵向延展 (Highlight length)
smA = SmoothStep(highlight, lo_A, hi_A)

// SmoothStep B 通道: 控制颜色插值边界 (SMO Min/Max + Offset)
smB = SmoothStep(highlight + offset, lo_B, hi_B)

// 双色插值
colorAB = lerp(HighLightColorA, HighLightColorB, smB)

// 组装高光结果
// HNdotV(Fresnel) = pow(HNdotV, 5.0) — 控制高光在逆光方向增强
fresnelTerm = pow(HNdotV, 5.0)
finalHighlight = smA × colorAB × fresnelTerm × Final_brightness
```

**调用子群组**：SmoothStep ×2

**输入参数**：HighLightColorA、HighLightColorB、FHighLightPos、Highlight length、Final brightness、Hair HighLight Color Lerp SMO Min/Max/Offset

---

### Frame.009 — IndirectLighting（间接光照）

**职责**：基于 FGD 预积分查找表计算间接漫反射和间接高光。

| 子框 | 计算 |
|------|------|
| `specularFGD`（帧.038） | FGD.specFGD × fresnel0 |
| `diffuseFGD`（帧.037） | FGD.diffuseFGD × diffuseColor |
| `indirectLighting.diffuse`（帧.036） | diffuseFGD × AO × indirectDiffuseLighting |
| `energyCompensation`（帧.035） | FGD.energyCompensation |

**调用子群组**：GetPreIntegratedFGDGGXAndDisneyDiffuse

---

### Frame.010 — ShadowAjust（投影阴影调整）

**职责**：对 SHADERINFO 节点输出的投影阴影值做 Toon 化（SmoothStep）处理。

```
shadowRaw ← SHADERINFO.castShadow
shadowAdj = clamp(SmoothStep(shadowRaw, CastShadow_center, CastShadow_sharp))
```

**调用子群组**：SmoothStep

---

### Frame.011 — ToonFresnel（Toon 菲涅尔）

**职责**：基于 NoV 的卡通化菲涅尔，插值内外两色。

```
fresnelRaw = pow(1.0 - NoV, ToonfresnelPow)
fresnelSmooth = SmoothStep(fresnelRaw, _ToonfresnelSMO_L, _ToonfresnelSMO_H)
fresnelColor = lerp(fresnelInsideColor, fresnelOutsideColor, fresnelSmooth)
```

**调用子群组**：SmoothStep

---

### Frame.012 — Rim & Outline（边缘光 + 描边色）

**职责**：计算边缘光（Rim）和外描边颜色遮罩（OutlineColor）。

**边缘光（Rim）部分（与 PBRToonBase 相同）**：
1. dirLightAtten ← DirectionalLightAttenuation(N, L, ...) — 方向光在 rim 上的衰减
2. fresnelAtten ← FresnelAttenuation(NoV, ...) — Fresnel 边缘衰减
3. vertAtten ← VerticalAttenuation(V.y, ...) — 垂直方向衰减
4. depthRim ← DepthRim(screenPos, ...) — 深度图 rim 检测
5. rimColor ← Rim_Color(Rim_Color, Rim_ColorStrength, ...) — 最终 Rim 颜色合成

**OutlineColor 部分（Hair 专属，新增）**：

6. `outlineMask` ← OutlineColor(fresnelAtten, vertAtten)
   - 创建仅在边缘且偏下方区域显示的描边色遮罩（详见 sub_groups/OutlineColor.md）

**最终混合**：
```
// OutlineColor 通过 VECT_TRANSFORM + SEPXYZ 计算方向修正
rimFinal = rimColor + outlineMask × rim_params
```

**调用子群组**：DirectionalLightAttenuation、FresnelAttenuation、VerticalAttenuation、DepthRim、Rim_Color、**OutlineColor**（新增）

---

## 子群组 ↔ Frame 归属总表

| 子群组 | 归属 Frame | 状态 |
|--------|-----------|------|
| DecodeNormal | Frame.013（Init） | 已有文档 |
| Get_NoH_LoH_ToH_BoH | Frame.013（Init） | 已有文档 |
| SigmoidSharp | Frame.013 / Frame.007 | 已有文档 |
| PerceptualSmoothnessToPerceptualRoughness | Frame.014 | 已有文档 |
| PerceptualRoughnessToRoughness | Frame.014 | 已有文档 |
| ComputeFresnel0 | Frame.014 | 已有文档 |
| ComputeDiffuseColor | Frame.014 | 已有文档 |
| DV_SmithJointGGX_Aniso | Frame.006 | 已有文档 |
| F_Schlick | Frame.006 | 已有文档 |
| directLighting_diffuse | Frame.007 | 已有文档 |
| SmoothStep | Frame.008 / Frame.010 / Frame.011 | 已有文档 |
| GetPreIntegratedFGDGGXAndDisneyDiffuse | Frame.009 | 已有文档 |
| DirectionalLightAttenuation | Frame.012 | 已有文档 |
| FresnelAttenuation | Frame.012 | 已有文档 |
| VerticalAttenuation | Frame.012 | 已有文档 |
| DepthRim | Frame.012 | 已有文档 |
| Rim_Color | Frame.012 | 已有文档 |
| DeSaturation | 帧.071（组合） | 已有文档 |
| **OutlineColor** | **Frame.012** | **新增文档** → `sub_groups/OutlineColor.md` |

---

## 光照模型总结

| 模块 | 实现方式 | Unity 迁移难度 |
|------|----------|----------------|
| 漫反射 | Toon Half-Lambert + 内嵌 Ramp 贴图 | 🟢 直接用 tex2D |
| 高光（标准） | DV_SmithJointGGX_Aniso + F_Schlick | 🟡 需移植 GGX 各向异性 |
| **发丝各向异性高光** | **Kajiya-Kay sinT 方法，双色 SmoothStep** | **🔴 需自行实现，无 URP 内置等价** |
| 间接光 | FGD 预积分（与 PBRToonBase 相同） | 🟡 需模拟 FGD LUT |
| ToonFresnel | pow(1-NoV, n) + SmoothStep | 🟢 直接实现 |
| Rim | DepthRim + 方向/Fresnel/Vertical 衰减 | 🟡 DepthRim 需 _CameraDepthTexture |
| **OutlineColor** | **Rim 边缘遮罩 × Vertical 遮罩（两个 ColorRamp）** | **🟢 简单 HLSL 实现** |
| 投影阴影 | SmoothStep Toon 化（SHADERINFO 节点） | 🟡 需接入 Unity 阴影贴图 |

---

## 待补充

- [ ] Frame.013 中 MixV 的具体计算方式（FHighLightPos 如何施加偏移）
- [ ] T_actor_common_hair_01_RD.png 的 UV 采样细节（是否与 _P.A 相关）
- [ ] DeSaturation 在当前材质中的具体调用位置（帧.071 外包裹层）
- [ ] GlobalShadowBrightnessAdjustment 的最终混合位置（帧.039 外包裹，顶层合成）
