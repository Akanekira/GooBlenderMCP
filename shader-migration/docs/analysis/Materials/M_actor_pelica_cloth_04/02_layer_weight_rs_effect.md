# 02 — LAYER_WEIGHT 节点精确分析 & RS Effect 管线

> 溯源：`docs/raw_data/PBRToonBase_full_20260227.json`
> 分析日期：2026-03-03
> 关联文档：[01_shader_arch.md](01_shader_arch.md)、[final_color_assembly.md](final_color_assembly.md)

---

## 1. LAYER_WEIGHT 节点概览

### 1.1 全局实例数

整个 `Arknights: Endfield_PBRToonBase` 群组中 **只存在一个** LAYER_WEIGHT 节点，内部名称为 `层权重`。

> **勘误**：`01_shader_arch.md` 中 Frame.008 与 Frame.011 均提到"LAYER_WEIGHT Fresnel 因子"——
> 实际使用的是 **Facing 输出端口**，Fresnel 端口未接线。

### 1.2 两个输出的公式对比

| 输出端口 | 公式 | 本 Shader 是否使用 |
|---------|------|-------------------|
| **Fresnel** | 电介质菲涅耳（`blend` 映射到 IOR） | ❌ 未接线 |
| **Facing** | `(1 - \|dot(N, V)\|)^exp(blend)` | ✅ 实际使用 |

### 1.3 Facing 输出精确公式

Blender 源码（OSL / GLSL 层）：

```glsl
float facing_raw = 1.0 - abs(dot(N, I));   // I = 归一化视角方向

float facing;
if (blend > 0.5)
    facing = pow(facing_raw, 1.0 / (2.0 * (1.0 - blend)));  // 曲线压缩（更陡）
else if (blend > 0.0)
    facing = pow(facing_raw, 2.0 * blend);                    // 曲线拉伸（更平）
else
    facing = 0.0;                                              // blend=0 → 恒为 0
```

**blend 取值与视觉效果对照**：

| `blend` | 指数 exp | 效果描述 |
|---------|----------|---------|
| 0.0 | 0 | 输出恒为 0（无效果） |
| 0.25 | 0.5 | `sqrt(1-NdotV)`，边缘过渡扩展 |
| **0.5** | **1.0** | `1 - NdotV`，线性，最常见基准值 |
| 0.75 | 2.0 | `(1-NdotV)²`，边缘更陡峭 |
| →1.0 | →∞ | 趋近阶跃函数 |

> 当前 `PBRToonBase.hlsl` 中的 `saturate(1.0 - ld.NoV)` 对应 blend=0.5（线性近似）。
> 若美术在 Blender 中调整了 `Layer weight Value`，实际效果将偏离此近似。

---

## 2. LAYER_WEIGHT 完整连线（原始 JSON 确认）

```
Group Input.048 ("Layer weight Value")     ──→  层权重.Blend
Group Input.049 ("Layer weight Value Offset") ─┐
                               层权重.Facing ──┘→  运算.004 (ADD)
                                                         ↓
                                                   钳制.001 (CLAMP [0,1])
                                                         ↓
                                              合并 XYZ.004 (CombineXYZ, X 端口)
                                                   ↙             ↘
                                          图像纹理.005          图像纹理
                                          (ThinFilm LUT A)    (ThinFilm LUT B)
```

### 2.1 合并 XYZ.004 的 UV 语义

| 轴 | 来源 | 含义 |
|----|------|------|
| X | `钳制.001` 输出 | LUT 水平轴 = 视角 Facing 因子 |
| Y | 固定常量（≈ 0.5） | LUT 采样固定行（彩虹色带中线） |
| Z | 未接线 / 0 | 无意义 |

---

## 3. RS Effect 管线详解（帧.048）

`final_color_assembly.md` 中的简述 `混合.029/030 — RS EFF` 的完整节点连线如下：

### 3.1 完整数据流

