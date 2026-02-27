# Shader Migration: Blender → HLSL → Unity

> 目标：将 Goo Engine 中的 `Arknights: Endfield_PBRToonBase` Toon PBR 渲染方案，通过节点分析迁移为 Unity HLSL Shader。

---

## 工程目录结构

```
shader-migration/
├── README.md                        ← 本文件，工作流总览
├── docs/
│   ├── analysis/
│   │   ├── 00_material_overview.md  ← 材质全局概览（输入贴图语义、参数说明）
│   │   ├── 01_shader_arch.md        ← 主群组架构分析（流向图 + 各阶段说明）
│   │   ├── 02_lighting_model.md     ← 光照模型推导（Diffuse / Specular / Rim）
│   │   └── sub_groups/              ← 每个子群组独立分析文档
│   │       ├── DecodeNormal.md
│   │       ├── ComputeDiffuseColor.md
│   │       ├── ComputeFresnel0.md
│   │       ├── PerceptualSmoothness.md
│   │       ├── SigmoidSharp.md
│   │       ├── SmoothStep.md
│   │       ├── RampSelect.md
│   │       ├── DirectionalLightAttenuation.md
│   │       ├── Get_NoH_LoH_ToH_BoH.md
│   │       ├── DV_SmithJointGGX_Aniso.md
│   │       ├── F_Schlick.md
│   │       ├── GetPreIntegratedFGD.md
│   │       ├── DepthRim.md
│   │       ├── FresnelAttenuation.md
│   │       ├── VerticalAttenuation.md
│   │       ├── Rim_Color.md
│   │       ├── directLighting_diffuse.md
│   │       ├── DeSaturation.md
│   │       └── ShaderOutput.md
│   └── raw_data/                    ← MCP 提取的原始 JSON，供溯源
│       ├── M_actor_pelica_cloth_04_nodes.json
│       ├── PBRToonBase_full.json
│       └── [sub_group_name].json
├── hlsl/
│   ├── PBRToonBase.hlsl             ← 主 Shader 入口（组装所有子函数）
│   ├── PBRToonBase_Input.hlsl       ← 输入结构体定义（贴图、参数）
│   └── SubGroups/                   ← 对应每个子群组的 HLSL 实现
│       ├── DecodeNormal.hlsl
│       ├── ComputeDiffuseColor.hlsl
│       ├── ... (每个子群组一个文件)
│       └── ShaderOutput.hlsl
├── unity/
│   ├── Shaders/
│   │   └── PBRToonBase.shader       ← Unity ShaderLab 封装
│   └── Materials/
│       └── [验证用材质]
└── scripts/
    ├── extract_nodes.py             ← MCP 节点提取脚本（可复用）
    └── analyze_group.py             ← 递归分析指定群组并输出文档
```

---

## 工作阶段

### Phase 1 — 节点提取与原始数据归档
**目标**：通过 Blender MCP 将所有相关节点树导出为结构化 JSON，存入 `docs/raw_data/`。

| 步骤 | 内容 | 产物 |
|------|------|------|
| 1.1 | 提取顶层材质节点（贴图接口、连线） | `M_actor_pelica_cloth_04_nodes.json` |
| 1.2 | 提取 `PBRToonBase` 群组完整结构 | `PBRToonBase_full.json` |
| 1.3 | 递归提取全部 26 个子群组 | `[sub_group_name].json` × 26 |
| 1.4 | 记录每个节点的：类型、参数默认值、连线关系 | 同上 |

**注意**：JSON 只记录结构，不做任何推断，保证溯源真实性。

---

### Phase 2 — 架构分析与文档撰写
**目标**：理解每个子群组的数学语义，写成人可读的分析文档存入 `docs/analysis/`。

| 步骤 | 内容 | 产物 |
|------|------|------|
| 2.1 | 整理贴图语义（_D/_N/_P/_E/_M 各通道含义） | `00_material_overview.md` |
| 2.2 | 绘制主群组数据流向图 | `01_shader_arch.md` |
| 2.3 | 推导光照模型（halfLambert、Toon Ramp、GGX Aniso） | `02_lighting_model.md` |
| 2.4 | 逐一分析 26 个子群组（节点列表 + 等价数学公式） | `sub_groups/*.md` |

每个子群组文档格式：
```markdown
# [SubGroupName]
## 输入 / 输出
## 内部节点列表
## 等价数学公式
## 备注（与标准 PBR 的差异）
```

---

### Phase 3 — HLSL 实现
**目标**：将每个子群组的分析文档转写为对应 `.hlsl` 函数文件。

