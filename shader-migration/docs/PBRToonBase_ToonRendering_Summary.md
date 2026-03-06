# PBRToonBase 卡通渲染方案总结

> 来源：Arknights: Endfield / Goo Engine 4.4（基于 Blender 4.4）
> 基准材质：M_actor_pelica_cloth_04
> 主节点群：Arknights: Endfield_PBRToonBase（437 节点 / 15 个 Frame 模块 / 20 个子群组）
> 相关代码：`hlsl/PBRToonBase.hlsl` | `hlsl/SubGroups/SubGroups.hlsl`

---

## 1. 方案概述

PBRToonBase 是一套面向角色材质的 **PBR + Toon 混合渲染方案**。它以物理正确的微表面模型（GGX、能量守恒）为基础，通过 SigmoidSharp 阶跃函数和 Ramp 色带采样将光照响应风格化为卡通阴影，同时叠加 Toon Fresnel 边缘色、屏幕空间 Rim 边缘光、视角色变等风格化效果层。

整个 Shader 通过 15 个 Frame 模块按序组装，51 个可调参数（含 7 个功能开关）提供高度灵活的美术控制。

---

## 2. 渲染管线总览

```
贴图输入 (_D / _N / _P / _E)
    |
    v
+--------------------------------------------------+
| Frame.012  Init        几何向量 N/V/L/T/B + 点积  |
| Frame.013  SurfaceData 贴图拆通道 + PBR 参数计算   |
+--------------------------------------------------+
    |
    v
+--------------------------------------------------+
| Frame.069  SimpleTransmission  伪透射修改 albedo   |  (前置，影响后续漫反射)
+--------------------------------------------------+
    |
    +-------------------+-------------------+
    |                                       |
    v                                       v
+-----------------------------+  +-----------------------------+
| Frame.005  DiffuseBRDF      |  | Frame.004  SpecularBRDF     |
| Toon 漫反射                 |  | GGX 高光                    |
| SigmoidSharp + Ramp 色带    |  | 镜面反射 / 各向异性可选      |
+-----------------------------+  +-----------------------------+
    |                                       |
    v                                       |
+-----------------------------+             |
| Frame.007  ShadowAdjust     |             |
| 全局阴影亮度调节              |             |
+-----------------------------+             |
    |                                       |
    +-------------------+-------------------+
                        |
                        v
+--------------------------------------------------+
| Frame.006  IndirectLighting                       |
| FGD LUT 预积分 + Kulla-Conty 能量守恒补偿         |
| 汇合：直接光(漫反射+高光) + 间接光(漫反射+高光)     |
+--------------------------------------------------+
    |
    v  ADD 叠加风格化效果
+--------------------------------------------------+
| Frame.008  ToonFresnel     Toon 边缘色            |
| Frame.009  Rim             屏幕空间深度边缘光       |
| Frame.010  Emission        自发光                  |
| Frame.011  ThinFilmFilter  视角色变(RS 彩虹)       |
+--------------------------------------------------+
    |
    v
+--------------------------------------------------+
| Frame.014  Alpha 输出                              |
+--------------------------------------------------+
```

---

## 3. 光照模型

光照计算遵循标准路径：**直接漫反射 + 直接高光反射 + 间接光照**。

### 3.1 直接漫反射

**对应模块**：Frame.005 DiffuseBRDF + Frame.007 ShadowAdjust

卡通漫反射的核心是将连续的光照响应转化为**离散的阴影色带**，实现手绘感阴影。

#### SigmoidSharp 阶跃函数

```hlsl
float SigmoidSharp(float x, float center, float sharp)
{
    float t = -3.0 * sharp * (x - center);
    return 1.0 / (1.0 + pow(100000.0, t));
}
```

- 底数为 100000（而非自然指数 e），产生极其陡峭的 S 型曲线
- **`center`** 控制阴影分界线位置（NdotL 多大时开始过渡）
- **`sharp`** 控制边缘锐度（值越大，阴影边界越硬，越接近二值 Toon）
- 与 `smoothstep` 不同，SigmoidSharp 的过渡区域可以收窄到几乎为零，实现纯卡通硬阴影

#### 双路阴影合并

方案对**自阴影**和**投影阴影**采用独立的 SigmoidSharp 处理，各自有独立的 center/sharp 参数：

