# Plan: M_actor_pelica_face_01 材质分析与 HLSL 迁移

> 本文件为任务计划，供上下文过长时调用新 agent 继续使用。
> 创建日期：2026-03-06

## Context

**目标材质**：`M_actor_pelica_face_01`
**主节点群**：`Arknights: Endfield_PBRToonBaseFace`（328 节点，350 连线，15 个唯一子群组）
**基准对比**：`M_actor_pelica_cloth_04` / `Arknights: Endfield_PBRToonBase`（437 节点，20 个唯一子群组）

### 已完成的前置工作
- ✅ 主群组 JSON 已提取：`docs/raw_data/Arknights__Endfield_PBRToonBaseFace_20260306.json`
- ✅ 两个新子群组 JSON 已提取：`Recalculate_normal_20260306.json`、`Front_transparent_red_20260306.json`
- ✅ `00_material_overview.md` 已完成：`docs/analysis/Materials/M_actor_pelica_face_01/00_material_overview.md`
- ✅ 20+ 个已知子群组文档均已存在（`docs/analysis/sub_groups/`）

### Face Shader 与 Cloth Shader 的关键差异

| 方面 | PBRToonBase (Cloth) | PBRToonBaseFace (Face) |
|------|---------------------|------------------------|
| 架构 | 15 个 Frame.xxx 模块层级 | 扁平结构，44 个变量级 Frame 标签 |
| 法线 | DecodeNormal (法线贴图 XY) | Recalculate normal (球面法线重映射，骨骼驱动) |
| 阴影 | halfLambert + SigmoidSharp | SDF 贴图查询 + calculateAngel + 下巴/鼻子独立阴影 |
| Rim | DepthRim + 4 个衰减因子 | 移除经典 Rim，仅保留屏幕空间信息 |
| 薄膜 | ThinFilmFilter | 移除 |
| Fresnel | ToonFresnel | 移除 |
| 新增 | — | Front transparent red (SSS 近似)、SDF Shadow、解剖遮罩 |
| 各向异性 | 使用 T/B 轴分离 | 仅各向同性 GGX |

**Face 移除的模块**：DecodeNormal, RampSelect, DepthRim, FresnelAttenuation, VerticalAttenuation, Rim_Color, DirectionalLightAttenuation, ShaderOutput, ThinFilmFilter, ToonFresnel

**Face 新增的子群组**：Recalculate normal, Front transparent red, calculateAngel（已有文档）

---

## 任务清单（TodoWrite 格式）

### Phase 1 — 分析文档

#### Task 1.1: 编写 `01_shader_arch.md`
- **输出**：`shader-migration/docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md`
- **参考格式**：`docs/analysis/Materials/M_actor_pelica_cloth_04/01_shader_arch.md`
- **规范**：`docs/OUTPUT_REFERENCE.md` §G 视觉格式（`---` 分割线，`📥📤🔗` blockquote）
- **关键**：Face 的 44 个 Frame 是变量级标签而非模块容器，需按语义重新归纳为逻辑模块：
  1. 几何/向量基础（N, V, L, 各点积）— 含 Recalculate normal
  2. 表面参数（albedo, metallic, roughness, fresnel0）
  3. SDF 阴影系统（calculateAngel → SDF 采样 → SigmoidSharp → 下巴覆盖）
  4. 面部解剖特征（chinLambertShadow, noseShadowColor, directOcclusion）
  5. 漫反射 BRDF（directLighting_diffuse + Ramp + DeSaturation）
  6. 镜面 BRDF（DV_SmithJointGGX_Aniso + F_Schlick → directLighting_specular）
  7. 间接光照（FGD LUT + energyCompensation）
  8. 面部特效（Front transparent red, 屏幕空间 Rim, 高光贴图叠加）
  9. 最终合成

#### Task 1.2: 编写 `Recalculate_normal.md`（可与 1.3 并行）
- **输出**：`shader-migration/docs/analysis/sub_groups/Recalculate_normal.md`
- **数据源**：`docs/raw_data/Recalculate_normal_20260306.json`
- **特点**：球面法线重映射，输入为骨骼属性（headCenter, headUp, headRight, headForward）+ sphereNormal_Strength

#### Task 1.3: 编写 `Front_transparent_red.md`（可与 1.2 并行）
- **输出**：`shader-migration/docs/analysis/sub_groups/Front_transparent_red.md`
- **数据源**：`docs/raw_data/Front_transparent_red_20260306.json`
- **特点**：SSS 近似，参数 Front R Color / Pow / Smo，模拟耳朵/嘴唇透光

### Phase 2 — HLSL 输出

