# 01 — 主群组架构分析：Arknights: Endfield_PBRToonBaseFace

> 溯源：`docs/raw_data/Arknights__Endfield_PBRToonBaseFace_20260306.json`
> 提取日期：2026-03-06
> 相关文件：`hlsl/M_actor_pelica_face_01/PBRToonBaseFace.hlsl` | `hlsl/M_actor_pelica_face_01/SubGroups/SubGroups.hlsl`

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 328 |
| 连线数 | 350 |
| FRAME 节点数 | 44（含 4 个无标签帧） |
| 子群组调用数 | 20（15 个唯一群组） |
| 实际逻辑节点 | ~160 |
| REROUTE 节点数 | 124 |

---

## 架构特点：扁平帧 vs 模块帧

与 PBRToonBase（15 个模块级 `Frame.xxx`）不同，PBRToonBaseFace 的 44 个帧均为**变量级标签**，每个帧标注一个变量或计算步骤，无 Frame 内嵌套子框结构。

本文档按语义将这些帧归纳为 **9 个逻辑模块**，以便与 Cloth 版本对照理解。

---

## 逻辑模块一览

| # | 逻辑模块 | 对应帧标签 | 核心子群组 | 职责 |
|---|---------|-----------|-----------|------|
| 1 | **GeometryVectors** | N, V, L, NoV, ClampNdotV, LoV, NoL_Unsaturate, clampedNdotL, abs(NdotL), NdotH, LdotH | `Recalculate normal`, `Get_NoH_LoH_ToH_BoH` | 几何向量 + 点积 |
| 2 | **SurfaceData** | albedo, metallic, perceptualRoughness, roughness, fresnel0, diffuseColor, directOcclusion | `ComputeDiffuseColor`, `ComputeFresnel0`, `PerceptualSmoothness→Roughness` | 贴图采样 + 表面参数 |
| 3 | **SDFShadow** | AngelUV, AngleThreshold, SDFShadow, shadowArea, chinLambertShaodow, shadowScene, Remove Shadows | `calculateAngel`, `SigmoidSharp` ×3 | SDF 面部阴影系统 |
| 4 | **DiffuseBRDF** | shadowRampColor, directLighting_diffuse, dirLight_lightColor, nose shadow color | `directLighting_diffuse`, `SmoothStep` ×1 | Toon 漫反射 + 鼻影 |
| 5 | **SpecularBRDF** | DV, F, specTerm, directLighting_specular | `DV_SmithJointGGX_Aniso`, `F_Schlick` | 各向同性 GGX 高光 |
| 6 | **IndirectLighting** | specularFGD, diffuseFGD, energyCompensation, indirectLighting.diffuse, GlobalShadowBrightnessAdjustment | `GetPreIntegratedFGDGGXAndDisneyDiffuse`, `SmoothStep` ×1 | 间接光照 + 能量补偿 |
| 7 | **FaceEffects** | 帧.040（屏幕空间 Rim）, 帧.041（高光贴图叠加）, Front transparent red, DeSaturation | `Front transparent red`, `SmoothStep` ×2, `DeSaturation` | 面部特效 |
| 8 | **FinalComposite** | （无独立帧标签，根级混合节点） | — | 最终颜色合成 |
| 9 | **Alpha** | 帧.001（含 Front transparent red 调用） | — | Alpha 输出 |

---

## 📊 整体数据流

