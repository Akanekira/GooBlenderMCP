# 输出文件参考手册

> 每次分析新材质前必读，确保输出路径、命名和文件结构保持一致。
> 更新日期：2026-02-27 | 当前基准材质：`M_actor_pelica_cloth_04`

---

## 目录结构总览

```
shader-migration/
├── README.md                          # 工程概述与工作流
├── docs/
│   ├── OUTPUT_REFERENCE.md            # 本文件
│   ├── raw_data/                      # Phase 1：Blender 原始提取 JSON
│   └── analysis/                      # Phase 1：分析文档
│       ├── <MATERIAL_SAFE_NAME>/      # 每个材质一个子目录
│       │   ├── 00_material_overview.md
│       │   └── 01_shader_arch.md
│       └── sub_groups/               # 子群组文档（跨材质共享）
│           └── <SubGroupName>.md
├── hlsl/                              # Phase 2：HLSL 代码
│   └── <MATERIAL_SAFE_NAME>/
│       ├── <MaterialName>_Input.hlsl
│       ├── SubGroups/
│       │   └── SubGroups.hlsl
│       └── <MaterialName>.hlsl
├── unity/                             # Phase 3：Unity URP ShaderLab
│   └── Shaders/
│       └── <MaterialName>.shader
└── scripts/
    └── extract_nodes.py               # Blender MCP 提取脚本
```

---

## 命名约定

| 变量 | 说明 | 示例 |
|------|------|------|
| `<MATERIAL_SAFE_NAME>` | 材质名去掉特殊字符，用下划线连接 | `M_actor_pelica_cloth_04` |
| `<GROUP_SAFE_NAME>` | 群组名替换 `:` 和空格为 `_` | `Arknights__Endfield_PBRToonBase` |
| `<MaterialName>` | 主群组的功能名，去掉前缀 | `PBRToonBase` |
| `<TODAY>` | 提取日期，格式 `YYYYMMDD` | `20260227` |

---

## Phase 1 — 原始数据（`docs/raw_data/`）

### 文件命名

```
<GROUP_SAFE_NAME>_<TODAY>.json
```

### 现有文件（已提取，新材质分析前先检查是否可复用）

| 文件 | 内容 | 节点数 |
|------|------|--------|
| `PBRToonBase_full_20260227.json` | 主群组完整节点树 | 437 |
| `M_actor_pelica_cloth_04_nodes_20260227.json` | 材质顶层节点 | — |
| `SigmoidSharp_20260227.json` | 子群组 | — |
| `SmoothStep_20260227.json` | 子群组 | — |
| `DecodeNormal_20260227.json` | 子群组 | — |
| `ComputeDiffuseColor_20260227.json` | 子群组 | — |
| `ComputeFresnel0_20260227.json` | 子群组 | — |
| `PerceptualSmoothnessToPerceptualRoughness_20260227.json` | 子群组 | — |
| `PerceptualRoughnessToRoughness_20260227.json` | 子群组 | — |
| `Get_NoH_LoH_ToH_BoH_20260227.json` | 子群组 | — |
| `DV_SmithJointGGX_Aniso_20260227.json` | 子群组 | — |
| `F_Schlick_20260227.json` | 子群组 | — |
| `GetPreIntegratedFGDGGXAndDisneyDiffuse_20260227.json` | 子群组 | — |
| `RampSelect_20260227.json` | 子群组 | — |
| `directLighting_diffuse_20260227.json` | 子群组 | — |
| `Directional_light_attenuation_20260227.json` | 子群组 | — |
| `Fresnel_attenuation_20260227.json` | 子群组 | — |
| `Vertical_attenuation_20260227.json` | 子群组 | — |
| `DepthRim_20260227.json` | 子群组 | — |
| `Rim_Color_20260227.json` | 子群组 | — |
| `DeSaturation_20260227.json` | 子群组 | — |
| `ShaderOutput_20260227.json` | 子群组 | — |

### JSON 结构