```
自阴影路径：  NoL           → SigmoidSharp(center_HL, sharp_HL)    → shadowNdotL
投影阴影路径：castShadow    → SigmoidSharp(center_CS, sharp_CS)    → shadowScene

合并：shadowCombined = min(shadowNdotL, shadowScene)    // 取暗
```

- **取暗合并**意味着投影阴影可以完全覆盖自阴影区域，但不会抬亮任何一侧
- 两路独立参数允许美术分别调节：自阴影可以更软（如半调渐变），投影阴影保持硬边

#### Ramp 色带采样

阴影值作为 U 坐标，查询一维 Ramp LUT，输出风格化阴影颜色：

```
shadowCombined → Ramp UV (X=阴影值, Y=0.5) → RampSelect(RampIndex) → rampColor
```

- Ramp LUT 支持多行（5 条），通过 **`_P.A`** 通道的 RampIndex 选择不同色带
- 不同材质区域可以使用不同的 Ramp 行，实现一个 Shader 内多种阴影风格
- rampAlpha 输出传递到 ShadowAdjust，驱动全局阴影亮度的 SmoothStep 调节

#### 最终漫反射公式

```
directDiffuse = rampColor * diffuseColor * lightColor * directOcclusion
```

其中 **`directOcclusion`** 由 AO 贴图和 `_directOcclusionColor` 混合得到，控制遮蔽区域的色调。

---

### 3.2 直接高光反射

**对应模块**：Frame.004 SpecularBRDF

高光计算基于 Cook-Torrance 微表面模型 **F * D * V**（Fresnel * Distribution * Visibility），提供两种可选模式。

#### Fresnel 项（共用）

```hlsl
float3 F = F_Schlick(fresnel0, float3(1,1,1), LdotH);
```

两种高光模式共用同一 Schlick Fresnel，`fresnel0 = lerp(0.04, albedo, metallic)` 根据金属度在电介质基底反射率和金属色之间插值。

#### 镜面反射（等向 GGX）

标准 Smith-Joint GGX，单一 roughness 参数控制：

```
D_iso = a^2 / (PI * ((NdotH^2 * a^2 + (1-a^2))^2))
V_iso = 0.5 / (NdotL * sqrt(...) + NdotV * sqrt(...))
dvIsotropic = D_iso * V_iso
```

适用于大多数非布料材质（金属、皮革等），各方向高光形状一致。

#### 各向异性反射（Anisotropic GGX）

T/B 轴粗糙度分离，适用于布料、拉丝金属等具有方向性纹理的材质：

```
D_aniso = 1 / (PI * roughnessT * roughnessB * f^2)
  其中 f = (TdotH/roughT)^2 + (BdotH/roughB)^2 + NdotH^2

V_aniso = 0.5 / (NdotL * length(roughT*TdotV, roughB*BdotV, NdotV) + ...)
dvAnisotropic = D_aniso * V_aniso
```

- **roughnessT / roughnessB** 分别由 `_Aniso_SmoothnessMaxT` / `_Aniso_SmoothnessMaxB` 控制
- 布料材质中 T/B 轴粗糙度通常有显著差异，产生**沿纹理方向拉长的高光**

#### 模式选择

```hlsl
// 三级控制
float3 toonAnisoResult = (_UseToonAniso > 0.5) ? specTermAniso : specTerm;

if (_UseAnisotropy > 0.5)
    finalSpecTerm = lerp(specTerm, toonAnisoResult, _AnisotropicMask);
else
    finalSpecTerm = specTerm;
```

- **`_UseAnisotropy`**：总开关，关闭时直接使用等向 GGX
- **`_UseToonAniso`**：各向异性分支内的子选项
- **`_AnisotropicMask`**：遮罩加权，允许材质不同区域使用不同高光模式

---

### 3.3 间接光照

**对应模块**：Frame.006 IndirectLighting

间接光照模块完成三件事：
1. 对直接高光应用**能量守恒补偿**
2. 计算间接漫反射和间接高光
3. 将直接光和间接光汇合为最终 totalLighting

#### FGD LUT 预积分查询

```hlsl
GetPreIntegratedFGD(NdotV, perceptualRoughness, fresnel0,
                    specularFGD, diffuseFGD, reflectivity);
```