```
贴图输入(_D / _P / _E) + 骨骼属性(headCenter/Up/Right/Forward/LightDirection)
        │
        ▼
┌─────────────────────────────────────────┐
│  Module 1: GeometryVectors              │
│  Recalculate normal (球面法线)           │
│  Get_NoH_LoH_ToH_BoH (半角点积)         │
│  → N, V, L, NoV, NoL, LoV, NdotH...    │
└──────────────┬──────────────────────────┘
               ▼
┌─────────────────────────────────────────┐
│  Module 2: SurfaceData                  │
│  贴图拆通道 → metallic, roughness       │
│  ComputeDiffuseColor, ComputeFresnel0   │
│  → albedo, diffuseColor, fresnel0, AO   │
└──────┬─────────────────┬────────────────┘
       │                 │
       ▼                 ▼
┌──────────────┐  ┌──────────────────────┐
│ Module 3:    │  │ Module 5:            │
│ SDFShadow    │  │ SpecularBRDF         │
│              │  │                      │
│calculateAngel│  │ DV_SmithJointGGX     │
│→ SDF 采样    │  │ _Aniso (isotropic)   │
│→ SigmoidSharp│  │ F_Schlick            │
│→ 下巴阴影    │  │                      │
│→ shadowArea  │  └──────┬───────────────┘
└──────┬───────┘         │
       │          ┌──────▼───────────────┐
       ▼          │ Module 6:            │
┌──────────────┐  │ IndirectLighting     │
│ Module 4:    │  │ GetPreIntegratedFGD  │
│ DiffuseBRDF  │  │ energyCompensation   │
│ RampSelect   │  └──────┬───────────────┘
│ directLight  │         │
│ _diffuse     │         │
│ + nose shadow│         │
└──────┬───────┘         │
       └────────┬─────────┘
                ▼
       ┌────────────────────┐
       │ Module 7:          │
       │ FaceEffects        │
       │ Front transparent  │
       │   red (SSS)        │
       │ 屏幕空间 Rim (帧.040)│
       │ 高光贴图叠加 (帧.041)│
       │ DeSaturation       │
       └────────┬───────────┘
                ▼
       ┌────────────────────┐
       │ Module 8:          │
       │ FinalComposite     │
       │ Face Final         │
       │   brightness       │
       │ Eyes white Final   │
       │   brightness       │
       └────────┬───────────┘
                ▼
       GROUP_OUTPUT → Result / Debug
```

---

## 各模块详解

---

### Module 1 — GeometryVectors（几何向量初始化）

**职责**：从几何节点和骨骼属性获取所有向量并计算点积。**核心差异**：使用 `Recalculate normal` 替代 Cloth 版的 `DecodeNormal`。

> 📥 **输入**：`posWS`(GEOMETRY) · `headCenter`(骨骼属性) · `headUp/headRight/headForward`(骨骼属性) · `LightDirection`(骨骼属性) · `SHADERINFO`(光照)
> 📤 **输出**：N / V / L / NoV / ClampNdotV / NoL_Unsaturate / clampedNdotL / abs(NdotL) / LoV / NdotH / LdotH → Module 2~8
> 🔗 **子群组**：[`Recalculate normal`](../sub_groups/Recalculate_normal.md)、[`Get_NoH_LoH_ToH_BoH`](../sub_groups/Get_NoH_LoH_ToH_BoH.md)

| 帧标签 | 变量 | 计算 |
|--------|------|------|
| `帧.002` N | 法线 | `Recalculate normal`(sphereNormal_Strength, headCenter, posWS, NormalWS, ChinMask) |
| `帧.003` V | 视角方向 | `NEW_GEOMETRY.Incoming`（取反归一化） |
| `帧.020` L | 光方向 | `SHADERINFO` 或 `LightDirection` 属性 |
| `帧.004` NoV | dot(N,V) | VECT_MATH.DOT |
| `帧.005` ClampNdotV | saturate(NoV) | CLAMP |
| `帧.` NoL_Unsaturate | dot(N,L) | VECT_MATH.DOT |
| `帧.029` clampedNdotL | saturate(NoL) | CLAMP |
| `帧.` abs(NdotL) | abs(NoL) | MATH.ABSOLUTE |
| `帧.021` LoV | dot(L,V) | VECT_MATH.DOT |
| `帧.` NdotH / LdotH | 半角点积 | `Get_NoH_LoH_ToH_BoH` |

