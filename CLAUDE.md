# GooBlenderProj — Claude 项目上下文

> 本文件由 Claude Code 在会话启动时自动加载。
> 跨机器使用时，请确认 Blender MCP 已在本机启动（默认 localhost:9876）。

---

## 项目结构

```
GooBlenderProj/
├── CLAUDE.md                          ← 本文件（Claude 自动加载）
├── .claude/
│   └── commands/
│       └── analyze-material.md        ← 材质分析 slash command
└── shader-migration/                  ← Shader 迁移工程（独立 git 仓库）
    ├── README.md
    ├── docs/
    │   ├── OUTPUT_REFERENCE.md        ← 输出规范手册（分析前必读）
    │   ├── raw_data/                  ← Blender 提取的原始 JSON
    │   └── analysis/
    │       ├── <MATERIAL>/            ← 每个材质一个子目录
    │       └── sub_groups/            ← 跨材质共享的子群组文档（20个已完成）
    ├── hlsl/                          ← HLSL 代码（伪代码级）
    ├── unity/Shaders/                 ← 概念性 Unity URP ShaderLab
    └── scripts/
        └── extract_nodes.py           ← Blender MCP 节点提取脚本
```

---

## Blender MCP 配置

### 架构总览

```
Claude Code  ←MCP协议→  blender-mcp Server  ←Socket:9876→  Blender Addon
```

### Step 1 — 安装 Blender Addon

1. 下载 `blender_mcp_addon.py`（BlenderMCP v1.26.0）
2. 在 Blender/Goo Engine 中：编辑 → 偏好设置 → 插件 → 从文件安装
3. 选择 `blender_mcp_addon.py` 并启用
4. 每次打开 Blender 后，按 `N` 打开侧边栏 → 找到 **BlenderMCP** 面板 → 点击 **Start MCP Server**
5. 状态显示 `Running on localhost:9876` 即为成功

### Step 2 — 配置 Claude Code MCP Server

在项目根目录的 `.mcp.json` 中已配置（使用本地 `bin/uvx`，无需全局安装 uv）：

```json
{
  "mcpServers": {
    "blender": {
      "command": "./bin/uvx",
      "args": ["--python", "3.12", "blender-mcp"]
    }
  }
}
```

> **必须使用 Python 3.12**：3.14 会因 `pyroaring` 编译失败。
> `bin/uvx` 已包含在工程仓库中，clone 后直接可用，无需额外安装。

### Step 3 — 验证连接

Claude Code 启动后，MCP 工具列表中应出现 `execute_blender_code` 等工具（共22个）。

若 MCP 工具不可用，可改用 **直接 Socket 通信**（见下方）。

---

### 运行环境

| 项目 | 值 |
|------|----|
| 引擎 | Goo Engine 4.4（基于 Blender 4.4） |
| 扩展节点 | `SHADERINFO`、`SCREENSPACEINFO`（Goo Engine 特有） |
| Blender Python | 3.11（**不支持 f-string 内嵌单引号**，用字符串拼接替代） |
| Socket 端口 | `localhost:9876` |
| MCP 版本 | BlenderMCP v1.26.0，22个工具 |

---

### 直接 Socket 通信（MCP 不可用时的备用方案）

```python
import socket, json, time, tempfile, os

def blender_exec(code, wait=4):
    """发送代码到 Blender 执行，wait 秒后读取结果文件"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect(('localhost', 9876))
    cmd = json.dumps({'type': 'execute_code', 'params': {'code': code}}) + '\n'
    s.sendall(cmd.encode())
    time.sleep(wait)
    s.settimeout(5)
    data = b''
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk: break
            data += chunk
    except: pass
    s.close()
    return json.loads(data.decode('utf-8')) if data else {}

# 结果通过临时文件中转（避免大数据被截断）
TEMP_OUT = os.path.join(tempfile.gettempdir(), 'blender_extract_out.json')
```

### 节点提取代码模板（在 Blender 内执行的 Python）

```python
import bpy, json

# 注意：Blender Python 3.11 不支持 f-string 内嵌单引号
# 用变量 _target 代替 f-string
_target = 'GROUP_NAME_HERE'
ng = bpy.data.node_groups.get(_target)
if ng is None:
    result = {'error': 'NodeGroup not found: ' + _target}
else:
    nodes = [{
        'name': n.name, 'type': n.type, 'label': n.label,
        'parent': n.parent.name if n.parent else None,
        'node_tree': n.node_tree.name if hasattr(n, 'node_tree') and n.node_tree else None,
        'inputs':  [{'name': s.name, 'type': str(s.type)} for s in n.inputs],
        'outputs': [{'name': s.name, 'type': str(s.type)} for s in n.outputs],
    } for n in ng.nodes]
    links = [{'from_node': l.from_node.name, 'from_socket': l.from_socket.name,
              'to_node': l.to_node.name,   'to_socket': l.to_socket.name}
             for l in ng.links]
    result = {'group': _target, 'nodes': nodes, 'links': links}

# TEMP_OUT 路径在外层 Python 脚本中定义后字符串替换传入
with open(r'TEMP_OUT_PATH', 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
```