| 步骤 | 内容 | 产物 |
|------|------|------|
| 3.1 | 定义输入结构体（SurfaceData、LightingData） | `PBRToonBase_Input.hlsl` |
| 3.2 | 逐群组实现，函数签名对齐分析文档 | `SubGroups/*.hlsl` |
| 3.3 | 组装主 Shader 入口，复现流向图 | `PBRToonBase.hlsl` |
| 3.4 | 处理 Blender 特有节点的等价实现 | （见下方映射表） |

**Blender 节点 → HLSL 映射速查**：

| Blender 节点 | HLSL 等价 |
|---|---|
| `ShaderNodeMixRGB (MIX)` | `lerp(a, b, t)` |
| `ShaderNodeMath (MULTIPLY)` | `a * b` |
| `ShaderNodeVectorMath (DOT_PRODUCT)` | `dot(a, b)` |
| `ShaderNodeVectorMath (NORMALIZE)` | `normalize(v)` |
| `ShaderNodeClamp` | `clamp(x, min, max)` |
| `ShaderNodeSeparateXYZ` | `.x / .y / .z` |
| `ShaderNodeCombineXYZ` | `float3(x, y, z)` |
| `ShaderNodeNewGeometry` | `IN.normalWS / IN.viewDirWS` 等 |
| `ShaderNodeTangent` | `IN.tangentWS` |
| `ShaderNodeLayerWeight` | Fresnel 近似：`pow(1 - dot(N,V), blend)` |
| `ShaderNodeFresnel` | `FresnelSchlick` |
| `ShaderNodeCameraData` | `_WorldSpaceCameraPos` |
| `ShaderNodeAttribute` | 顶点色 / UV |
| `ShaderNodeScreenspaceInfo` (GooEngine) | 屏幕空间参数，待确认实现 |
| `ShaderNodeShaderInfo` (GooEngine) | 光照信息扩展节点，待确认实现 |

---

### Phase 4 — Unity 集成与验证
**目标**：将 HLSL 封装为 Unity ShaderLab，比对渲染结果。

| 步骤 | 内容 | 产物 |
|------|------|------|
| 4.1 | 创建 ShaderLab 骨架，定义 Properties 对应 PBRToonBase 接口 | `PBRToonBase.shader` |
| 4.2 | 接入 URP/Custom RenderPipeline 光照数据 | 同上 |
| 4.3 | 创建验证材质，绑定佩丽卡布料贴图 | `Materials/` |
| 4.4 | 对比 Blender 视窗截图与 Unity Game 视图 | 截图对比文档 |
| 4.5 | 修正差异（色调映射、gamma、坐标系差异） | 迭代修订 |

---

## 待确认问题

- [ ] `ShaderNodeShaderInfo` / `ShaderNodeScreenspaceInfo` 是 Goo Engine 扩展节点，需确认其输出的具体含义
- [ ] `RampSelect` 中的色带贴图来源（是 LUT 贴图还是渐变节点？）
- [ ] `_P` 贴图各通道的确切语义（Metallic / AO / Smoothness / ?）
- [ ] Toon 阴影 Ramp 在 Unity URP 中的光照数据接入方式
- [ ] Alpha 混合模式（Transparent / Cutout？）

---

## 分析复用约定

**子群组和 Frame 的分析结论全局共享，不随材质重复分析。**

新增材质分析时，只需关注：
1. **材质层差异**：连接了哪些贴图、哪些参数值不同
2. **新增子群组**：若该材质引用了未分析过的群组，才写新文档

以下内容已在 `PBRToonBase_full` 分析中覆盖，**其他材质直接引用，不重复分析**：
- `docs/analysis/sub_groups/` 下所有 20 个子群组
- `docs/analysis/01_shader_arch.md` 的 15 个 Frame 模块结构

---

## 溯源约定

- 所有分析结论必须在文档中注明来源节点名称（如 `群组.007 [DV_SmithJointGGX_Aniso]`）
- 若发现节点连线与文档描述不符，以 `docs/raw_data/` 中的 JSON 为准
- 每次 MCP 提取数据后更新 JSON，文件名加日期后缀（如 `PBRToonBase_full_20260227.json`）

---

## 当前进度

- [x] Phase 1.1 — 顶层材质节点提取（`M_actor_pelica_cloth_04`，7个节点）
- [x] Phase 1.2 — `PBRToonBase` 群组完整结构提取（437节点，26子群组）
- [ ] Phase 1.3 — 26 个子群组递归提取
- [ ] Phase 2 — 架构分析文档
- [ ] Phase 3 — HLSL 实现
- [ ] Phase 4 — Unity 集成
