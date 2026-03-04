---
description: 分析 Blender 材质节点群组，生成分析文档 + HLSL + Unity ShaderLab
argument-hint: <material_name> <group_name>
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Task, TodoWrite]
---

# analyze-material — Blender 材质节点迁移分析

**调用格式**：`/analyze-material <material_name> <group_name>`

**示例**：`/analyze-material M_actor_pelica_cloth_04 "Arknights: Endfield_PBRToonBase"`

---

## 执行前准备

先读取以下上下文，避免重复工作：

1. 读取 `shader-migration/docs/OUTPUT_REFERENCE.md` → **本次分析的完整规范**（文件结构、命名约定、各阶段必须包含的内容）
2. 读取 `shader-migration/docs/analysis/sub_groups/` 下所有已存在的 `.md` 文件 → 建立**已知子群组列表**
3. 读取 `shader-migration/docs/raw_data/` 下文件列表 → 检查是否已有该群组的 JSON 提取结果
4. 读取 `shader-migration/README.md` → 了解命名约定和溯源规范

---

## 工作流程（共 4 个阶段）

使用 `TodoWrite` 按如下任务列表追踪进度：

```
Phase 1.1  提取主节点群 JSON
Phase 1.2  提取全部子群组 JSON
Phase 1.3  分析 Frame 结构（模块划分）
Phase 1.4  编写 00_材质概览.md
Phase 1.5  编写 01_shader_arch.md（Frame 架构文档）
Phase 1.6  编写新子群组分析文档（跳过已知子群组）
Phase 2    输出 HLSL 文件
Phase 3    输出概念性 Unity ShaderLab
```

---

## Phase 1 — 节点提取与分析

### 1.1 检查/提取主节点群 JSON

检查 `shader-migration/docs/raw_data/<GROUP_SAFE_NAME>_*.json` 是否已存在。

- **若已存在**：直接使用，跳过提取
- **若不存在**：执行如下提取代码（通过 Blender MCP Socket localhost:9876）

```python
# 提取脚本模板 — 通过 socket 发送给 Blender
# 替换 TARGET_MAT 和 TARGET_GROUP 再执行

import socket, json, time, tempfile, os

BLENDER_HOST = 'localhost'
BLENDER_PORT = 9876
TARGET_MAT   = '<material_name>'       # 替换
TARGET_GROUP = '<group_name>'          # 替换
TODAY        = '<YYYYMMDD>'            # 替换为当天日期，格式 20260227
OUT_DIR      = os.path.join(os.getcwd(), 'shader-migration', 'docs', 'raw_data')

TEMP_OUT = os.path.join(tempfile.gettempdir(), 'blender_extract_out.json')

# Blender 端执行代码（字符串）
blender_code = r"""
import bpy, json, os

_target = '""" + TARGET_GROUP + r"""'
ng = bpy.data.node_groups.get(_target)
if ng is None:
    result = {'error': 'NodeGroup not found: ' + _target}
else:
    nodes = []
    for n in ng.nodes:
        node_data = {
            'name': n.name,
            'type': n.type,
            'label': n.label,
            'parent': n.parent.name if n.parent else None,
            'node_tree': n.node_tree.name if hasattr(n, 'node_tree') and n.node_tree else None,
            'inputs':  [{'name': s.name, 'type': str(s.type)} for s in n.inputs],
            'outputs': [{'name': s.name, 'type': str(s.type)} for s in n.outputs],
        }
        nodes.append(node_data)
    links = []
    for lnk in ng.links:
        links.append({
            'from_node':   lnk.from_node.name,
            'from_socket': lnk.from_socket.name,
            'to_node':     lnk.to_node.name,
            'to_socket':   lnk.to_socket.name,
        })
    result = {'group': _target, 'nodes': nodes, 'links': links}

with open(r'""" + TEMP_OUT.replace('\\', '/') + r"""', 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
"""

def blender_exec(code, wait=4):
    """通过 socket 在 Blender 内执行代码"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((BLENDER_HOST, BLENDER_PORT))
    payload = json.dumps({'type': 'execute', 'code': code}).encode()
    s.sendall(payload)
    s.close()
    time.sleep(wait)

blender_exec(blender_code, wait=5)

with open(TEMP_OUT, 'r', encoding='utf-8') as f:
    data = json.load(f)

safe_name = TARGET_GROUP.replace(':', '_').replace(' ', '_')
out_path = os.path.join(OUT_DIR, f'{safe_name}_{TODAY}.json')
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f'已保存: {out_path}')
print(f'节点数: {len(data.get("nodes", []))}')
print(f'连线数: {len(data.get("links", []))}')
```

> **注意**：若群组节点数 > 200，单次提取可能因 socket 超时导致 JSON 截断。
> 此时改为 `wait=8`，或分批提取子群组（见 1.2）。

### 1.2 提取全部子群组 JSON

从主群组 JSON 中找出所有 `type == "GROUP"` 的节点，收集唯一的 `node_tree` 名称，
对每个**未在 `docs/raw_data/` 中存在**的子群组单独提取 JSON。

