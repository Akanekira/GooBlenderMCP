# 项目记忆 — Arknights Endfield Shader Migration

> 最后更新：2026-03-04

---

## Blender PBRToonBase 命名陷阱

### Frame 中英文混用（重要！）

`Arknights: Endfield_PBRToonBase` 群组中存在**中英文混用**的 FRAME 节点命名：

| 类型 | 命名规则 | 示例 |
|------|---------|------|
| 顶级功能模块 | 英文 `Frame.xxx` | `Frame.005` DiffuseBRDF、`Frame.004` SpecularBRDF |
| 内部子框（变量分组） | 中文 `帧.xxx` | `帧.015` shadowNdotL、`帧.019` shadowScene |

**陷阱**：`帧.005`（中文）= `ClampNdotV`（Frame.012 内部子框），与 `Frame.005 DiffuseBRDF`（英文顶级）完全不同。

**正确查找法**：用 Blender MCP 时先列出所有 FRAME + label，再按 label 或精确英文 name 查找。

---

## 已确认的节点语义

### directLighting_diffuse.矢量

- `矢量` 插槽 = `Group Input.dirLight_lightColor`（平行光颜色 RGBA，Vector 类型）
- **不是**光方向向量，是光的颜色
- 确认来源：Frame.005 DiffuseBRDF 分析（2026-03-04，Blender MCP 实时验证）

---

## RampSelect 的 RampUV 是 Vector 类型

RampSelect（群组.011）的 `RampUV` 输入为 **VECTOR 类型**，非 Float。

上游用 `合并 XYZ` 打包：
```
RampUV = float3(shadowCombined, 0.5, 0.0)
         └─ X：阴影值(0~1)，Ramp U 轴
         └─ Y：0.5 固定，Ramp V 轴（在 1D 贴图中采样中线）
         └─ Z：0.0 无效
```

RampSelect.md 原描述 `RampUV` 为 Float（错误），实际为 Vector。

---

## Frame.005 DiffuseBRDF 架构（已完成分析）

双路阴影 → MINIMUM → COMBXYZ → RampSelect → directLighting_diffuse：

```
SigmoidSharp(NoL, HL_center, HL_sharp)          [帧.015 shadowNdotL]
    ↓
MINIMUM ← SigmoidSharp(CastShadow, CS_center, CS_sharp)  [帧.019 shadowScene]
    ↓
COMBXYZ(min, 0.5, 0.0) → RampUV vector          [帧.018 shadowArea]
    ↓
RampSelect(RampUV, RampIndex) → rampColor + rampAlpha
    ↓
directLighting_diffuse(rampColor, directOcclusion, diffuseColor, dirLightColor)
```

输出：
- `directLighting_diffuse` → Vector Math.015（与 Specular ADD 合并）
- `rampAlpha` → Frame.007 ShadowAdjust（SmoothStep.x）

详见：[Frames/Frame005_DiffuseBRDF.md](../../shader-migration/docs/analysis/Frames/Frame005_DiffuseBRDF.md)

---

## 已完成分析的 Frame 文档

| Frame | 标签 | 文档 |
|-------|------|------|
| `Frame.004` | SpecularBRDF | `Frames/Frame004_SpecularBRDF.md` |
| `Frame.005` | DiffuseBRDF | `Frames/Frame005_DiffuseBRDF.md` |

---

## 已完成的 Phase 汇总

- 材质 `M_actor_pelica_cloth_04`：Phase 1~3 全部完成
- 材质 `M_actor_laevat_hair_01`：Phase 1 完成
- 材质 `M_actor_laevat_iris_01`：Phase 1 完成
- 材质 `M_actor_laevat_cloth_05`：Phase 1 完成
- 子群组：20 个已归档（见 `sub_groups/`）
