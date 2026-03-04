# 00 — 材质概览：M_actor_laevat_cloth_05

> 主节点群：`Arknights: Endfield_PBRToonBase`
> 提取日期：2026-03-02 | 溯源：`docs/raw_data/M_actor_laevat_cloth_05_nodes_20260302.json`
> 群组 JSON：`docs/raw_data/PBRToonBase_full_20260227.json`（与 pelica_cloth_04 共享同一群组）
> 相关文件：`hlsl/M_actor_laevat_cloth_05/PBRToonBase_Cloth05_Input.hlsl` | `hlsl/M_actor_laevat_cloth_05/PBRToonBase_Cloth05.hlsl` | `unity/Shaders/PBRToonBase_Cloth05.shader`

---

## 材质结构（顶层）

材质节点树共 **8 个节点**，与 pelica_cloth_04 的核心差异：
- `_M` 贴图**首次连线**（pelica 未连接）：经由 `SmoothStep` 预处理后输入群组
- `_E` 贴图**未连线**（无 Emission 效果）
- 新增 `UV 贴图` 节点专为 `_M` 贴图提供 UV 驱动

```
[UV 贴图]
    │ UV
    ▼
[TEX_IMAGE] 图像纹理  ─── _M(R) ─→ [GROUP:SmoothStep]
                                         │ 输出(SmoothStep化的_M)
                                         ↓
[TEX_IMAGE] 图像纹理.001 ─── _D ─→ ┐
[TEX_IMAGE] 图像纹理.002 ─── _N ─→ ├─→ [GROUP] 群组.001
[TEX_IMAGE] 图像纹理.003 ─── _P ─→ │    Arknights: Endfield_PBRToonBase
                      (_E 未连线)   ┘
                                         └─→ (Viewer) ─→ [OUTPUT_MATERIAL]
```

---

## 贴图语义

| 节点名 | 文件名 | 连接插槽 | 语义 | 色彩空间 |
|--------|--------|----------|------|----------|
| 图像纹理 | `T_actor_laevat_cloth_03_M.png` | `_M（非色彩）`（经 SmoothStep） | 遮罩贴图，R 通道经 SmoothStep(0,1) 平滑后输入 | Non-Color |
| 图像纹理.001 | `T_actor_laevat_cloth_02_D.png` | `_D(sRGB)R.G.B` / `_D(sRGB).A` | Diffuse/Albedo，RGB=颜色，A=遮罩 | sRGB |
| 图像纹理.002 | `T_actor_laevat_cloth_02_N.png` | `_N(非色彩Non_Color)` | 法线贴图，切线空间 XY | Non-Color |
| 图像纹理.003 | `T_actor_laevat_cloth_02_P.png` | `_P(非色彩Non_Color)R.G.B` / `_P(非色彩Non_Color)A` | 参数贴图（RGB+A），见下方通道拆解 | Non-Color |
| —— | **（无 _E 贴图连线）** | `_E（非色彩）` | Emission 插槽未使用，走默认值（黑色） | — |

### _M 贴图预处理流程

```
T_actor_laevat_cloth_03_M.png
    → 图像纹理.Color (RGB)
    → 群组 SmoothStep [min=0, max=1, x=M_tex.RGB]
    → 输出 → 群组.001._M（非色彩）
```

等价 HLSL：
```cpp
float3 mTex = SAMPLE_TEXTURE2D(_M, sampler_M, uv_M).rgb;
float3 mMask = SmoothStep(0.0, 1.0, mTex);  // 输入到 _M 槽
```

> `_M` 槽在群组内部的用途：根据 PBRToonBase 群组架构，`_M（非色彩）` 最可能用于 **RS Effect（Frame.011 ThinFilmFilter / 框.048 RS EFF）** 的遮罩控制，或作为各向异性遮罩的来源。
> pelica 材质中该槽未连线，本材质首次激活，具体效果参见 Group 内部 `_M` 的连线（见 01_shader_arch.md）。

### _P 贴图通道

| 通道 | 推断语义 | 备注 |
|------|----------|------|
| R | Metallic | `× MetallicMax(1.0)` |
| G | AO / directOcclusion | 直接遮蔽 |
| B | Smoothness | `× SmoothnessMax(1.0)` |
| A | 材质 ID / RampUV | 用于 RampSelect 的 RampUV |

---

## 群组规模（共享群组，与 pelica_cloth_04 相同）

| 指标 | 数量 |
|------|------|
| 总节点数 | 437 |
| 连线数 | 410 |
| 顶级 Frame 模块 | 15 |
| 子群组调用数 | 26（20 个唯一群组） |

---

## 群组接口参数（本材质的具体数值）

### 开关设置