**与 Cloth 版差异**：
- 无 DecodeNormal（无法线贴图）→ 使用 Recalculate normal（球面法线）
- 无 T / B 向量（无各向异性）→ 无 TdotH / BdotH / TdotL 等
- 新增骨骼属性输入（headCenter/Up/Right/Forward/LightDirection）

---

### Module 2 — SurfaceData（表面数据）

**职责**：拆解贴图通道，计算物理表面参数。与 Cloth 版结构基本相同。

> 📥 **输入**：`_D.RGB`(Group Input) · `_P.RGBA`(内部采样，但 Face 中由 Group Input 传入) · `MetallicMax / SmoothnessMax`(Group Input) · `BaseColor`(Group Input)
> 📤 **输出**：albedo / metallic / perceptualRoughness / roughness / diffuseColor / fresnel0 / AO → Module 3~7
> 🔗 **子群组**：[`ComputeDiffuseColor`](../sub_groups/ComputeDiffuseColor.md)、[`ComputeFresnel0`](../sub_groups/ComputeFresnel0.md)、[`PerceptualSmoothnessToPerceptualRoughness`](../sub_groups/PerceptualSmoothnessToPerceptualRoughness.md)、[`PerceptualRoughnessToRoughness`](../sub_groups/PerceptualRoughnessToRoughness.md)

| 帧标签 | 变量 | 计算 |
|--------|------|------|
| `帧.` albedo | 漫反射色 | `_D.RGB`（sRGB） |
| `帧.` metallic | 金属度 | `_P.R × MetallicMax` |
| `帧.030` directOcclusion | AO | `_P.G` |
| `帧.010` perceptualRoughness | 感知粗糙度 | `PerceptualSmoothnessToPerceptualRoughness(_P.B × SmoothnessMax)` |
| `帧.` roughness | 物理粗糙度 | `PerceptualRoughnessToRoughness(perceptualRoughness)` |
| `帧.031` diffuseColor | 漫反射色 | `ComputeDiffuseColor(albedo, metallic)` |
| `帧.013` fresnel0 | F0 | `ComputeFresnel0(BaseColor, metallic, 0.04)` |

**与 Cloth 版差异**：
- 无各向异性粗糙度（roughnessT / roughnessB）
- 无 RampUV（P_A）通道 → 面部 Ramp 由 SDF 阴影系统驱动
- 无 Emission 贴图采样（面部无 _E）

---

### Module 3 — SDFShadow（SDF 面部阴影系统）

**职责**：面部阴影的核心模块，完全替代 Cloth 版的 halfLambert 阴影。使用 SDF 贴图实现面部方向感知的阴影控制。

> 📥 **输入**：`LightDirection / headUp / headRight / headForward`(骨骼属性) · `SDF 贴图` · `ChinMask 贴图` · `NoL_Unsaturate` · `castShadow`(SHADERINFO) · `SDF_RemaphalfLambert_center/sharp / chin_center/sharp / CastShadow_center/sharp`(Group Input)
> 📤 **输出**：`shadowArea` → Module 4 DiffuseBRDF
> 🔗 **子群组**：[`calculateAngel`](../sub_groups/calculateAngel.md)、[`SigmoidSharp`](../sub_groups/SigmoidSharp.md) ×3

#### 子模块分解

**帧.AngelUV / 帧.AngleThreshold — calculateAngel 调用**

```
LightDirection + headUp + headRight + headForward
    → calculateAngel
    → AngleThreshold（光源相对头部水平方位角 [0,1]）
    → Flip threshold（左右翻转参考）
```

**帧.SDFShadow — SDF 贴图采样**

```
AngleThreshold
    → 构造 SDF 采样 UV（U = AngleThreshold, V = 固定行）
    → 图像纹理.001（SDF 贴图）→ SDF 值
    → SigmoidSharp(SDF值, SDF_RemaphalfLambert_center, SDF_RemaphalfLambert_sharp)
    → SDFShadow 遮罩
```

**帧.chinLambertShaodow — 下巴 Lambert 阴影**