```
混合.033 (RS 效果 A) ─┐ Factor = RS Model (bool)
混合.038 (RS 效果 B) ─┘→  混合.037 (MIX，RS 模式选择)
                                        ↓ B 端
混合.026 (Emission 之后的累积色) ──→ Reroute.017 ──→ 混合.029 (LIGHTEN)
                                                        Factor = RS Multiply Value
                                                             ↓ Result
               Reroute.018 (同为累积色，绕过 RS) ──→ A ┐
                                    混合.029.Result ──→ B ┤ 混合.030 (MIX)
                                    Use RS_Eff? ──────→ Factor ┘
                                                             ↓
                                                       Reroute.108 → 下游（HSV 节点）
```

### 3.2 混合.037 — RS 模式选择

```
Factor = RS Model (boolean)
A      = 混合.033  ← 非 RS Model 路径的效果色
B      = 混合.038  ← RS Model 路径的效果色
Result = lerp(混合.033, 混合.038, RS_Model)
```

当 `RS_Model = 0`（false）时输出混合.033；`RS_Model = 1`（true）时输出混合.038。

### 3.3 混合.029 — LIGHTEN（变亮混合）

**Blender LIGHTEN 混合模式公式**：

```cpp
// blend_type = LIGHTEN，逐通道取最大值
float3 brightest = max(A, B);                  // 逐通道较亮值
float3 result    = lerp(A, brightest, factor); // factor = RS Multiply Value
// 展开：result = A + factor * max(0, B - A)
```

**关键性质**：

- LIGHTEN 只会增亮，永远不会使结果变暗（因为 `max(A,B) ≥ A` 恒成立）
- RS 特效叠加不破坏阴影/暗部区域，这正是此处选用 LIGHTEN 而非 ADD 的原因
- `factor = 0` → 无效果（输出 A）；`factor = 1` → 完全取较亮值

代入本 Shader 变量：

```cpp
float3 A      = accumulated_color;        // 混合.026 输出（Emission 之后的完整颜色）
float3 B      = rs_effect_color;          // 混合.037 输出（RS 特效颜色，模式由 RS_Model 选择）
float  factor = _RS_MultiplyValue;        // Group Input "RS Multiply Value"

float3 brightest        = max(A, B);
float3 lighten_result   = lerp(A, brightest, factor);
```

### 3.4 混合.030 — RS 总开关（MIX）

```cpp
// Factor = Use RS_Eff? (boolean 0 or 1)
float3 final_color = lerp(
    accumulated_color,   // A = Reroute.018（未经 RS 处理的原始累积色）
    lighten_result,      // B = 混合.029 输出（经 LIGHTEN 处理后）
    _UseRSEff            // 0 = 不启用 RS 效果；1 = 启用
);
```

---

## 4. 等价 HLSL（完整 RS Effect 段落）

```cpp
// ——— 帧.048 RS EFF ———
// 1. RS 模式选择（混合.037）
float3 rsEffectColor = lerp(rs_eff_modeA, rs_eff_modeB, _RS_Model);

// 2. LIGHTEN 混合（混合.029）
//    只增亮，不减暗；factor 控制强度
float3 rsLighten = lerp(color, max(color, rsEffectColor), _RS_MultiplyValue);

// 3. 总开关（混合.030）
color = lerp(color, rsLighten, _UseRSEff > 0.5 ? 1.0 : 0.0);
// ——— RS EFF 结束 ———
```

---

## 5. 与 01_shader_arch.md 的差异说明

| 原文描述 | 修正 |
|---------|------|
| Frame.008/011 均称 `LAYER_WEIGHT Fresnel 因子` | 实际为 **Facing 输出**，Fresnel 端口未接线 |
| Frame.011 描述 `LAYER_WEIGHT → CLAMP → 驱动多个 MIX 节点` | 更准确的下游路径：`CLAMP → 合并 XYZ.004 → 图像纹理`（LUT UV 坐标驱动） |
| 帧.048 RS EFF 描述为 `MIX ×2` | 实际三节点：`混合.037`（RS 模式选择）+ `混合.029`（LIGHTEN）+ `混合.030`（开关） |