```json
{
  "group": "群组名",
  "nodes": [
    {
      "name": "节点内部名",
      "type": "GROUP / FRAME / MATH / TEX_IMAGE ...",
      "label": "节点标签（Frame 模块名从这里读）",
      "parent": "父 Frame 节点名 或 null",
      "node_tree": "子群组名（type=GROUP 时有值）",
      "inputs":  [{"name": "...", "type": "..."}],
      "outputs": [{"name": "...", "type": "..."}]
    }
  ],
  "links": [
    {
      "from_node": "...", "from_socket": "...",
      "to_node":   "...", "to_socket":   "..."
    }
  ]
}
```

---

## Phase 1 — 分析文档（`docs/analysis/`）

### 1. 材质概览（`00_material_overview.md`）

**路径**：`docs/analysis/<MATERIAL_SAFE_NAME>/00_material_overview.md`

**必须包含**：

| 章节 | 内容 |
|------|------|
| 群组规模 | 节点数、连线数、子群组数 |
| 贴图输入 | 贴图槽名、语义、通道说明（R/G/B/A） |
| 群组接口输入 | 参数名、类型、分类（开关/粗糙度/阴影/高光/Fresnel/Rim/其他） |
| 输出 | 输出名、类型、说明 |

**文件头模板**：

```markdown
# 00 — 材质概览：<material_name>

> 主节点群：`<group_name>`
> 提取日期：<TODAY> | 溯源：`docs/raw_data/<GROUP_SAFE_NAME>_<TODAY>.json`
```

---

### 2. 架构文档（`01_shader_arch.md`）

**路径**：`docs/analysis/<MATERIAL_SAFE_NAME>/01_shader_arch.md`

**必须包含**：

| 章节 | 内容 |
|------|------|
| 群组规模表 | 节点数/连线数/Frame数/子群组数 |
| 顶级 Frame 一览 | Frame编号、模块名、节点数、职责 |
| 整体数据流 | ASCII 流程图，从贴图输入到最终输出 |
| 各模块详解 | 每个 Frame 的职责、子框变量、调用的子群组 |
| 子群组 ↔ Frame 归属总表 | 子群组名 → 所属 Frame |
| 光照模型总结 | 模块、实现方式、Unity 迁移难度（🟢🟡🔴） |
| 待补充 | 未确认项 checklist |

**Frame 分析要点**：
- 从 JSON 中筛选 `type == "FRAME"` 节点，读 `label` 字段确定模块名
- 顶级 Frame：`Frame.xxx`（三位数字）；模块内分组：`框.xxx`（汉字框）
- 每个非 FRAME/REROUTE 节点的 `parent` 字段决定其归属

---

### 3. 子群组文档（`sub_groups/<SubGroupName>.md`）

**复用规则（重要）**：

```
已存在的子群组文档 → 直接引用，不重新分析
只为新出现的子群组创建 .md 文件
```

**现有子群组（20个 + 第三层）**，下次分析前先对照此列表：

```
SigmoidSharp / SmoothStep / DecodeNormal
ComputeDiffuseColor / ComputeFresnel0
PerceptualSmoothnessToPerceptualRoughness / PerceptualRoughnessToRoughness
Get_NoH_LoH_ToH_BoH / DV_SmithJointGGX_Aniso / F_Schlick
GetPreIntegratedFGDGGXAndDisneyDiffuse / RampSelect
directLighting_diffuse / DirectionalLightAttenuation
FresnelAttenuation / VerticalAttenuation / DepthRim
Rim_Color / DeSaturation / ShaderOutput
ThirdLevel_SubGroups（Remap01ToHalfTexelCoord / GetinvLenLV）
```

**新子群组文档必须包含**：

| 章节 | 内容 |
|------|------|
| 接口 | 输入/输出名称与类型 |
| 内部节点 | 节点名与作用 |
| 计算流程 | 文字或 ASCII 流程 |
| 等价公式 | 数学表达式 |
| HLSL 等价 | 伪代码函数签名 + 函数体 |
| 备注 | 对应 HDRP/URP 标准函数、注意事项 |