```
NoL_Unsaturate
    → SigmoidSharp(NoL, chin_center, chin_sharp)
    → chinLambertShadow
    → 通过 ChinMask 与 SDFShadow 混合（ChinMask=1 区域使用下巴阴影）
```

**帧.shadowScene — 投影阴影**

```
castShadow (SHADERINFO)
    → SigmoidSharp(castShadow, CastShadow_center, CastShadow_sharp)
    → shadowScene
```

**帧.shadowArea — 阴影合并**

```
min(SDFShadow_with_chin, shadowScene) → shadowArea
```

**帧.Remove Shadows — 去阴影开关**

```
shadowArea → 可选覆盖（调试用）
```

---

### Module 4 — DiffuseBRDF（漫反射）

**职责**：基于 shadowArea 进行 Toon Ramp 采样和漫反射计算。

> 📥 **输入**：`shadowArea`(Module 3) · `diffuseColor`(Module 2) · `AO`(Module 2) · `dirLight_lightColor`(Group Input) · `Ramp 贴图`
> 📤 **输出**：`directLighting_diffuse` → Module 8 FinalComposite
> 🔗 **子群组**：[`directLighting_diffuse`](../sub_groups/directLighting_diffuse.md)、[`SmoothStep`](../sub_groups/SmoothStep.md)

| 帧标签 | 变量 | 计算 |
|--------|------|------|
| `帧.032` shadowRampColor | Ramp 颜色 | Ramp 贴图采样（U = shadowArea, V = 固定行） |
| `帧.033` directLighting_diffuse | 漫反射输出 | `rampColor × diffuseColor × lightColor × AO` |
| `帧.` dirLight_lightColor | 光照颜色 | Group Input |
| `帧.` nose shadow color | 鼻影颜色 | `nose_shadow_Color`(Group Input) × 鼻部遮罩 叠加 |

**与 Cloth 版差异**：
- 无 RampSelect（Face 只有单一 Ramp 贴图，非 5 行 LUT）
- shadowArea 来自 SDF 系统而非 halfLambert
- 新增鼻影颜色叠加

---

### Module 5 — SpecularBRDF（高光）

**职责**：各向同性 GGX 高光计算。与 Cloth 版的各向异性双路结构不同，Face 仅使用各向同性分支。

> 📥 **输入**：`NdotH / abs(NdotL) / NoV / LdotH`(Module 1) · `roughness / fresnel0`(Module 2) · `SpecularColor`(Group Input)
> 📤 **输出**：`directLighting_specular` → Module 6/8
> 🔗 **子群组**：[`DV_SmithJointGGX_Aniso`](../sub_groups/DV_SmithJointGGX_Aniso.md)（仅各向同性输出）、[`F_Schlick`](../sub_groups/F_Schlick.md)

| 帧标签 | 变量 | 计算 |
|--------|------|------|
| `帧.026` DV | D×V 项 | `DV_SmithJointGGX_Aniso`（仅使用 dvIsotropic） |
| `帧.027` F | Fresnel 项 | `F_Schlick(fresnel0, 1.0, LdotH)` |
| `帧.028` specTerm | 高光项 | `F × DV` |
| `帧.034` directLighting_specular | 高光输出 | `specTerm × SpecularColor × lightColor` |

**与 Cloth 版差异**：
- 无各向异性分支（无 TdotH / BdotH / roughnessT / roughnessB）
- 无 Toon Aniso 混合开关
- 使用 `SpecularColor` 参数（HDR，R=3.0 偏暖红）调制高光颜色

---

### Module 6 — IndirectLighting（间接光照）

**职责**：预积分 FGD 查找 + 能量补偿 + 环境光叠加。与 Cloth 版流程基本一致。

