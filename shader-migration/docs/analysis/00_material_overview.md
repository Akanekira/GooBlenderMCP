# 00 — 材质概览：M_actor_pelica_cloth_04

> 主节点群：`Arknights: Endfield_PBRToonBase`
> 溯源：`docs/raw_data/M_actor_pelica_cloth_04_nodes_20260227.json`
> 提取日期：2026-02-27
> 相关文件：`hlsl/PBRToonBase_Input.hlsl` | `hlsl/PBRToonBase.hlsl` | `unity/Shaders/PBRToonBase.shader`

---

## 材质结构（顶层）

材质节点树共 7 个节点，结构极为扁平：

```
[TEX_IMAGE] 图像纹理    ─── _D ─→ ┐
[TEX_IMAGE] 图像纹理.001 ─── _N ─→ │
[TEX_IMAGE] 图像纹理.002 ─── _E ─→ ├─→ [GROUP] 群组.001
[TEX_IMAGE] 图像纹理.003 ─── _P ─→ │    Arknights: Endfield_PBRToonBase
[TEX_IMAGE] 图像纹理.004 (RD，未连线) ┘
                                         └─→ Result ─→ [OUTPUT_MATERIAL]
```

---

## 贴图语义

| 节点名 | 文件名 | 连接插槽 | 语义 | 色彩空间 |
|--------|--------|----------|------|----------|
| 图像纹理 | `T_actor_pelica_cloth_01_D.png` | `_D(sRGB)R.G.B` / `_D(sRGB).A` | Diffuse/Albedo，RGB=颜色，A=遮罩/AO | sRGB |
| 图像纹理.001 | `T_actor_pelica_cloth_01_N.png` | `_N(非色彩Non_Color)` | 法线贴图，切线空间 XY | Non-Color |
| 图像纹理.002 | `T_actor_pelica_cloth_01_E.png` | `_E（非色彩）` | Emission 自发光 | Non-Color（插槽标注） |
| 图像纹理.003 | `T_actor_pelica_cloth_01_P.png` | `_P(非色彩)R.G.B` / `_P(非色彩)A` | 参数贴图（RGB+A），详见下方通道拆解 | Non-Color |
| 图像纹理.004 | `TPLK_actor_common_cloth_03_RD.png` | **未连线** | 公共 Toon Ramp LUT（推测由 RampSelect 内部引用） | — |

### _P 贴图通道推断

`_P` 贴图分两路接入：
- `R.G.B` → `_P(非色彩Non_Color)R.G.B`（Vector 插槽）
- `.A` → `_P(非色彩Non_Color)A`（Float 插槽）

结合 Arknights: Endfield 角色 Shader 惯例，通道语义推断为：

| 通道 | 推断语义 | 备注 |
|------|----------|------|
| R | Metallic | 金属度 |
| G | AO / Occlusion | 环境遮蔽，用于 directOcclusion |
| B | Smoothness | 感知平滑度，需乘以 SmoothnessMax |
| A | 材质 ID / Ramp Mask | 用于 RampSelect 的 RampUV |

> **待确认**：_P 各通道准确含义，需对比实际渲染结果或查阅原游戏资产规范。

---

## 群组接口参数（完整 51 个输入）

### 贴图直接输入
| 参数名 | 类型 | 来源 |
|--------|------|------|
| `_D(sRGB)R.G.B` | Color | _D 贴图 RGB |
| `_D(sRGB).A` | Float | _D 贴图 Alpha |
| `_N(非色彩Non_Color)` | Vector | _N 贴图 Color |
| `_P(非色彩Non_Color)R.G.B` | Vector | _P 贴图 RGB |
| `_P(非色彩Non_Color)A` | Float | _P 贴图 Alpha |
| `_E（非色彩）` | Color | _E 贴图 Color |
| `_M（非色彩）` | Color | **未连线**（此材质） |
| `BaseColor` | Color | **未连线**（此材质，可能走默认值） |