#### Task 2.1: 编写 `PBRToonBaseFace_Input.hlsl`
- **输出**：`shader-migration/hlsl/M_actor_pelica_face_01/PBRToonBaseFace_Input.hlsl`
- **参考**：`shader-migration/hlsl/PBRToonBase_Input.hlsl`（186 行）
- **内容**：
  - 贴图：_D, _N, _P, _E + _SDF, _ChinMask, _HighlightMask, _RampLUT, _FGD_LUT
  - 材质属性：面部特有参数（sphereNormal_Strength, Front R 系列, SDF 系列, chin/nose 参数）
  - Varyings：增加骨骼属性（headCenter/Up/Right/Forward, LightDirection）
  - SurfaceData / LightingData 结构体

#### Task 2.2: 创建面部 `SubGroups/SubGroups.hlsl`
- **输出**：`shader-migration/hlsl/M_actor_pelica_face_01/SubGroups/SubGroups.hlsl`
- **策略**：`#include "../../SubGroups/SubGroups.hlsl"` 复用共享函数，新增：
  - `RecalculateNormal()` — 球面法线重映射
  - `FrontTransparentRed()` — SSS 近似

#### Task 2.3: 编写 `PBRToonBaseFace.hlsl`
- **输出**：`shader-migration/hlsl/M_actor_pelica_face_01/PBRToonBaseFace.hlsl`
- **参考**：`shader-migration/hlsl/PBRToonBase.hlsl`（523 行）
- **函数结构**：
  1. `GetSurfaceData()` — 贴图采样 + 参数计算
  2. `InitLightingData()` — 几何向量（RecalculateNormal 替代 DecodeNormal）
  3. `SDFShadow()` — calculateAngel → SDF 采样 → SigmoidSharp → 下巴覆盖
  4. `DiffuseBRDF()` — Ramp + 阴影混合 + DeSaturation + noseShadowColor
  5. `SpecularBRDF()` — 各向同性 GGX（无 T/B 分离）
  6. `IndirectLighting()` — FGD + 能量补偿
  7. `FaceEffects()` — Front transparent red, 高光贴图叠加, 屏幕空间 Rim
  8. `PBRToonBaseFace_Frag()` — 主函数
  9. `PBRToonBaseFace_Vert()` — 顶点变换

### Phase 3 — Unity URP ShaderLab

#### Task 3.1: 编写 `PBRToonBaseFace.shader`
- **输出**：`shader-migration/unity/Shaders/PBRToonBaseFace.shader`
- **参考**：`shader-migration/unity/Shaders/PBRToonBase.shader`
- **内容**：概念性 URP ShaderLab（Properties + ForwardLit + ShadowCaster + DepthOnly）

---

## 执行顺序与依赖

```
Task 1.2 (Recalculate_normal.md) ──┐
Task 1.3 (Front_transparent_red.md)─┼─→ Task 1.1 (01_shader_arch.md)
                                    ↓
                              Task 2.1 (Input.hlsl)
                              Task 2.2 (SubGroups.hlsl)  ← 可与 2.1 并行
                                    ↓
                              Task 2.3 (Main .hlsl)
                                    ↓
                              Task 3.1 (.shader)
```

## 复用资源

| 资源 | 路径 | 用途 |
|------|------|------|
| 主群组 JSON | `docs/raw_data/Arknights__Endfield_PBRToonBaseFace_20260306.json` | 架构分析数据源 |
| Recalculate_normal JSON | `docs/raw_data/Recalculate_normal_20260306.json` | 子群组分析 |
| Front_transparent_red JSON | `docs/raw_data/Front_transparent_red_20260306.json` | 子群组分析 |
| 材质概览 | `docs/analysis/Materials/M_actor_pelica_face_01/00_material_overview.md` | 参考 |
| Cloth 架构文档 | `docs/analysis/Materials/M_actor_pelica_cloth_04/01_shader_arch.md` | 格式模板 |
| 20+ 子群组文档 | `docs/analysis/sub_groups/*.md` | 直接引用 |
| 共享 SubGroups.hlsl | `hlsl/SubGroups/SubGroups.hlsl` | `#include` 复用 |
| Base Input.hlsl | `hlsl/PBRToonBase_Input.hlsl` | 结构参考 |
| Base 主 HLSL | `hlsl/PBRToonBase.hlsl` | 流程参考 |
| OUTPUT_REFERENCE | `docs/OUTPUT_REFERENCE.md` | 格式规范 |

## 验证方式

1. 检查所有输出文件符合 OUTPUT_REFERENCE.md 规范
2. 确认 15 个唯一子群组全部在架构文档中有引用（13 复用 + 2 新增）
3. 确认主 HLSL 中各语义模块均有对应代码段
4. 确认文件头溯源注释指向正确的 JSON 和分析文档
