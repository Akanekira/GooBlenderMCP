---
description: 深入分析单个 Frame 模块，展开全部子群组到底层节点
argument-hint: <Frame.xxx> [group_name]
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Task, TodoWrite]
---

# analyze-frame — 单 Frame 深度分析

**调用格式**：`/analyze-frame <Frame.xxx> [group_name]`

**示例**：
- `/analyze-frame Frame.013` ← 默认群组 `Arknights: Endfield_PBRToonBase`
- `/analyze-frame Frame.013 "Arknights: Endfield_PBRHair"`

**参数说明**：
- `$ARGUMENTS` 格式：`<Frame.xxx> [group_name]`
- `group_name` 省略时默认 `Arknights: Endfield_PBRToonBase`，对应材质 `M_actor_pelica_cloth_04`
- 若指定其他群组，从已有分析目录推断材质名，或提示用户补充

---

## 执行前准备

1. 读取 `shader-migration/docs/OUTPUT_REFERENCE.md` → 确认格式规范（图标、blockquote、分割线）
2. 列出 `shader-migration/docs/analysis/sub_groups/` 下所有 `.md` 文件 → 建立**已知子群组列表**（有文档 = 直接引用，无需重新提取）
3. 列出 `shader-migration/docs/raw_data/` 下文件 → 确认该群组的 JSON 是否已存在

---

## 工作流程

使用 `TodoWrite` 追踪以下任务：

```
Step 1  确认/加载主群组 JSON
Step 2  定位目标 Frame + 收集子节点
Step 3  分析入边/出边（跨 Frame 数据流）
Step 4  展开子群组（已有文档引用 / 无文档则提取并分析）
Step 5  生成 HLSL 伪代码片段
Step 6  输出完整分析（对话 or 写文件）
```

---

## Step 1 — 加载主群组 JSON

检查 `shader-migration/docs/raw_data/` 下是否已有目标群组的 JSON 文件：

- 文件名模式：`<GROUP_SAFE_NAME>_*.json`（`GROUP_SAFE_NAME` = 群组名中 `:` 替换为 `_`，空格替换为 `_`）
- **若已存在**：直接 `Read` 读取，跳过提取
- **若不存在**：执行如下 Socket 提取脚本

```python
import socket, json, time, tempfile, os

BLENDER_HOST = 'localhost'
BLENDER_PORT = 9876
TARGET_GROUP = '<group_name>'   # 替换实际群组名
TODAY        = '<YYYYMMDD>'     # 替换为当天日期
OUT_DIR      = os.path.join(os.getcwd(), 'shader-migration', 'docs', 'raw_data')
TEMP_OUT     = os.path.join(tempfile.gettempdir(), 'blender_extract_out.json')

blender_code = r"""
import bpy, json

_target = '""" + TARGET_GROUP + r"""'
ng = bpy.data.node_groups.get(_target)
if ng is None:
    result = {'error': 'NodeGroup not found: ' + _target}
else:
    nodes = []
    for n in ng.nodes:
        nodes.append({
            'name': n.name, 'type': n.type, 'label': n.label,
            'parent': n.parent.name if n.parent else None,
            'node_tree': n.node_tree.name if hasattr(n, 'node_tree') and n.node_tree else None,
            'inputs':  [{'name': s.name, 'type': str(s.type)} for s in n.inputs],
            'outputs': [{'name': s.name, 'type': str(s.type)} for s in n.outputs],
        })
    links = [{'from_node': lnk.from_node.name, 'from_socket': lnk.from_socket.name,
              'to_node': lnk.to_node.name, 'to_socket': lnk.to_socket.name}
             for lnk in ng.links]
    result = {'group': _target, 'nodes': nodes, 'links': links}

with open(r'""" + TEMP_OUT.replace('\\', '/') + r"""', 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
"""

def blender_exec(code, wait=5):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((BLENDER_HOST, BLENDER_PORT))
    payload = json.dumps({'type': 'execute', 'code': code}).encode()
    s.sendall(payload)
    s.close()
    time.sleep(wait)

blender_exec(blender_code, wait=6)   # 大群组用 wait=8

with open(TEMP_OUT, 'r', encoding='utf-8') as f:
    data = json.load(f)

safe_name = TARGET_GROUP.replace(':', '_').replace(' ', '_')
out_path  = os.path.join(OUT_DIR, f'{safe_name}_{TODAY}.json')
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f'已保存: {out_path}，节点数: {len(data.get("nodes",[]))}')
```