> 📥 **输入**：`ClampNdotV`(Module 1) · `perceptualRoughness / fresnel0 / diffuseColor`(Module 2) · `AmbientLighting`(SHADERINFO) · `AmbientLightColorTint / specularFGD_Strength`(Group Input)
> 📤 **输出**：`indirectDiffuse` + `indirectSpecComp` → Module 8 FinalComposite
> 🔗 **子群组**：[`GetPreIntegratedFGDGGXAndDisneyDiffuse`](../sub_groups/GetPreIntegratedFGDGGXAndDisneyDiffuse.md)、[`SmoothStep`](../sub_groups/SmoothStep.md)

| 帧标签 | 变量 | 计算 |
|--------|------|------|
| `帧.038` specularFGD | FGD 高光项 | LUT 查询输出 |
| `帧.037` diffuseFGD | FGD 漫反射项 | LUT 查询输出 |
| `帧.035` energyCompensation | EC 因子 | `1.0 / reflectivity - 1.0` |
| `帧.036` indirectLighting.diffuse | 间接漫反射 | `diffuseColor × diffuseFGD × ambientCombined` |
| `帧.` GlobalShadowBrightnessAdjustment | 阴影亮度 | `SmoothStep` 调制 |

---

### Module 7 — FaceEffects（面部特效）

**职责**：面部特有的视觉效果集合，全部为 Face shader 新增。

> 📥 **输入**：合成前颜色 · N · V · `_D.R` · `Front R Color/Pow/Smo`(Group Input) · 屏幕空间信息 · 高光遮罩贴图
> 📤 **输出**：特效叠加后颜色 → Module 8
> 🔗 **子群组**：[`Front transparent red`](../sub_groups/Front_transparent_red.md)、[`SmoothStep`](../sub_groups/SmoothStep.md) ×2、[`DeSaturation`](../sub_groups/DeSaturation.md)

#### 帧.040 — 屏幕空间 Rim / Outline

使用 `SCREENSPACEINFO`（Goo Engine 专有）实现面部边缘检测。包含 ~10 个 MATH 节点 + 1 个 SEPXYZ + 1 个 TEX_IMAGE（自定义遮罩）+ 1 个 VALTORGB（颜色渐变）。

与 Cloth 版的 `DepthRim + 4 因子衰减` 完全不同，此处直接使用屏幕空间信息节点。

#### 帧.041 — 高光贴图叠加

使用 `T_actor_common_face_01_hl_M.png`（高光遮罩贴图）叠加面部高光细节。

#### Front transparent red（帧.001 内）

调用 `Front transparent red` 子群组实现正面透红 SSS 近似。

#### DeSaturation

通过 `Color desaturation in shaded areas attenuation` 参数对阴影区域进行去饱和处理。

---

### Module 8 — FinalComposite（最终合成）

**职责**：汇合所有光照分支和特效，输出最终颜色。

> 📥 **输入**：directDiffuse + directSpecular + indirectDiffuse + indirectSpecComp + FaceEffects 各项
> 📤 **输出**：最终颜色 → GROUP_OUTPUT

```
directLighting  = (directSpecular × energyCompFactor) + directDiffuse
totalSpecular   = directLighting + indirectSpecComp
totalLighting   = totalSpecular + indirectDiffuse
    → + FaceEffects（透红 / Rim / 高光贴图）
    → × Face Final brightness
    → GROUP_OUTPUT(Result)
```

**特有参数**：
- `Face Final brightness`（默认 1.15）：面部整体亮度倍率
- `Eyes white Final brightness`（默认 1.3）：眼白区域独立亮度

---

### Module 9 — Alpha

**职责**：Alpha 输出。

> 📥 **输入**：`_D.A`(Group Input)
> 📤 **输出**：Alpha → GROUP_OUTPUT

与 Cloth 版不同，Face 不使用 `ShaderOutput` 子群组，直接通过 MIX_SHADER(Transparent, Emission) 输出。

---

## 子群组 ↔ 逻辑模块归属总表

