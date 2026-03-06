# 00 — 材质概览：M_actor_pelica_face_01

> 主节点群：`Arknights: Endfield_PBRToonBaseFace`
> 提取日期：20260306 | 溯源：`docs/raw_data/Arknights__Endfield_PBRToonBaseFace_20260306.json`
> 相关文件：`hlsl/M_actor_pelica_face_01/PBRToonBaseFace_Input.hlsl` | `hlsl/M_actor_pelica_face_01/PBRToonBaseFace.hlsl` | `unity/Shaders/PBRToonBaseFace.shader`

---

## 材质定性

`PBRToonBaseFace` 是面部专用的 Toon PBR 着色器。相较于通用 `PBRToonBase`（437 节点、15 个 Frame 模块），本群组采用**扁平帧结构**（44 个帧标签用于标记变量，无模块级 Frame 分层），重点实现了面部特有的阴影系统：

- **SDF 阴影**：通过 SDF 贴图（`T_actor_common_female_face_01_SDF.png`）实现面部光影方向控制
- **球面法线重建**（`Recalculate normal`）：将面部法线球面化以获得平滑柔和的阴影过渡
- **下巴阴影**（chinLambertShadow）：下巴区域独立的 Lambert 阴影
- **鼻影着色**（nose shadow color）：鼻部阴影颜色叠加
- **前向透红**（`Front transparent red`）：面部皮肤次表面散射近似（正面透红效果）
- **屏幕空间 Rim / Outline**：帧.040 使用 SCREENSPACEINFO 实现
- **高光贴图叠加**：帧.041 使用 hl_M 高光遮罩贴图

核心 PBR 光照管线（DiffuseBRDF / SpecularBRDF / IndirectLighting）复用 PBRToonBase 的子群组。

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 328 |
| 连线数 | 350 |
| FRAME 节点数 | 44（含 4 个无标签帧） |
| REROUTE 节点数 | 124 |
| 逻辑节点数 | ~160 |
| 子群组调用数 | 20（15 个唯一群组） |

---

## 贴图输入

本群组引用 6 个内部纹理节点 + 群组接口传入 `_D` 贴图的 RGB 和 Alpha。

| 内部纹理槽 | 贴图名 | 语义 |
|-----------|--------|------|
| `图像纹理` | `T_actor_common_face_01_RD.png` | Ramp/Diffuse 色带（阴影颜色查找） |
| `图像纹理.001` | `T_actor_common_female_face_01_SDF.png` | SDF 面部阴影方向贴图（Non-Color） |
| `图像纹理.002` | `T_actor_common_female_face_01_cm_M.png` | 下巴遮罩（Chin Mask） |
| `图像纹理.003` | `CsutmMask`（帧.040 内） | 自定义遮罩（屏幕空间 Rim 用） |
| `图像纹理.004` | `CsutmMask` | 自定义遮罩 |
| `图像纹理.005` | `T_actor_common_face_01_hl_M.png`（帧.041 内） | 面部高光遮罩（Highlight Mask） |

---

## 群组接口输入（参数）

| 参数名 | 类型 | 默认值 | 分类 | 说明 |
|--------|------|--------|------|------|
| `_D(sRGB)R.G.B` | Color | (1,1,1,1) | 贴图 | Diffuse 贴图 RGB（外部采样后传入） |
| `_D(sRGB).A` | Float | 0.0 | 贴图 | Diffuse 贴图 Alpha |
| `BaseColor` | Color | (1,1,1,1) | 贴图 | 基础颜色（用于 fresnel0 计算） |
| `SmoothnessMax` | Float | 1.0 | 粗糙度 | 光滑度上限 |
| `MetallicMax` | Float | 1.0 | 金属度 | 金属度上限 |
| `SDF_RemaphalfLambert_center` | Float | 0.57 | 阴影 | SDF 阴影 SigmoidSharp 中心值 |
| `SDF_RemaphalfLambert_sharp` | Float | 0.16 | 阴影 | SDF 阴影 SigmoidSharp 锐度 |
| `chin_RemaphalfLambert_center` | Float | 0.0 | 阴影 | 下巴阴影 SigmoidSharp 中心值 |
| `chin_RemaphalfLambert_sharp` | Float | 0.0 | 阴影 | 下巴阴影 SigmoidSharp 锐度 |
| `CastShadow_center` | Float | 0.0 | 阴影 | 投射阴影 SigmoidSharp 中心值 |
| `CastShadow_sharp` | Float | 0.0 | 阴影 | 投射阴影 SigmoidSharp 锐度 |
| `Front R Color` | Color | (0,0,0,1) | 皮肤 | 前向透红颜色（次表面散射近似） |
| `Front R Pow` | Float | 2.0 | 皮肤 | 透红衰减指数 |
| `Front R Smo` | Float | 0.0 | 皮肤 | 透红 SmoothStep 上限 |
| `dirLight_lightColor` | Color | (1,1,1,1) | 光照 | 主方向光颜色 |
| `AmbientLightColorTint` | Color | (1,1,1,1) | 光照 | 环境光色调 |
| `SpecularColor` | Color | (3.0, 1.46, 1.34, 1) | 高光 | 高光颜色（HDR，R=3.0 偏暖红） |
| `Rim_Color` | Color | (1,1,1,1) | Rim | 边缘光颜色 |
| `nose_shadow_Color` | Color | (0,0,0,1) | 面部 | 鼻影颜色 |
| `GlobalShadowBrightnessAdjustment` | Float | 0.0 | 阴影 | 全局阴影亮度补偿 |
| `sphereNormal_Strength` | Float | 0.0 | 面部 | 球面法线混合强度 |
| `Face Final brightness` | Float | 1.15 | 面部 | 面部最终亮度倍率 |
| `Eyes white Final brightness` | Float | 1.3 | 面部 | 眼白亮度倍率 |
| `Lips highlight color` | Color | (0,0,0,1) | 面部 | 唇部高光颜色 |
| `Color desaturation in shaded areas attenuation` | Float | 1.0 | 阴影 | 阴影区域去饱和衰减 |