重用上方提取脚本，将 `TARGET_GROUP` 换成子群组名称，`wait=3` 即可。

### 1.3 分析 Frame 结构

从主群组 JSON 中：

1. 筛选 `type == "FRAME"` 的节点，读取 `label` 字段 → 确定顶级 Frame 模块列表
2. 筛选每个非 FRAME/REROUTE 节点的 `parent` 字段 → 确定节点归属
3. 统计每个 Frame 内的节点数和子群组调用情况
4. 根据数据流（连线 from/to）确定 Frame 之间的依赖顺序

**Frame 命名约定**（参照 PBRToonBase 已有模式）：
- 顶级 Frame：`Frame.xxx`（三位数字）
- 模块内分组：`框.xxx`（汉字框）
- 无标签 Frame：功能从连线上下文推断

### 1.4 编写材质概览文档

输出路径：`shader-migration/docs/analysis/<MATERIAL_SAFE_NAME>/00_material_overview.md`

文档模板：

```markdown
# 00 — 材质概览：<material_name>

> 主节点群：`<group_name>`
> 提取日期：<TODAY> | 溯源：`docs/raw_data/<GROUP_SAFE_NAME>_<TODAY>.json`
> 相关文件：`hlsl/<MATERIAL_SAFE_NAME>/<MaterialName>_Input.hlsl` | `hlsl/<MATERIAL_SAFE_NAME>/<MaterialName>.hlsl` | `unity/Shaders/<MaterialName>.shader`

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | N |
| 连线数 | N |
| 子群组调用数 | N（M 个唯一群组） |

## 贴图输入

| 贴图槽 | 语义 | 通道说明 |
|--------|------|----------|
| `_D` | Diffuse/Albedo | RGB=颜色 A=遮罩 |
| ... | ... | ... |

## 群组接口输入（参数）

| 参数名 | 类型 | 说明 |
|--------|------|------|
| ... | ... | ... |

## 输出

| 输出名 | 类型 | 说明 |
|--------|------|------|
| Result | Shader | 最终着色结果 |
```

### 1.5 编写架构文档

输出路径：`shader-migration/docs/analysis/<MATERIAL_SAFE_NAME>/01_shader_arch.md`

> 遵循 `OUTPUT_REFERENCE.md §G` 视觉格式规范：每个 Frame `###` 模块前加 `---` 分割线，模块标题后附 `📥📤🔗` blockquote 摘要。

文档模板（参照已有的 `PBRToonBase/01_shader_arch.md`）：

```markdown
# 01 — 主群组架构分析：<group_name>

> 溯源：`docs/raw_data/<GROUP_SAFE_NAME>_<TODAY>.json`
> 提取日期：<TODAY>
> 相关文件：`hlsl/<MATERIAL_SAFE_NAME>/<MaterialName>.hlsl` | `hlsl/<MATERIAL_SAFE_NAME>/SubGroups/SubGroups.hlsl`

## 顶级模块（Frame）一览

| Frame | 模块名 | 节点数 | 作用 |
|-------|--------|--------|------|
| Frame.xxx | InitXxx | N | 描述 |
...

## 整体数据流（ASCII 流程图）

```
[贴图输入]
    ↓
[Frame.xxx Init]
    ↓
[Frame.xxx 核心计算]
    ↓
[输出]
` ``

## 各模块详解

---

### Frame.xxx — 模块名

**职责**：...

> 📥 **输入**：变量A（来源 Frame.yyy）· 变量B（贴图）
> 📤 **输出**：结果变量 → Frame.zzz
> 🔗 **子群组**：`SubGroupA`、`SubGroupB`

调用子群组：...

## 子群组 ↔ Frame 归属总表

| 子群组 | 归属 Frame |
|--------|-----------|
| ... | ... |

## 光照模型总结

| 模块 | 实现方式 | Unity 迁移难度 |
|------|----------|----------------|
| ... | ... | 🟢/🟡/🔴 |
```

### 1.6 编写子群组分析文档

**核心规则：复用已知子群组，不重复分析。**

- 读取 `shader-migration/docs/analysis/sub_groups/` 中已有文件
- **已有的子群组**：不新建文档，在架构文档中直接引用路径
- **新出现的子群组**：在 `sub_groups/` 下新建 `<SubGroupName>.md`

> 遵循 `OUTPUT_REFERENCE.md §G` 视觉格式规范：章节标题使用图标（`📊🧮💻📝❓`），每个 `##` 章节之间加 `---` 分割线，接口表使用 `📥📤` 列头。

新子群组文档模板：

```markdown
# <SubGroupName>

> 溯源：`docs/raw_data/<SubGroupName>_<TODAY>.json` | 节点数：N
> HLSL 实现：`hlsl/<MATERIAL_SAFE_NAME>/SubGroups/SubGroups.hlsl` — `<FunctionName>()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| ...     | ...  | ...  |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| ...     | ...  | ...  |

---

## 🔗 内部节点（第三层）

| 节点 | 作用 |
|------|------|
| ...  | ...  |

---

## 📊 计算流程

` ``
step1 → step2 → output
` ``

---

## 🧮 等价公式

数学公式（LaTeX 或文字描述）