> **大群组（> 200节点）**：建议 `wait=6~8`，防止 Blender 写入未完成时就读取导致 JSON 截断。

---

## 材质分析工作流

### 触发方式

```
/analyze-material <material_name> <group_name>
```

命令文件：`.claude/commands/analyze-material.md`（本目录下，自动加载）

### 四个阶段

| 阶段 | 输出 | 规范参考 |
|------|------|----------|
| Phase 1 提取 | `docs/raw_data/*.json` | — |
| Phase 1 分析 | `docs/analysis/<MATERIAL>/` + `sub_groups/` | `docs/OUTPUT_REFERENCE.md` |
| Phase 2 HLSL | `hlsl/<MATERIAL>/` | `docs/OUTPUT_REFERENCE.md` |
| Phase 3 Unity | `unity/Shaders/<Material>.shader` | `docs/OUTPUT_REFERENCE.md` |

**分析前必读**：`shader-migration/docs/OUTPUT_REFERENCE.md`（命名约定、文件结构、各阶段必须章节）

---

## 复用约定（重要）

### 已分析的子群组（20个，跳过不重复分析）

```
SigmoidSharp / SmoothStep / DecodeNormal
ComputeDiffuseColor / ComputeFresnel0
PerceptualSmoothnessToPerceptualRoughness / PerceptualRoughnessToRoughness
Get_NoH_LoH_ToH_BoH / DV_SmithJointGGX_Aniso / F_Schlick
GetPreIntegratedFGDGGXAndDisneyDiffuse / RampSelect
directLighting_diffuse / DirectionalLightAttenuation
FresnelAttenuation / VerticalAttenuation / DepthRim
Rim_Color / DeSaturation / ShaderOutput
（第三层：Remap01ToHalfTexelCoord / GetinvLenLV）
```

新材质分析 = 差量（新子群组 + 新 Frame 架构） + 复用（已知子群组直接引用）

### 基准参考材质

- 材质：`M_actor_pelica_cloth_04`
- 主群组：`Arknights: Endfield_PBRToonBase`（437节点，15个Frame模块，20个子群组）
- 完成状态：Phase 1~3 全部完成

---

## 工作规范

- **重复内容直接输出**：分析过程中若遇到已知子群组或已追踪过的节点路径，直接引用结论，不重新查询 Blender。
- **节点/帧查找仅做概念性输入输出**：用户询问某个 Frame 或节点的计算流程时，只需列出概念性的上下游输入输出（来源变量 → 模块 → 流向），不做深入子群组分析，目的是让用户快速理解流程。
- **所有文件查找仅限工程目录**：节点数据搜索、JSON 读取等操作只在 `f:\GooBlenderProj\` 内进行，不访问其他路径，避免因路径错误触发中断确认。

---

## 输出规范（摘要）

| 项目 | 规范 |
|------|------|
| 分析粒度 | 只分析主节点群，**不进入第三层节点**，除非明确要求 |
| HLSL 输出 | 伪代码级，不强求可编译 |
| Unity 目标 | 概念性 URP ShaderLab，不需要可运行版本 |
| DepthRim | 展示深度图采样概念即可，不需要完整屏幕空间实现 |
| 文件头 | 每个 HLSL 文件必须有溯源注释块 |
| Frame 分隔 | 主 .hlsl 每个模块前加 `// Frame.xxx — 模块名` 注释 |

---

## 贴图通道语义（PBRToonBase 约定）

| 贴图 | 通道 | 语义 |
|------|------|------|
| `_D` | RGB | Albedo（sRGB） |
| `_D` | A | Alpha |
| `_N` | RG | 切线空间法线 XY（Non-Color） |
| `_P` | R | Metallic |
| `_P` | G | AO / directOcclusion |
| `_P` | B | Smoothness |
| `_P` | A | RampUV（Toon Ramp 行选择） |
| `_E` | RGB | Emission |

---

## 跨机器使用说明

1. Clone 本仓库（含 `bin/`、`blender-mcp/`、`shader-migration/` 全部内容）
2. 安装 Goo Engine，从工程根目录的 `blender_mcp_addon.py` 安装 Blender 插件
3. 打开 Goo Engine → N 面板 → **Start MCP Server**
4. 在本目录启动 Claude Code，`CLAUDE.md` / `.claude/commands/` / `.mcp.json` 自动加载
5. `/analyze-material <材质名> <群组名>` 即可开始