- 输入 **(NdotV, perceptualRoughness)** 查询 2D LUT
- 输出 **specularFGD**（预积分 Fresnel-GGX）、**diffuseFGD**（Disney 漫反射积分项）、**reflectivity**（总反射率 r）
- LUT 布局：R = B_term, G = A+B(reflectivity), B = Disney Diffuse FGD

#### Kulla-Conty 能量守恒补偿

标准微表面 BRDF 只考虑单次散射，粗糙表面上微面元间的**多重散射能量损失**可达 30%+。Kulla-Conty 近似通过反射率 r 估算损失量并补回：

```
ecFactor = 1/reflectivity - 1
```

- `r -> 1.0`（光滑镜面）时 `ecFactor -> 0`，无需补偿
- `r ~ 0.5`（中等粗糙）时 `ecFactor ~ 1.0`，补偿最强

补偿分两条路径：

```
路径 A — 修正直接高光：
  energyCompFactor = F0 * ecFactor + 1.0
  correctedSpecular = directSpecular * energyCompFactor

路径 B — 补充间接高光：
  indirectSpecComp = ecFactor * specularFGD * _specularFGDStrength
```

路径 A 放大直接高光中因多重散射丢失的部分；路径 B 以间接高光形式补充分布在半球各方向的散射能量。两条路径互补，确保总能量守恒。

#### 间接漫反射

```
indirectDiffuse = diffuseColor * diffuseFGD * ambientCombined
```

- **`ambientCombined`** = `_AmbientLightColorTint` * `_AmbientLighting`（Goo Engine 的 Ambient Lighting；Unity 侧替换为 SH 探针或 `unity_AmbientSky`）

#### 汇合

```
totalLighting = correctedSpecular + directDiffuse + indirectSpecComp + indirectDiffuse
```

---

## 4. 风格化处理

在 PBR 光照计算基础上，对结果进行风格化处理。这些效果并非简单的加法叠加，而是通过各自不同的混合方式对写实渲染结果做色调、轮廓、质感上的风格化修饰。

### 4.1 Toon Fresnel 边缘色

**对应模块**：Frame.008 ToonFresnel

基于视角的边缘色调偏移，在角色轮廓处对 PBR 结果施加风格化的色彩渐变。

```hlsl
float toonFresnelFactor = pow(1.0 - NoV, _ToonfresnelPow);
toonFresnelFactor = SmoothStepCustom(_ToonfresnelSMO_L, _ToonfresnelSMO_H, toonFresnelFactor);
float layerWeight = saturate(toonFresnelFactor * _LayerWeightValue + _LayerWeightValueOffset);
float3 result = lerp(_fresnelInsideColor, _fresnelOutsideColor, layerWeight) * layerWeight;
```

- **`_ToonfresnelPow`** 控制 Fresnel 衰减速度
- **`SmoothStep(SMO_L, SMO_H)`** 裁切和软化边缘范围
- **内/外双色混合**：正面使用 `fresnelInsideColor`，掠射角过渡到 `fresnelOutsideColor`
- 最终输出为**颜色 * 权重**的形式，权重由视角控制，本质上是对 PBR 结果做视角相关的色调偏移

---

### 4.2 屏幕空间边缘光 Rim

**对应模块**：Frame.009 Rim

与传统 Fresnel Rim 不同，本方案使用**屏幕空间深度差检测**作为主要轮廓判据，并通过四个独立因子控制 Rim 的形状与分布。

#### 四因子遮罩链

```
rimMask = DepthRim * FresnelAtten * DirLightAtten * VerticalAtten
```

| 因子 | 计算 | 作用 |
|------|------|------|
| **DepthRim** | 法线方向偏移采样深度图，当前深度 vs 偏移深度的差值 | 检测几何轮廓，只在深度突变处（物体边缘）产生 Rim |
| **FresnelAttenuation** | (1 - NoV)^4 | 掠射角加强，正对相机处抑制 |
| **DirectionalLightAttenuation** | lerp(atten, 1.0, saturate(NoL)) | 光照方向响应，可控背光侧保留量 |
| **VerticalAttenuation** | saturate(normalWS.y) | 顶部强、底部弱，防止脚底 Rim 过亮 |

- **`min(depthRim, 0.5)`** 截断 DepthRim 贡献上限，四因子相乘后幅值已小，防止过曝
- **LoV 调制**：RimColor 中光线背面加强、正面减弱，避免高光与 Rim 重叠
- 最终 Rim 贡献 = **rimColor * rimMask**，颜色本身由 albedo、光色、Rim 参数混合而成

