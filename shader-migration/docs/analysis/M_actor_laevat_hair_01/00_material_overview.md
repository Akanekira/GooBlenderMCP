# 00 — 材质概览：M_actor_laevat_hair_01

> 主节点群：`Arknights: Endfield_PBRToonBaseHair`
> 提取日期：20260301 | 溯源：`docs/raw_data/Arknights__Endfield_PBRToonBaseHair_20260301.json`
> 相关文件：`hlsl/M_actor_laevat_hair_01/PBRToonBaseHair_Input.hlsl` | `hlsl/M_actor_laevat_hair_01/PBRToonBaseHair.hlsl` | `unity/Shaders/PBRToonBaseHair.shader`

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 388 |
| 连线数 | 356 |
| 功能 Frame 数 | 10（Frame.006–Frame.015） |
| 子群组调用数 | 25（19 个唯一树） |
| 内嵌纹理 | 1（`T_actor_common_hair_01_RD.png`，内部 Ramp 贴图） |

---

## 贴图输入

| 贴图槽 | 语义 | 通道说明 |
|--------|------|----------|
| `_D`（sRGB） | Diffuse / Albedo | RGB = 发丝颜色，A = Alpha |
| `_HN`（Non-Color） | Hair Normal / 各向异性方向 | RGB = 发丝切线法线方向（编码切线偏移），A = 保留 |
| `_P`（Non-Color） | PBR 参数 | R = Metallic，G = AO / directOcclusion，B = Smoothness，A = RampUV / 保留 |
| `T_actor_common_hair_01_RD.png`（内嵌） | 阴影 Ramp 查找表 | 在 Frame.007（Diffuse BRDF）内部直接使用，不通过接口传入 |

> **注意**：与 PBRToonBase 的差异——使用 `_HN`（Hair Normal）替代 `_N`（Standard Normal）。
> `_HN` 不是传统切线空间法线，而是编码了各向异性高光方向的发丝切线纹理，
> 用于 Frame.008 的 Kajiya-Kay 风格各向异性高光计算。

---

## 群组接口输入（参数）

### 开关

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `Use Fusion face color?` | BOOLEAN | 是否启用面部颜色融合 |
| `Use Rimlimitation?` | BOOLEAN | 是否启用 Rim 方向限制 |

### 贴图数据（直接传入，非采样）

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `_D(sRGB)R.G.B` | RGBA | Diffuse 贴图 RGB 通道 |
| `_D(sRGB).A` | VALUE | Diffuse 贴图 Alpha 通道 |
| `_HN(非彩色Non_Color)R.G.B` | VECTOR | Hair Normal 贴图 RGB（切线方向） |
| `_HN(非彩色Non_Color)A` | VALUE | Hair Normal 贴图 Alpha |
| `_P(非彩色Non_Color)R.G.B` | VECTOR | PBR 贴图 RGB（Metallic/AO/Smoothness） |
| `_P(非彩色Non_Color)A` | VALUE | PBR 贴图 Alpha |
| `BaseColor` | RGBA | 基础颜色叠加 |
| `Fusion face color` | RGBA | 面部融合颜色 |

### 粗糙度 / 金属度

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `SmoothnessMax` | VALUE | 光滑度最大值（_P.B 的映射上限） |
| `MetallicMax` | VALUE | 金属度最大值（_P.R 的映射上限） |

### 阴影 / Diffuse

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `RemaphalfLambert_center` | VALUE | Half-Lambert 重映射中心 |
| `RemaphalfLambert_sharp` | VALUE | Half-Lambert 重映射锐度 |
| `CastShadow_center` | VALUE | 投影阴影中心 |
| `CastShadow_sharp` | VALUE | 投影阴影锐度 |
| `GlobalShadowBrightnessAdjustment` | VALUE | 全局阴影亮度调整 |
| `directOcclusionColor` | RGBA | 直接遮蔽区颜色 |
| `Color desaturation in shaded areas attenuation` | VALUE | 阴影区域去饱和度衰减 |