| 子群组 | 调用次数 | 归属模块 | 状态 |
|--------|---------|---------|------|
| [`Recalculate normal`](../sub_groups/Recalculate_normal.md) | 1 | GeometryVectors | **新增** |
| [`Get_NoH_LoH_ToH_BoH`](../sub_groups/Get_NoH_LoH_ToH_BoH.md) | 1 | GeometryVectors | 已有 |
| [`ComputeDiffuseColor`](../sub_groups/ComputeDiffuseColor.md) | 1 | SurfaceData | 已有 |
| [`ComputeFresnel0`](../sub_groups/ComputeFresnel0.md) | 1 | SurfaceData | 已有 |
| [`PerceptualSmoothnessToPerceptualRoughness`](../sub_groups/PerceptualSmoothnessToPerceptualRoughness.md) | 1 | SurfaceData | 已有 |
| [`PerceptualRoughnessToRoughness`](../sub_groups/PerceptualRoughnessToRoughness.md) | 1 | SurfaceData | 已有 |
| [`calculateAngel`](../sub_groups/calculateAngel.md) | 1 | SDFShadow | 已有 |
| [`SigmoidSharp`](../sub_groups/SigmoidSharp.md) | 3 | SDFShadow | 已有 |
| [`directLighting_diffuse`](../sub_groups/directLighting_diffuse.md) | 1 | DiffuseBRDF | 已有 |
| [`DV_SmithJointGGX_Aniso`](../sub_groups/DV_SmithJointGGX_Aniso.md) | 1 | SpecularBRDF | 已有 |
| [`F_Schlick`](../sub_groups/F_Schlick.md) | 1 | SpecularBRDF | 已有 |
| [`GetPreIntegratedFGDGGXAndDisneyDiffuse`](../sub_groups/GetPreIntegratedFGDGGXAndDisneyDiffuse.md) | 1 | IndirectLighting | 已有 |
| [`SmoothStep`](../sub_groups/SmoothStep.md) | 4 | DiffuseBRDF / IndirectLighting / FaceEffects | 已有 |
| [`Front transparent red`](../sub_groups/Front_transparent_red.md) | 1 | FaceEffects | **新增** |
| [`DeSaturation`](../sub_groups/DeSaturation.md) | 1 | FaceEffects | 已有 |

---

## 光照模型总结

| 模块 | 实现方式 | Unity 迁移难度 |
|------|----------|----------------|
| GeometryVectors | 球面法线重映射 + 点积 | 🟡 中（需骨骼数据传入 shader） |
| SurfaceData | 贴图采样 + 标准 PBR 转换 | 🟢 易 |
| SDFShadow | SDF 贴图 + calculateAngel + SigmoidSharp | 🟡 中（需骨骼属性 + SDF 贴图导出） |
| DiffuseBRDF | Ramp 采样 + 鼻影叠加 | 🟢 易 |
| SpecularBRDF | 各向同性 Smith-GGX | 🟢 易（无各向异性复杂度） |
| IndirectLighting | FGD LUT + 能量补偿 | 🟡 中（HDRP LUT 替换） |
| FaceEffects — 透红 | SSS 近似 | 🟢 易（纯数学） |
| FaceEffects — Rim | SCREENSPACEINFO | 🔴 难（Goo Engine 专有节点） |
| FaceEffects — 高光贴图 | 遮罩叠加 | 🟢 易 |
| FaceEffects — 去饱和 | DeSaturation | 🟢 易 |
| FinalComposite | 亮度倍率合成 | 🟢 易 |

---

## ❓ 待确认

- [ ] 帧.040 屏幕空间 Rim 的详细计算流程（SCREENSPACEINFO 输出含义、颜色渐变节点配置）
- [ ] `Front transparent red` 的 `Positive attenuation` 上游连线（推测为 `saturate(dot(N, V))` 或类似正面因子）
- [ ] `nose shadow color` 的遮罩来源：是否通过 `_P` 贴图某通道或独立遮罩控制
- [ ] 眼白区域 `Eyes white Final brightness` 的遮罩驱动方式（顶点色？贴图通道？）
- [ ] 帧.001 的完整结构（包含 Front transparent red 调用，但帧标签为空）
