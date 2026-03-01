# 01 — 主群组架构分析：Arknights: Endfield_PBRToon_irisBase

> 溯源：`docs/raw_data/Arknights__Endfield_PBRToon_irisBase_20260302.json`
> 提取日期：20260302
> 相关文件：`hlsl/M_actor_laevat_iris_01/PBRToon_irisBase.hlsl` | `hlsl/M_actor_laevat_iris_01/SubGroups/SubGroups.hlsl`

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 25（含 2 个 REROUTE） |
| 连线数 | 29 |
| 顶级 Frame 数 | 0（无 Frame 分层，节点完全平铺） |
| 子群组数 | 1（`calculateAngel`） |

> **与 PBRToonBase 的对比**：该群组规模极小（PBRToonBase 为 437 节点、15 个 Frame），是一个高度专用的辅助 Emission 群组，而非完整的 PBR 着色器。

---

## 架构说明：无 Frame 结构

本群组所有节点 `parent` 字段均为 `null`，即不存在 Frame（模块）层级。
整体逻辑可分为以下三条独立分支，最终汇合于 `ADD_SHADER` 输出：

| 分支 | 节点范围 | 作用 |
|------|----------|------|
| **A. 角度阈值分支** | 属性×4 → calculateAngel → SUBTRACT → CLAMP → MIX_MULTIPLY | 根据灯光角度调制虹膜底色亮度 |
| **B. Matcap UV + 主高光** | TEX_COORD → VECT_TRANSFORM → VECT_MATH×2 → TEX_IMAGE.001 → MIX_MULTIPLY → MIX_ADD | Matcap 贴图提供镜面高光，与角度结果叠加 |
| **C. 辅助 Matcap 高光** | TEX_IMAGE.002 → EMISSION(强度 0.7) | 固定强度的第二层 Matcap 高光 |

---

## 整体数据流（ASCII 流程图）

```
[几何属性: LightDirection / headUp / headRight / headForward]
                         ↓
              [calculateAngel]
                         ↓ AngleThreshold
              [SUBTRACT (angle - 0.5)]
                         ↓
              [CLAMP (0.5, 1.0)]  →  angleClamp
                         ↓
[D_RGB] → [MIX MULTIPLY (A=D_RGB, B=angleClamp)] → angle_iris
                         ↓
                 [MIX ADD (A=angle_iris, B=matcap_combined)] → main_color
                         ↓                                           ↑
   [D_Alpha, Eyes_brightness, angle×HLBrightness]    [matcap_05×D_RGB]
                         ↓                                           ↑
              [MIX FLOAT → strength]             [TEX_COORD.Normal]
                         |                        → [World→Camera]
                         ↓                        → [×0.5]
              [EMISSION(color=main_color,          → [+0.5]
               strength=strength)]                → [TEX_IMAGE.001(matcap_05)]
                         |
                         ↓
              [ADD_SHADER] ← [EMISSION(TEX_IMAGE.002(matcap_07), strength=0.7)]
                         ↓
                    [GROUP OUTPUT: Emission]
```

---

## 各模块详解

### A — 角度阈值分支

**职责**：根据主光源与角色头部朝向的相对角度，计算虹膜高光的强度权重。

**节点序列**：

| 节点名 | 类型 | 参数/连接 | 作用 |
|--------|------|-----------|------|
| `属性.001` | ATTRIBUTE | `headForward` (GEOMETRY) | 读取头部前向向量 |
| `属性.002` | ATTRIBUTE | `headRight` (GEOMETRY) | 读取头部右向向量 |
| `属性.003` | ATTRIBUTE | `headUp` (GEOMETRY) | 读取头部上向向量 |
| `属性.004` | ATTRIBUTE | `LightDirection` (GEOMETRY) | 读取光源方向向量 |
| `群组`（AngleThreshold） | GROUP | `calculateAngel` | 计算光源相对头部坐标系的方位角 |
| `运算` | MATH SUBTRACT | `AngleThreshold - 0.5` | 平移角度范围，使 [0.5, 1.0] 区间产生有效高光 |
| `钳制` | CLAMP MINMAX | min=0.5, max=1.0 | 限制到有效高光范围 |
| `混合` | MIX RGBA MULTIPLY | A=D_RGB, B=angleClamp | 角度权重调制虹膜颜色 |

**调用子群组**：`calculateAngel`（已有分析文档，见 `sub_groups/calculateAngel.md`）

---

### B — Matcap UV 与主高光分支

**职责**：利用视空间法线 UV 采样 Matcap 贴图，叠加到角度结果上形成镜面感高光。

**节点序列**：