---

### 4.3 视角色变 ThinFilmFilter

**对应模块**：Frame.011 ThinFilmFilter

在角色边缘产生彩虹/光泽色变效果，模拟薄膜干涉或特殊织物反光。

```
facing = pow(1.0 - NdotV, 1.0 / _LayerWeightValue)  // 视角菲涅耳
rsUV = float2(saturate(facing + offset), 0.5)         // 1D LUT 采样坐标
rsColor = lerp(RS_Aurora, RS_Yvonne, _RS_Index)        // 双贴图混合
```

- **双 RS 贴图**（Aurora / Yvonne）：不同材质角色使用不同的色变贴图，通过 `_RS_Index` 混合
- **Facing 驱动 1D LUT**：Y 固定 0.5（中线），仅用视角作为 X 轴，简化为一维查表
- **光照调制**：`rsColor *= saturate(NdotL) * shadowScene`，确保阴影区域不叠加色变
- **LIGHTEN 混合**：`max(baseColor, rsColor)` 取亮值，只增亮不减暗，保护暗部区域

---

### 4.4 伪透射 SimpleTransmission

**对应模块**：Frame.069 SimpleTransmission（管线前置）

通过屏幕空间采样模拟半透明材质的透射效果。

```hlsl
float fresnel = saturate(pow(1.0 - NdotV, 1.0 + ior * 0.5));     // IOR=1.25
float2 offsetScreenUV = screenUV + offsetViewPos.xy * 0.01;
float3 sceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, offsetScreenUV);
float3 result = lerp(sceneColor, albedo, _SimpleTransmissionValue); // 混合场景色与 albedo
```

- 在管线最前端执行，**修改 albedo** 后影响后续所有漫反射计算
- 菲涅尔偏移使边缘处采样到更远的背景，产生折射扭曲感
- `_UseSimpleTransmission` 开关控制，默认混合强度 0.65

---

## 5. 设计特点

### PBR 与 Toon 的平衡

方案没有抛弃 PBR 物理基础，而是在其上叠加风格化处理：
- **高光反射**保留完整的 Cook-Torrance 微表面模型（GGX + Schlick Fresnel + Smith Visibility）
- **间接光照**保留 FGD 预积分和 Kulla-Conty 能量守恒
- **漫反射**通过 SigmoidSharp + Ramp 色带将连续光照响应风格化

这种设计使角色在 PBR 光照环境中保持物理一致性，同时具备卡通手绘感。

### 高度参数化

51 个输入参数覆盖材质的各个维度，7 个功能开关允许按需启用/禁用特定效果：

| 开关 | 控制 |
|------|------|
| UseAnisotropy | 各向异性高光 |
| UseToonAniso | 各向异性分支的 Toon 变体 |
| UseNormalTex | 法线贴图 |
| UseRSEff | 视角色变效果 |
| UseSimpleTransmission | 伪透射 |
| RS_Model | RS 贴图处理路径（Fresnel 路径 / Model 路径） |
| IsSkin | 皮肤材质特殊处理 |

### 模块化 Frame 架构

15 个 Frame 模块各自独立，通过结构体（SurfaceData / LightingData）传递数据。这种设计的优势：
- 单个模块可以独立调试和替换
- 新效果可以作为新 Frame 插入管线而不影响已有模块
- 相同的子群组（如 SigmoidSharp、F_Schlick）在多个 Frame 间复用

---

## 6. 贴图约定

| 贴图 | 通道 | 语义 | 色彩空间 |
|------|------|------|----------|
| **_D** | RGB | Albedo 颜色 | sRGB |
| **_D** | A | Alpha 遮罩 | — |
| **_N** | RG | 切线空间法线 XY | Non-Color |
| **_P** | R | Metallic 金属度 | Non-Color |
| **_P** | G | AO / directOcclusion | Non-Color |
| **_P** | B | Smoothness 感知平滑度 | Non-Color |
| **_P** | A | RampUV（Toon Ramp 行选择） | Non-Color |
| **_E** | RGB | Emission 自发光 | Non-Color |
| **_M** | RGBA | 遮罩（部分材质使用） | Non-Color |
| **RS** | — | 视角色变 LUT（Aurora / Yvonne） | Linear / sRGB |