### 开关 Boolean 控制
| 参数名 | 含义 |
|--------|------|
| `Is Skin?` | 皮肤模式开关（影响 SSS/Diffuse 处理） |
| `Use anisotropy?` | 是否启用各向异性高光 |
| `Use Toonaniso?` | 是否启用 Toon 各向异性 |
| `Use NormalTex?` | 是否使用法线贴图 |
| `Use RS_Eff?` | 是否启用 Rim/Special 特效 |
| `Use Simple transmission？` | 简化透射模式 |
| `RS Model` | RS（Rim/Special）模型选择 |

### 粗糙度/金属度控制
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `SmoothnessMax` | Float | Smoothness 最大值乘数 |
| `Aniso_SmoothnessMaxT` | Float | 各向异性切线方向 Smoothness 最大值 |
| `Aniso_SmoothnessMaxB` | Float | 各向异性副切线方向 Smoothness 最大值 |
| `MetallicMax` | Float | Metallic 最大值乘数 |

### 光照/阴影控制
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `RemaphalfLambert_center` | Float | halfLambert 阴影过渡中心点 |
| `RemaphalfLambert_sharp` | Float | halfLambert 阴影过渡锐度 |
| `CastShadow_center` | Float | 投影阴影过渡中心点 |
| `CastShadow_sharp` | Float | 投影阴影过渡锐度 |
| `RampIndex` | Float | Toon 色带索引（选择哪条 Ramp） |
| `dirLight_lightColor` | Color | 平行光颜色 |
| `directOcclusionColor` | Color | 直接遮蔽颜色 |
| `AmbientLightColorTint` | Color | 环境光色调 |
| `GlobalShadowBrightnessAdjustment` | Float | 全局阴影亮度调整 |
| `Color desaturation in shaded areas attenuation` | Float | 暗部去饱和强度 |

### 高光控制
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `SpecularColor` | Color | 高光颜色叠加 |
| `NormalStrength` | Float | 法线强度 |
| `specularFGD Strength` | Float | FGD 预积分高光强度 |

### Fresnel / Toon Fresnel 控制
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `fresnelInsideColor` | Color | 内侧 Fresnel 颜色 |
| `fresnelOutsideColor` | Color | 外侧 Fresnel 颜色 |
| `ToonfresnelPow` | Float | Toon Fresnel 幂次 |
| `_ToonfresnelSMO_L` | Float | Toon Fresnel 平滑下限 |
| `_ToonfresnelSMO_H` | Float | Toon Fresnel 平滑上限 |
| `Layer weight Value` | Float | LayerWeight Fresnel 基础值 |
| `Layer weight Value Offset` | Float | LayerWeight Fresnel 偏移 |

### Rim Light 控制
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `Rim_DirLightAtten` | Float | 平行光对 Rim 的衰减系数 |
| `Rim_width_X` | Float | Rim 宽度（屏幕水平方向） |
| `Rim_width_Y` | Float | Rim 宽度（屏幕垂直方向） |
| `Rim_Color` | Color | Rim 颜色 |
| `Rim_ColorStrength` | Float | Rim 颜色强度 |

### RS (Rim/Special Effect) 控制
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `RS_Index` | Float | RS 效果索引 |
| `RS Strength` | Float | RS 效果强度 |
| `RS Multiply Value` | Float | RS 效果乘数 |
| `RS ColorTint` | Color | RS 颜色叠加 |

### 其他
| 参数名 | 类型 | 含义 |
|--------|------|------|
| `Alpha` | Float | 整体透明度 |
| `Anisotropic mask` | Float | 各向异性遮罩 |
| `Simple transmission Value` | Float | 简化透射值 |

---

## 群组输出
| 插槽 | 类型 | 含义 |
|------|------|------|
| `Result` | Shader | 最终着色结果（接入材质输出 Surface） |
| `Debug` | Color | 调试通道（未接入材质输出） |

---

## 待确认问题

- [ ] `_P` 贴图 B 通道是否为 Smoothness（还是 AO/其他）
- [ ] `_M（非色彩）` 在其他材质（如皮肤材质）中的实际用途
- [ ] `图像纹理.004 (TPLK_..._RD.png)` 是否由 `RampSelect` 内部图像纹理节点直接引用
- [ ] `BaseColor` 插槽在此材质中使用默认值还是另有来源