---

## 几何属性输入（Geometry Attribute）

| 属性名 | 类型 | 节点数 | 说明 |
|--------|------|--------|------|
| `LightDirection` | Vector | 2 | 主光源方向（世界空间，骨骼写入） |
| `headUp` | Vector | 3 | 头部上方轴（世界空间骨骼坐标） |
| `headRight` | Vector | 2 | 头部右方轴 |
| `headForward` | Vector | 3 | 头部前向轴 |
| `headCenter` | Vector | 1 | 头部中心位置（用于球面法线计算） |

---

## 输出

| 输出名 | 类型 | 说明 |
|--------|------|------|
| `Result` | Shader | 最终面部着色结果（EMISSION 输出） |
| `Debug` | Float | 调试输出（diffuseFGD） |

---

## 子群组列表

| 子群组 | 调用次数 | 状态 | 文档 |
|--------|---------|------|------|
| `SigmoidSharp` | 3 | 已有 | `sub_groups/SigmoidSharp.md` |
| `SmoothStep` | 4 | 已有 | `sub_groups/SmoothStep.md` |
| `ComputeDiffuseColor` | 1 | 已有 | `sub_groups/ComputeDiffuseColor.md` |
| `ComputeFresnel0` | 1 | 已有 | `sub_groups/ComputeFresnel0.md` |
| `PerceptualSmoothnessToPerceptualRoughness` | 1 | 已有 | `sub_groups/PerceptualSmoothnessToPerceptualRoughness.md` |
| `PerceptualRoughnessToRoughness` | 1 | 已有 | `sub_groups/PerceptualRoughnessToRoughness.md` |
| `Get_NoH_LoH_ToH_BoH` | 1 | 已有 | `sub_groups/Get_NoH_LoH_ToH_BoH.md` |
| `DV_SmithJointGGX_Aniso` | 1 | 已有 | `sub_groups/DV_SmithJointGGX_Aniso.md` |
| `F_Schlick` | 1 | 已有 | `sub_groups/F_Schlick.md` |
| `GetPreIntegratedFGDGGXAndDisneyDiffuse` | 1 | 已有 | `sub_groups/GetPreIntegratedFGDGGXAndDisneyDiffuse.md` |
| `directLighting_diffuse` | 1 | 已有 | `sub_groups/directLighting_diffuse.md` |
| `DeSaturation` | 1 | 已有 | `sub_groups/DeSaturation.md` |
| `calculateAngel` | 1 | 已有 | `sub_groups/calculateAngel.md` |
| **`Recalculate normal`** | 1 | **新增** | `sub_groups/Recalculate_normal.md` |
| **`Front transparent red`** | 1 | **新增** | `sub_groups/Front_transparent_red.md` |

---

## 与 PBRToonBase 的差异

| 特性 | PBRToonBase | PBRToonBaseFace |
|------|------------|-----------------|
| 节点数 | 437 | 328 |
| Frame 结构 | 15 个模块级 Frame.xxx | 44 个变量级帧标签（扁平） |
| 法线处理 | DecodeNormal（法线贴图） | Recalculate normal（球面法线） |
| 阴影系统 | halfLambert + CastShadow | SDF 阴影 + 下巴阴影 + 鼻影 |
| 各向异性 | TdotH/BdotH 独立 Frame | 无各向异性（使用 isotropic DV） |
| Fresnel/Rim | ToonFresnel + DepthRim | 屏幕空间 Rim（帧.040） |
| 薄膜效果 | ThinFilmFilter (Frame.011) | 无 |
| Emission | Frame.010 叠加 | 无独立 Emission |
| 面部特有 | — | SDF 阴影、球面法线、透红、鼻影、下巴阴影、高光遮罩、去饱和 |
