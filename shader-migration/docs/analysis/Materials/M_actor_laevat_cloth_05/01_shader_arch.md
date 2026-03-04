# 01 — 主群组架构分析：Arknights: Endfield_PBRToonBase（laevat_cloth_05 视角）

> 溯源：`docs/raw_data/PBRToonBase_full_20260227.json`（群组结构与 pelica_cloth_04 完全相同）
> 材质 JSON：`docs/raw_data/M_actor_laevat_cloth_05_nodes_20260302.json`
> 提取日期：2026-03-02
> 相关文件：`hlsl/M_actor_laevat_cloth_05/PBRToonBase_Cloth05.hlsl` | `hlsl/M_actor_laevat_cloth_05/SubGroups/SubGroups.hlsl`
>
> **本文为差量文档**：群组内部 Frame 架构与 pelica_cloth_04 完全一致，详细架构见 `docs/analysis/Materials/M_actor_pelica_cloth_04/01_shader_arch.md`。
> 本文仅记录 laevat_cloth_05 的**特有差异**及 `_M` 贴图激活的影响分析。

---

## 群组规模（共享，无变化）

| 指标 | 数量 |
|------|------|
| 总节点数 | 437 |
| 连线数 | 410 |
| 顶级 Frame 模块 | 15 |
| 子群组调用数 | 26（20 个唯一群组） |

所有子群组均已有文档，见 `docs/analysis/sub_groups/`，本材质**无新增子群组**。

---

## 与 pelica_cloth_04 的架构差异

### 差异 1：`_M` 贴图首次激活

**pelica_cloth_04**：`_M（非色彩）` 插槽未连线，走群组默认值（黑色/零）。

**laevat_cloth_05**：在材质层增加了 `_M` 预处理链：

```
[UV 贴图] → UV
    ↓
[TEX_IMAGE] T_actor_laevat_cloth_03_M.png
    ↓ Color (RGB)
[SmoothStep] min=0, max=1, x=M_tex.RGB
    ↓ 输出
[群组.001] _M（非色彩）← 输入
```

等价 HLSL：
```cpp
float2 uvM = input.uv;  // UV 贴图节点（默认 UV0，待确认是否 UV2）
float3 mTex  = SAMPLE_TEXTURE2D(_M, sampler_M, uvM).rgb;
float3 mMask = SmoothStep(0.0, 1.0, mTex);
// mMask → 送入群组 _M 插槽
```

**`_M` 在群组内的作用推断**：

根据 PBRToonBase 群组架构（`docs/analysis/Materials/M_actor_pelica_cloth_04/01_shader_arch.md`），`_M（非色彩）`
在群组内最可能连接到以下位置之一：

| 可能位置 | 依据 |
|----------|------|
| **框.048 RS EFF** — RS 特效遮罩 | 本材质 `Use RS_Eff? = True`，且 RS Model = True，具备 RS 效果 |
| **Frame.011 ThinFilmFilter** — 薄膜区域遮罩 | ThinFilm 常用遮罩控制发生位置 |
| **Frame.013 GetSurfaceData** — 各向异性遮罩叠加 | `Anisotropic mask = 0.0`（默认），_M 可能替代或叠加 |

> 实际连线需在 Blender 中查询 `Arknights: Endfield_PBRToonBase` 群组内 `Group Input._M（非色彩）` 的连线目标。

---

### 差异 2：`_E` 贴图未连线 → Frame.010 Emission 失效

pelica_cloth_04 中 `_E` 接入 `_E（非色彩）` 插槽，驱动 Frame.010 Emission 模块叠加自发光。

laevat_cloth_05 中该槽未连线，Frame.010 接收默认值（黑色），**Emission 效果不启用**。

等价 HLSL 变化：
```cpp
// pelica_cloth_04:
s.emission = SAMPLE_TEXTURE2D(_E, sampler_E, input.uv).rgb;

// laevat_cloth_05:
s.emission = float3(0, 0, 0);  // 未连线，默认黑色
```

---

### 差异 3：输出插槽 `(Viewer)` 而非 `Result`

laevat_cloth_05 的材质节点树中，群组输出连到 `(Viewer)` 插槽（Goo Engine 调试输出），而非 `Result`。
功能上等价，迁移时统一使用 `Result` 插槽输出即可。

---

## 顶级模块一览（完整，参照基准架构）

架构与 pelica 相同，差异列于"本材质激活状态"列：

| Frame | 模块名 | 本材质激活状态 |
|-------|--------|---------------|
| `Frame.012` | Init | ✅ 完整激活 |
| `Frame.013` | GetSurfaceData | ✅（_M 输入新激活） |
| `Frame.005` | DiffuseBRDF | ✅ |
| `Frame.004` | SpecularBRDF | ✅（各向异性：MaxT=0.22, MaxB=0.67） |
| `Frame.006` | IndirectLighting | ✅ |
| `Frame.007` | ShadowAdjust | ✅（GlobalShadowBrightness = -1.8） |
| `Frame.008` | ToonFresnel | ✅ |
| `Frame.009` | Rim | ✅（Rim_width_X=0.0418, Y=0.0191, Strength=5.0） |
| `Frame.010` | Emission | ⚠️ **无效**（_E 未连线） |
| `Frame.011` | ThinFilmFilter | ✅（_M 可能影响此模块） |
| `Frame.014` | Alpha | ✅（不透明：Alpha=1.0） |

---

## 整体数据流（laevat_cloth_05 特化版）