| 节点名 | 类型 | 参数/连接 | 作用 |
|--------|------|-----------|------|
| `纹理坐标` | TEX_COORD | Normal 输出（世界空间法线） | 获取顶点法线 |
| `矢量变换` | VECT_TRANSFORM | World→Camera, VECTOR | 法线转换为相机空间 |
| `矢量运算` | VECT_MATH MULTIPLY | ×[0.5, 0.5, 0] | Matcap UV 缩放到 [-.5, .5] |
| `矢量运算.001` | VECT_MATH ADD | +[0.5, 0.5, 0] | 偏移到 [0, 1] UV 范围 |
| `图像纹理.001` | TEX_IMAGE | `T_actor_common_matcap_05_D.png` | 采样主 Matcap 高光 |
| `混合.003` | MIX RGBA MULTIPLY | A=matcap_05, B=D_RGB | 以虹膜颜色着色 Matcap |
| `混合.002` | MIX RGBA ADD | factor=0.567, A=angle_iris, B=matcap_tinted | 合并角度分支与 Matcap 高光 |

**Matcap UV 公式**：

```
N_world = TexCoord.Normal
N_cam   = TransformWorldToCamera(N_world)
matcap_uv = N_cam.xy * 0.5 + 0.5
```

---

### C — 辅助 Matcap 高光（固定层）

**职责**：叠加第二层 Matcap 高光，提供固定强度的额外光泽感。

| 节点名 | 类型 | 参数 | 作用 |
|--------|------|------|------|
| `图像纹理.002` | TEX_IMAGE | `T_actor_common_matcap_07_D.png` | 采样辅助 Matcap（同 UV） |
| `自发光` | EMISSION | Strength=0.7（固定） | 固定强度辅助高光 Emission |

> 注：`图像纹理.002` 在 JSON 中无 Vector 输入连接，使用节点默认 UV（与 `.001` 相同的 matcap_UV 隐式共享，或使用 Blender 默认 UV 坐标）。

---

### D — 亮度控制分支

**职责**：根据光照角度和遮罩计算最终 Emission 强度。

| 节点名 | 类型 | 参数/连接 | 作用 |
|--------|------|-----------|------|
| `运算.001` | MATH MULTIPLY | A=AngleThreshold-0.5, B=Eyes_HightLight_brightness | 角度权重 × 高光亮度峰值 |
| `混合.001` | MIX FLOAT | Factor=D_Alpha, A=Eyes_brightness, B=运算.001 | Alpha 遮罩插值基础亮度与高光亮度 |
| `自发光(发射)` | EMISSION | Color=main_color, Strength=混合.001 | 主 Emission（角度+Matcap 驱动） |

**强度公式**：
```
angle_strength = (AngleThreshold - 0.5) * Eyes_HightLight_brightness
emission_strength = lerp(Eyes_brightness, angle_strength, D_Alpha)
```

---

## 子群组 ↔ 模块归属总表

| 子群组 | 调用位置 | 文档 |
|--------|----------|------|
| `calculateAngel` | 分支 A（角度阈值） | `docs/analysis/sub_groups/calculateAngel.md`（**新增**） |

---

## 光照模型总结

| 模块 | 实现方式 | Unity 迁移难度 |
|------|----------|----------------|
| 光照角度计算 | 基于骨骼属性的头部坐标系 atan2 | 🔴（需要自定义骨骼数据传递机制） |
| Matcap 高光 | 相机空间法线 × 0.5 + 0.5 采样 Matcap | 🟢（标准 Matcap，URP 易实现） |
| 亮度混合 | Alpha 遮罩 lerp(base, peak, mask) | 🟢（直接对应 lerp） |
| Emission 叠加 | ADD_SHADER | 🟢（对应 Additive Blend 或 Emission 叠加） |

> **最大迁移难点**：`LightDirection / headUp / headRight / headForward` 这四个几何属性需要从骨骼系统传递到 GPU。在 Unity 中需要通过自定义 `MaterialPropertyBlock` 或 vertex attribute（来自 `SkinnedMeshRenderer` bone 数据）传入，没有 Blender 的 Geometry Nodes 属性机制。

---

## 待确认

- [ ] `图像纹理.002`（matcap_07）是否也使用 matcap UV，还是使用默认的 UV0？从 JSON 中无 Vector 输入连线，需在 Blender 中确认实际行为。
- [ ] `混合`（MIX MULTIPLY, B=angleClamp）：float value 连入 RGBA B 槽的行为——Blender 是否将标量广播为灰度色？
- [ ] `calculateAngel` 输出的 `Flip threshold`（= sX）在本材质中未被使用，是为其他材质预留的接口？