| 参数名 | 数值 | 含义 |
|--------|------|------|
| `Is Skin?` | `False` | 非皮肤材质 |
| `Use anisotropy?` | **`True`** | 启用各向异性高光 |
| `Use Toonaniso?` | **`True`** | 启用 Toon 各向异性 |
| `Use NormalTex?` | **`True`** | 使用法线贴图 |
| `Use RS_Eff?` | **`True`** | 启用 RS 特效 |
| `Use Simple transmission？` | `False` | 不启用简化透射 |
| `RS Model` | **`True`** | RS 模型模式 B |

### 粗糙度 / 金属度

| 参数名 | 数值 |
|--------|------|
| `SmoothnessMax` | 1.0 |
| `Aniso_SmoothnessMaxT` | **0.2197**（各向异性 T 轴上限，较低 → 切线方向更粗糙） |
| `Aniso_SmoothnessMaxB` | **0.6689**（各向异性 B 轴上限，较高 → 副切线方向更光滑） |
| `MetallicMax` | 1.0 |

### 阴影 / 漫反射

| 参数名 | 数值 |
|--------|------|
| `RemaphalfLambert_center` | 0.570 |
| `RemaphalfLambert_sharp` | 0.180 |
| `CastShadow_center` | 0.0 |
| `CastShadow_sharp` | 0.170 |
| `RampIndex` | 0.0 |
| `GlobalShadowBrightnessAdjustment` | **-1.800**（较深的阴影压暗） |
| `Color desaturation in shaded areas attenuation` | **0.900** |

### 法线 / 高光

| 参数名 | 数值 |
|--------|------|
| `NormalStrength` | **1.446** |
| `specularFGD Strength` | 1.0 |

### ToonFresnel

| 参数名 | 数值 |
|--------|------|
| `ToonfresnelPow` | **1.700** |
| `_ToonfresnelSMO_L` | 0.0 |
| `_ToonfresnelSMO_H` | **0.500** |
| `Layer weight Value` | 0.0 |
| `Layer weight Value Offset` | 0.0 |

### Rim Light

| 参数名 | 数值 |
|--------|------|
| `Rim_DirLightAtten` | **0.962** |
| `Rim_width_X` | **0.04185** |
| `Rim_width_Y` | **0.01911** |
| `Rim_ColorStrength` | **5.0** |

### RS Effect

| 参数名 | 数值 |
|--------|------|
| `RS_Index` | 0.0 |
| `RS Strength` | 1.0 |
| `RS Multiply Value` | 1.0 |

### 其他

| 参数名 | 数值 |
|--------|------|
| `Alpha` | 1.0 |
| `Anisotropic mask` | 0.0 |
| `Simple transmission Value` | 0.0 |

---

## 与基准材质 pelica_cloth_04 的差量对比

| 项目 | pelica_cloth_04 | laevat_cloth_05 |
|------|-----------------|-----------------|
| `_D` 贴图 | `T_actor_pelica_cloth_01_D.png` | `T_actor_laevat_cloth_02_D.png` |
| `_N` 贴图 | `T_actor_pelica_cloth_01_N.png` | `T_actor_laevat_cloth_02_N.png` |
| `_P` 贴图 | `T_actor_pelica_cloth_01_P.png` | `T_actor_laevat_cloth_02_P.png` |
| `_E` 贴图 | `T_actor_pelica_cloth_01_E.png`（已连线） | **未连线** |
| `_M` 贴图 | 未连线 | **`T_actor_laevat_cloth_03_M.png` → SmoothStep → `_M`** |
| 材质节点总数 | 7 | **8**（多一个 SmoothStep + UV 贴图节点）|
| UV 贴图节点 | 无 | **有**（专为 _M 驱动 UV） |
| `RS Model` | （需确认） | `True` |
| 输出插槽 | `Result` | `(Viewer)`（Goo Engine 调试模式） |

---

## 群组输出

| 插槽 | 类型 | 含义 |
|------|------|------|
| `(Viewer)` | Shader | 最终着色结果（Goo Engine 调试输出，功能同 Result） |
| `Result` | Shader | 标准输出（未连线） |
| `Debug` | Color | 调试通道（未连线） |

---

## 待确认问题

- [ ] `_M（非色彩）` 在群组内部连接到哪个节点（需查看 PBRToonBase 群组内 _M 输入的连线目标）
- [ ] `T_actor_laevat_cloth_03_M.png` R/G/B 通道各自语义（为何只用 Color 整体输入 SmoothStep）
- [ ] UV 贴图节点是否使用第二套 UV（UV2）还是默认 UV0
- [ ] `(Viewer)` 输出在最终渲染时是否等价于 `Result`