---

## Phase 2 — HLSL（`hlsl/<MATERIAL_SAFE_NAME>/`）

### 文件清单

| 文件 | 职责 |
|------|------|
| `<MaterialName>_Input.hlsl` | 贴图声明 + 材质属性 + 结构体定义 |
| `SubGroups/SubGroups.hlsl` | 所有子群组 HLSL 函数 |
| `<MaterialName>.hlsl` | 主函数，按 Frame 顺序组装 |

### 强制规范

**文件头注释**（每个文件必须有）：
```hlsl
// =============================================================================
// FileName.hlsl
// 功能描述
// 溯源：docs/analysis/<MATERIAL_SAFE_NAME>/...
// 注：伪代码级 HLSL，供理解渲染流程使用
// =============================================================================
```

**Frame 分隔注释**（主 .hlsl 中每个模块前）：
```hlsl
// -------------------------------------------------------------------------
// Frame.xxx — 模块名（描述）
// 溯源：docs/analysis/.../01_shader_arch.md#framexxx
// -------------------------------------------------------------------------
```

**子群组复用**：
- 若函数已在其他材质 `SubGroups.hlsl` 中存在 → `#include` 引用，不重写
- 新函数紧随已有函数之后追加

### `_Input.hlsl` 内容顺序

1. Include guard + 必要 include
2. 贴图声明（`TEXTURE2D` + `SAMPLER`），附通道语义注释
3. 材质属性（按类别 `[Header]` 分组）
4. `Varyings` 结构体：positionCS / uv / normalWS / tangentWS / bitangentWS / positionWS / screenPos
5. `SurfaceData` 结构体：albedo / alpha / metallic / ao / smoothness / perceptualRoughness / roughness / 各向异性变体 / diffuseColor / fresnel0 / emission / normalTS / rampUV
6. `LightingData` 结构体：N / V / L / T / B / NoV / NoL / LoV / 各向异性点积 / NdotH / LdotH / TdotH / BdotH / lightColor / castShadow

### 主 `.hlsl` 函数顺序

1. `SurfaceData GetSurfaceData(Varyings)` — 贴图采样 + 参数计算
2. `LightingData InitLightingData(Varyings, SurfaceData)` — 几何向量初始化
3. `float4 <MaterialName>_Frag(Varyings) : SV_Target` — 按 Frame 顺序组装
4. `Varyings <MaterialName>_Vert(Attributes)` — 顶点变换

---

## Phase 3 — Unity URP（`unity/Shaders/<MaterialName>.shader`）

### 必须包含的 Pass

| Pass | 用途 |
|------|------|
| `ForwardLit` | 主渲染，`Blend SrcAlpha OneMinusSrcAlpha` |
| `ShadowCaster` | 投影阴影 |
| `DepthOnly` | 深度预通（供 DepthRim 采样 `_CameraDepthTexture`） |

### Properties 分组顺序（`[Header]`）

```
Textures → Switches → Roughness Metallic → Shadow Diffuse
→ Specular → Fresnel ToonFresnel → Rim Light → RS Effect → Other
```

---

## 当前基准参考文件

新材质分析时，优先参照以下文件的格式和风格：

| 参考文件 | 用途 |
|----------|------|
| [docs/analysis/00_material_overview.md](analysis/00_material_overview.md) | 材质概览格式 |
| [docs/analysis/01_shader_arch.md](analysis/01_shader_arch.md) | 架构文档格式 |
| [hlsl/PBRToonBase_Input.hlsl](../hlsl/PBRToonBase_Input.hlsl) | Input 结构体风格 |
| [hlsl/SubGroups/SubGroups.hlsl](../hlsl/SubGroups/SubGroups.hlsl) | 子群组函数风格 |
| [hlsl/PBRToonBase.hlsl](../hlsl/PBRToonBase.hlsl) | 主函数组装风格 |
| [unity/Shaders/PBRToonBase.shader](../unity/Shaders/PBRToonBase.shader) | ShaderLab 结构 |