---

## Step 2 — 定位目标 Frame

> ⚠️ **命名陷阱（已验证，2026-03-04）**：
> `Arknights: Endfield_PBRToonBase` 群组中存在**中英文混用**的 Frame 命名：
> - **顶级功能模块**使用英文名：`Frame.005`（DiffuseBRDF）、`Frame.004`（SpecularBRDF）等
> - **内部子框**使用中文名：`帧.015`（shadowNdotL）、`帧.018`（shadowArea）等
>
> **关键区别**：`帧.005`（中文）= `ClampNdotV`（Frame.012 内部子框），与 `Frame.005`（英文顶级）完全不同。
>
> **正确查找方式**：
> - 用 Blender MCP 时：先列出所有 FRAME 节点及 label，再按 label 或精确 name 匹配
> - JSON 中按 `label` 字段匹配（如 `label == "DiffuseBRDF"`），比按 name 更可靠
> - 使用 MCP 时优先 `n.name == 'Frame.005'`（精确英文名），而非 `'Frame.005' in n.name`

从 JSON 的 `nodes` 列表中：

1. 找出 `type == "FRAME"` 且 **`label`** 匹配目标模块名（如 `"DiffuseBRDF"`）的节点 → 记录 `frame_node_name`
   - 若用 MCP 提取，先列出所有 FRAME 的 name+label，确认后再按精确 name 查子节点
2. 收集所有 `parent == frame_node_name` 的节点 → 这就是该 Frame 的**直接子节点集合**
3. 按 `type` 分类：`GROUP`（子群组调用）/ `TEX_IMAGE`（贴图采样）/ 其他内置节点

> 若存在嵌套 Frame（子帧），先找顶级 Frame，再递归收集子帧内的节点。

---

## Step 3 — 分析入边 / 出边

从 JSON 的 `links` 列表中，遍历所有连线：

- **入边**：`to_node` 在 Frame 子节点集合内，且 `from_node` 不在集合内 → 来自外部
- **出边**：`from_node` 在 Frame 子节点集合内，且 `to_node` 不在集合内 → 流向外部

整理格式：

```
入边：<来源节点/Frame> . <来源 socket>  →  <目标节点> . <目标 socket>
出边：<Frame 内节点> . <输出 socket>    →  <目标节点/Frame> . <目标 socket>
```

---

## Step 4 — 展开子群组

对 Step 2 中所有 `type == "GROUP"` 的节点，按如下规则处理：

### 4a — 已有文档的子群组（直接引用）

若 `shader-migration/docs/analysis/sub_groups/<SubGroupName>.md` 已存在：

- **不重新提取**，直接读取该文档的**接口表**和 **HLSL 等价**章节
- 在分析输出中标注：`（已有文档，见 sub_groups/<SubGroupName>.md）`
- 引用其函数签名用于主 HLSL 伪代码

### 4b — 无文档的子群组（完整提取并分析）

若无文档，执行：

1. 检查 `raw_data/<SubGroupName>_*.json` 是否存在；不存在则通过 Socket 提取（`wait=3`）
2. 从 JSON 展开**全部节点**（递归到无 GROUP 节点为止）
3. 按以下模板生成子群组分析（直接输出到对话，**不自动写文件**，除非用户说"保存"）：