---

## 💻 HLSL 等价

` ``hlsl
float FunctionName(float x, ...)
{
    return ...;
}
` ``

---

## 📝 备注

- ⚠️ 与标准实现的差异...
- 对应 HDRP/URP 标准函数...

---

## ❓ 待确认

- [ ] 待补充项
```

---

## Phase 2 — HLSL 输出

### 文件结构

```
shader-migration/hlsl/<MATERIAL_SAFE_NAME>/
  <MaterialName>_Input.hlsl       # 贴图 + 属性 + 结构体
  SubGroups/SubGroups.hlsl        # 所有子群组函数（新+复用）
  <MaterialName>.hlsl             # 主函数，按 Frame 顺序组装
```

> **复用规则**：若子群组函数已在其他材质的 `SubGroups.hlsl` 中存在，
> 可在新文件顶部 `#include` 复用，无需重写。

### 写法规范

- 文件头注释格式（每个文件必须有）：

```hlsl
// =============================================================================
// FileName.hlsl
// 功能描述
// 溯源：docs/analysis/<MATERIAL_SAFE_NAME>/...
// =============================================================================
```

- 每个 Frame 模块用 `// Frame.xxx — 模块名` 分隔
- 允许使用伪代码（如 `GetMainLight()` / `SAMPLE_TEXTURE2D`）
- 不依赖第三层子群组细节，除非用户明确要求

### Input.hlsl 内容

参照 [PBRToonBase_Input.hlsl](../hlsl/PBRToonBase_Input.hlsl) 的格式：

1. **贴图声明**：`TEXTURE2D(_X); SAMPLER(sampler_X);`，附注释说明通道语义
2. **材质属性**：按类别分组（开关 / 粗糙度 / 阴影 / 高光 / Fresnel / Rim / 其他）
3. **顶点输出结构** `Varyings`：positionCS, uv, normalWS, tangentWS, bitangentWS, positionWS, screenPos
4. **表面数据结构** `SurfaceData`：albedo, alpha, metallic, ao, smoothness, 衍生量
5. **光照数据结构** `LightingData`：N/V/L/T/B, 所有点积

### SubGroups.hlsl 内容

- 每个函数前加 `// --- 子群组名 ---` 注释块
- 新增函数紧随最后一个函数之后
- include guard：`#ifndef <MATERIAL>_SUBGROUPS_INCLUDED`

### 主 .hlsl 内容

主要包含：

1. `SurfaceData GetSurfaceData(Varyings input)` — 贴图采样 + 参数计算
2. `LightingData InitLightingData(Varyings input, SurfaceData sd)` — 几何向量初始化
3. `float4 <MaterialName>_Frag(Varyings input)` — 按 Frame 顺序组装最终颜色
4. `Varyings <MaterialName>_Vert(Attributes input)` — 顶点变换

---

## Phase 3 — Unity URP ShaderLab

输出路径：`shader-migration/unity/Shaders/<MaterialName>.shader`

### 文件结构

```
Shader "Goo/<MaterialName>"
{
    Properties { /* 所有材质属性，带 [Header] 分组 */ }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" ... }

        Pass "ForwardLit"     // 主渲染 Pass + Blend 设置
        Pass "ShadowCaster"   // 标准投影 Pass
        Pass "DepthOnly"      // 深度预通（供 DepthRim 使用）
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
```

参照 [PBRToonBase.shader](../unity/Shaders/PBRToonBase.shader) 的格式。

---

## 重用约定总结

| 类型 | 策略 |
|------|------|
| **已有子群组分析文档** | 不重写，架构文档中标注 `（已有文档，见 sub_groups/XXX.md）` |
| **已有 HLSL 子群组函数** | `#include` 复用，不重写 |
| **新材质特有的 Frame 结构** | 完整编写新的架构文档 |
| **新子群组** | 新建分析 .md + 新增 HLSL 函数 |

---

## 输出目录一览

```
shader-migration/
  docs/
    raw_data/
      <GROUP_SAFE_NAME>_<TODAY>.json        # 主群组提取数据
      <SubGroup>_<TODAY>.json               # 各子群组提取数据（新增）
    analysis/
      <MATERIAL_SAFE_NAME>/
        00_material_overview.md             # 材质概览
        01_shader_arch.md                   # Frame 架构文档
      sub_groups/
        <NewSubGroup>.md                    # 新子群组分析（已有跳过）
  hlsl/
    <MATERIAL_SAFE_NAME>/
      <MaterialName>_Input.hlsl
      SubGroups/SubGroups.hlsl
      <MaterialName>.hlsl
  unity/
    Shaders/
      <MaterialName>.shader
```

---

## 调用本命令的参数说明

```
$ARGUMENTS 格式：<material_name> <group_name>

示例：
  M_actor_pelica_cloth_04 "Arknights: Endfield_PBRToonBase"
  M_hair_01 "Arknights: Endfield_PBRHair"
  M_skin_body "Arknights: Endfield_PBRSkin"

若只需要文档分析（不输出 HLSL）：
  在开始时告知用户，并在 TodoWrite 中去掉 Phase 2/3 任务
```