```
贴图输入：
  T_actor_laevat_cloth_02_D → _D(sRGB)
  T_actor_laevat_cloth_02_N → _N
  T_actor_laevat_cloth_02_P → _P
  T_actor_laevat_cloth_03_M → SmoothStep → _M  ← 新增
  （_E 未连线）
        │
        ▼
┌─────────────────────────────────┐
│  Frame.012  Init                │
│  N, V, L, T, B, 各点积         │
│  DecodeNormal / Get_NoH_...     │
└──────────┬──────────────────────┘
           │
┌──────────▼──────────────────────┐
│  Frame.013  GetSurfaceData      │
│  _D/N/P/M 贴图拆通道           │
│  _M 在此或下游某处介入          │
└──────┬───────────────┬──────────┘
       │               │
┌──────▼──────┐  ┌─────▼────────────┐
│ Frame.005   │  │  Frame.004        │
│ DiffuseBRDF │  │  SpecularBRDF     │
└──────┬──────┘  └─────┬────────────┘
       │               │
       └───────┬────────┘
               ▼
        Frame.006 IndirectLighting
               ▼
        Frame.007 ShadowAdjust
               ▼
        Frame.008 ToonFresnel
               ▼
        Frame.009 Rim
               ▼
        Frame.010 Emission  ← 输入黑色（_E 未连）
               ▼
        Frame.011 ThinFilmFilter ← _M 可能在此参与
               ▼
        Frame.014 Alpha → (Viewer) → 材质输出
```

---

## 子群组 ↔ Frame 归属总表（全部复用，无新增）

| 子群组 | 归属 Frame | 文档 |
|--------|-----------|------|
| `DecodeNormal` | Init | `sub_groups/DecodeNormal.md` |
| `Get_NoH_LoH_ToH_BoH` | Init | `sub_groups/Get_NoH_LoH_ToH_BoH.md` |
| `ComputeDiffuseColor` | GetSurfaceData | `sub_groups/ComputeDiffuseColor.md` |
| `ComputeFresnel0` | GetSurfaceData | `sub_groups/ComputeFresnel0.md` |
| `PerceptualSmoothnessToPerceptualRoughness` ×3 | GetSurfaceData | `sub_groups/PerceptualSmoothnessToPerceptualRoughness.md` |
| `PerceptualRoughnessToRoughness` ×3 | GetSurfaceData | `sub_groups/PerceptualRoughnessToRoughness.md` |
| `SigmoidSharp` ×2 | DiffuseBRDF | `sub_groups/SigmoidSharp.md` |
| `RampSelect` | DiffuseBRDF | `sub_groups/RampSelect.md` |
| `directLighting_diffuse` | DiffuseBRDF | `sub_groups/directLighting_diffuse.md` |
| `DV_SmithJointGGX_Aniso` | SpecularBRDF | `sub_groups/DV_SmithJointGGX_Aniso.md` |
| `F_Schlick` | SpecularBRDF | `sub_groups/F_Schlick.md` |
| `GetPreIntegratedFGDGGXAndDisneyDiffuse` | IndirectLighting | `sub_groups/GetPreIntegratedFGDGGXAndDisneyDiffuse.md` |
| `SmoothStep` | ShadowAdjust / ToonFresnel / 材质层 | `sub_groups/SmoothStep.md` |
| `DirectionalLightAttenuation` | Rim | `sub_groups/DirectionalLightAttenuation.md` |
| `DepthRim` | Rim | `sub_groups/DepthRim.md` |
| `FresnelAttenuation` | Rim | `sub_groups/FresnelAttenuation.md` |
| `VerticalAttenuation` | Rim | `sub_groups/VerticalAttenuation.md` |
| `Rim_Color` | Rim | `sub_groups/Rim_Color.md` |
| `DeSaturation` | 无标签 Frame（Rim 附近） | `sub_groups/DeSaturation.md` |
| `ShaderOutput` | Alpha | `sub_groups/ShaderOutput.md` |

---

## 光照模型总结

| 模块 | 实现方式 | Unity 迁移难度 | laevat 特有说明 |
|------|----------|----------------|----------------|
| Init | 几何向量点积 | 🟢 易 | — |
| GetSurfaceData | 贴图采样 + PBR 转换 | 🟢 易 | _M 槽新激活，需补充连线确认 |
| DiffuseBRDF | halfLambert + Sigmoid + Toon Ramp | 🟡 中 | — |
| SpecularBRDF | 各向异性 Smith-GGX（MaxT=0.22, MaxB=0.67） | 🟡 中 | 各向异性参数与 pelica 不同 |
| IndirectLighting | FGD LUT 预积分 | 🟡 中 | — |
| ShadowAdjust | SmoothStep（GlobalShadow=-1.8） | 🟢 易 | 阴影压暗明显 |
| ToonFresnel | LayerWeight + SmoothStep | 🟢 易 | — |
| Rim | DepthRim（屏幕空间深度） | 🔴 难 | Rim_width 较小（布料边缘光细） |
| Emission | 直接叠加 | 🟢 易 | **_E 未连线，Emission=黑色** |
| ThinFilmFilter | LayerWeight + LUT | 🟡 中 | _M 可能参与遮罩 |
| Alpha | Transparent 混合 | 🟢 易 | 完全不透明(Alpha=1.0) |

---

## 待确认

- [ ] 查询 `Arknights: Endfield_PBRToonBase` 群组内 `_M（非色彩）` Group Input 的实际连线目标节点
- [ ] 确认 `UV 贴图` 节点使用的是 UV0 还是第二套 UV（可能 _M 使用独立 UV 通道）
- [ ] 确认 `_M` 的 Color 三通道是否均用于 SmoothStep，还是只用 R 通道