```markdown
### 子群组：<SubGroupName>

> 节点数：N | 溯源：raw_data/<SubGroupName>_<TODAY>.json

#### 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| ...     | ...  | ...  |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| ...     | ...  | ...  |

#### 内部节点（第三层）

| 节点 | 类型 | 作用 |
|------|------|------|
| ...  | ...  | ...  |

#### 等价公式

...（数学描述）

#### HLSL 等价

```hlsl
float SubGroupName(...)
{
    return ...;
}
` ``
```

> **递归规则**：若该子群组内部仍有 GROUP 节点，继续展开，直到所有节点均为 Blender 内置节点（MathNode / VectorMath / Mix / Dot 等）为止。

---

## Step 5 — HLSL 伪代码片段

为目标 Frame 生成独立的 HLSL 伪代码，格式：

```hlsl
// =============================================================================
// Frame.<xxx> — <模块名>
// 群组：<group_name>  |  溯源：docs/raw_data/<GROUP_SAFE_NAME>_<TODAY>.json
// =============================================================================

// --- 入参（来自外部 Frame 或群组接口）---
// <变量名> : <类型>  ←  <来源描述>

void Frame_<xxx>_<ModuleName>(
    /* 入参 */,
    /* 出参（out） */
)
{
    // --- 内置节点计算 ---

    // --- 子群组调用（已有文档直接使用函数签名） ---
    float result = SubGroupName(arg1, arg2, ...);

    // --- 输出赋值 ---
}
```

- 子群组以函数调用形式展开（签名来自 4a/4b 的接口分析）
- 内置节点（Math/VectorMath/Mix 等）直接展开为行内表达式
- 使用伪代码可读性优先，不要求可编译

---

## Step 6 — 最终输出

将以上内容整合，按如下顺序输出到**对话**：

```markdown
# Frame.<xxx> — <模块名> 深度分析

> 群组：`<group_name>` | 材质：`<material_name>`
> 溯源：`docs/raw_data/<GROUP_SAFE_NAME>_*.json`

---

## 基本信息

| 项目 | 值 |
|------|-----|
| Frame 节点名 | Frame.xxx |
| 模块标签 | <label> |
| 子节点数 | N |
| 子群组调用数 | N（M 个唯一） |

---

## 📥 输入

| 来源节点/Frame | Socket | 目标节点 | Socket |
|----------------|--------|----------|--------|
| ...            | ...    | ...      | ...    |

---

## 📤 输出

| Frame 内节点 | Socket | 目标节点/Frame | Socket |
|--------------|--------|----------------|--------|
| ...          | ...    | ...            | ...    |

---

## 🔗 子群组

| 子群组 | 文档状态 | 主要功能 |
|--------|----------|----------|
| <Name> | ✅ 已有文档 / 📝 本次分析 | ... |

---

## 📊 内部节点详解

（逐节点说明：类型 → 输入连接 → 输出连接 → 计算作用）

---

## 子群组展开

（按 4a/4b 规则，展开每个子群组的接口 + 公式 + HLSL）

---

## 💻 HLSL 伪代码

（Step 5 生成的完整片段）
```

### 可选写文件

当用户说"写入文件"或"保存"时，输出到：

```
shader-migration/docs/analysis/<MATERIAL_SAFE_NAME>/frames/<Frame.xxx>.md
```

---

## 关键约定

| 项目 | 值 |
|------|-----|
| 默认群组 | `Arknights: Endfield_PBRToonBase` |
| 默认材质 | `M_actor_pelica_cloth_04` |
| 默认 JSON 路径 | `shader-migration/docs/raw_data/Arknights__Endfield_PBRToonBase_*.json` |
| 分析粒度 | **递归到无 GROUP 节点为止**（底层内置节点全量展开） |
| 已知子群组 | 有 `sub_groups/<Name>.md` → 直接引用，**不重新提取** |
| 无文档子群组 | 提取 JSON + 完整分析 + 现场生成文档内容 |
| 输出方式 | 默认输出到对话；用户说"保存"才写文件 |
| 格式规范 | 遵循 `OUTPUT_REFERENCE.md §G`（图标、blockquote、分割线） |