### 法线

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `NormalStrength` | VALUE | 表面法线强度 |
| `HNormalStrength` | VALUE | 发丝切线法线强度 |

### 高光 / Specular

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `SpecularColor` | RGBA | 高光颜色 |
| `dirLight_lightColor` | RGBA | 主方向光颜色 |

### Toon Fresnel

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `fresnelInsideColor` | RGBA | Fresnel 内侧颜色（正视颜色） |
| `fresnelOutsideColor` | RGBA | Fresnel 外侧颜色（掠射颜色） |
| `ToonfresnelPow` | VALUE | Toon Fresnel 指数 |
| `_ToonfresnelSMO_L` | VALUE | ToonFresnel SmoothStep 低阈值 |
| `_ToonfresnelSMO_H` | VALUE | ToonFresnel SmoothStep 高阈值 |

### Rim & Outline

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `Rim_Color` | RGBA | Rim 颜色 |
| `Rim_ColorStrength` | VALUE | Rim 颜色强度 |
| `Rim_DirLightAtten` | VALUE | Rim 对方向光的衰减权重 |
| `Rim_width_X` | VALUE | Rim 宽度（X 轴，横向） |
| `Rim_width_Y` | VALUE | Rim 宽度（Y 轴，纵向） |

### 发丝各向异性高光（Hair-Specific）

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `HighLightColorA` | RGBA | 主高光颜色 A |
| `HighLightColorB` | RGBA | 主高光颜色 B |
| `FHighLightPos` | VALUE | 高光位置偏移（沿发丝方向） |
| `Highlight length` | VALUE | 高光长度（控制高光纵向延伸） |
| `Final brightness` | VALUE | 最终亮度倍增 |
| `Hair HighLight Color Lerp SMO Min` | VALUE | 高光颜色插值 SmoothStep 最小阈值 |
| `Hair HighLight Color Lerp SMO Max` | VALUE | 高光颜色插值 SmoothStep 最大阈值 |
| `Hair HighLight Color Lerp SMO Offset` | VALUE | 高光颜色插值 SmoothStep 偏移 |

---

## 输出

| 输出名 | 类型 | 说明 |
|--------|------|------|
| `Result` | SHADER | 最终着色结果（接入材质输出） |
| `Debug` | RGBA | 调试输出（可切换显示中间量） |
| `N Normal` | VECTOR | 表面法线（世界空间，供外部使用） |
| `H Normal` | VECTOR | 发丝法线（世界空间，各向异性方向） |
| `DirectOcclusion` | RGBA | 直接遮蔽颜色结果 |
| `Albedo` | RGBA | 反照率输出 |
| `HightLightColor` | RGBA | 发丝高光颜色输出 |

---

## 与 PBRToonBase 的关键差异

| 对比项 | PBRToonBase | PBRToonBaseHair |
|--------|-------------|-----------------|
| 法线贴图 | `_N`（标准切线空间法线） | `_HN`（发丝切线方向） |
| 高光模型 | DV_SmithJointGGX_Aniso | Kajiya-Kay 风格各向异性高光（Frame.008） |
| Ramp 贴图 | 通过 `RampSelect` 子群组 | 直接采样内嵌 `T_actor_common_hair_01_RD.png` |
| Outline | 无独立 OutlineColor 子群组 | 新增 `OutlineColor` 子群组（Rim+Vertical 遮罩） |
| 双色高光 | 无 | `HighLightColorA` / `HighLightColorB` 双色插值 |
| 额外输出 | Result/Debug | +N Normal / H Normal / DirectOcclusion / Albedo / HightLightColor |

---

## 待确认

- [ ] `_HN` 的 Alpha 通道语义（未在节点连线中发现明确用途）
- [ ] `T_actor_common_hair_01_RD.png` 的具体 UV 映射方式（RampUV 来源）
- [ ] `FHighLightPos` 参数的具体偏移目标（切线方向 or 高光纹理 UV）
