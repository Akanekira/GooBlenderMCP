# DV_SmithJointGGX_Aniso — 第三层子群组完整分析

> 溯源：通过 MCP 实时提取（2026-03-04）
> 上层文档：`docs/analysis/sub_groups/DV_SmithJointGGX_Aniso.md`
> 提取方式：`execute_blender_code` + 带 input-index 的精确 link 追踪（规避 socket 同名覆盖问题）

---

## 📌 外层调用拓扑（DV_SmithJointGGX_Aniso，22节点）

节点帧标签：`a2` | `partLambdaV` | `lambdaV` | `AnisoPartLambdaV`

### 各向同性路径（→ original 输出）

```
组输入.clampedRoughness ──→ 运算[in0] (MULTIPLY)
组输入.clampedRoughness ──→ 运算[in1]
                             运算.output → 转接点(a2帧) = a2 = roughness²

组输入.clampedNdotV ──→ 群组[in0].clampedNdotV  ─┐
转接点(a2) ───────────→ 群组[in1].a2              ├─ GetSmithJointGGet...PartLambdaV
                         群组.output[0] = partLambdaV

转接点.002(partLambdaV) ──→ 运算.005[in0] (MULTIPLY)
组输入.Abs_NdotL ─────────→ 运算.005[in1]
                             运算.005.output = partLambdaV × NdotL    ← 无 sqrt！
                             → 转接点.007 → 群组.001[in0].lambdaV

组输入.NdotH        → 群组.001[in1].NdotH
组输入.Abs_NdotL    → 群组.001[in2].Abs_NdotL
组输入.clampedNdotV → 群组.001[in3].clampedNdotV
转接点(a2)          → 群组.001[in4].a2
                      群组.001.output[0] → 组输出[in0].original
```

**关键差异**：外层将 `partLambdaV`（sqrt 内部量）**直接 × NdotL** 传给 `DV_SmithJointGGX.IN`，
而不是 `NdotL × sqrt(partLambdaV)`（标准 HDRP 实现）。详见子群组 C 分析。

### 各向异性路径（→ anisotropy 输出）

```
组输入.TdotV     → 群组.002[in0].TdotV       ─┐
组输入.BdotV     → 群组.002[in1].BdotV        │
组输入.roughnessT→ 群组.002[in2].roughnessT   ├─ GetSmithJointGGXAnisoPartLambdaV
组输入.roughnessB→ 群组.002[in3].roughnessB   │
组输入.clampedNdotV→群组.002[in4].clampedNdotV│
                   群组.002.output[0] = AnisoPartLambdaV → 转接点.012

组输入.NdotH     → 群组.003[in0].NdotH        ─┐
组输入.roughnessT→ 群组.003[in1].roughnessT    │
组输入.roughnessB→ 群组.003[in2].roughnessB    │
组输入.TdotH     → 群组.003[in3].TdotH         │
组输入.BdotH     → 群组.003[in4].BdotH         ├─ DV_SmithJointGGXAniso
转接点.012       → 群组.003[in5].AnisoPartLambdaV│
组输入.Abs_NdotL → 群组.003[in6].NdotL         │
组输入.clampedNdotV→群组.003[in7].NdotV        │
组输入.TdotL     → 群组.003[in8].TdotL         │
组输入.BdotL     → 群组.003[in9].BdotL         │
                   群组.003.output[0] → 组输出[in1].anisotropy

转接点.012 → 组输出[in2].DeBug   ← DeBug = AnisoPartLambdaV（调试用）
```

---

## 📌 子群组 A：GetSmithJointGGetSmithJointGGXPartLambdaV

> **Blender 实际名称有重复前缀 bug**（应为 `GetSmithJointGGXPartLambdaV`）
> 节点数：9 | 帧：`a2`

### 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `clampedNdotV` | Float | — |
| `a2` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `partLambdaV` | Float | — |

### 节点追踪

```
转接点(a2帧) ← 组输入.a2               = a2 路由点

运算.001 (MULTIPLY):  NdotV × (-1.0)   = -NdotV
运算.002 (MULTIPLY):  -NdotV × a2      = -NdotV·a2
运算.003 (ADD):       -NdotV·a2 + NdotV = NdotV·(1-a2)
运算.004 (MULTIPLY):  NdotV·(1-a2) × NdotV = NdotV²·(1-a2)
运算.005 (ADD):       NdotV²·(1-a2) + a2   = partLambdaV
```

### 公式

```
partLambdaV = (-NdotV·a2 + NdotV)·NdotV + a2
            = (1-a2)·NdotV² + a2
```

> ⚠️ **注意**：输出为 sqrt **内部量**，不含 sqrt，不含 NdotL。
> 与 HDRP `GetSmithJointGGXPartLambdaV` 的关系：
>   - HDRP 版本：`return sqrt((-NdotV·a2 + NdotV)·NdotV + a2)`（含 sqrt）
>   - Blender 版本：只返回 sqrt 内部量，外层不做 sqrt（直接 × NdotL）

---

## 📌 子群组 B：GetSmithJointGGXAnisoPartLambdaV

> 节点数：6

### 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `TdotV` | Float | — |
| `BdotV` | Float | — |
| `roughnessT` | Float | — |
| `roughnessB` | Float | — |
| `clampedNdotV` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `AnisoPartLambdaV` | Float | — |

### 节点追踪

```
运算.006 (MULTIPLY): TdotV × roughnessT      = roughT·TdotV
运算.007 (MULTIPLY): BdotV × roughnessB      = roughB·BdotV
合并XYZ.001:         X=roughT·TdotV, Y=roughB·BdotV, Z=clampedNdotV
矢量运算.001 (LENGTH): ‖合并XYZ.001‖         = AnisoPartLambdaV
```

### 公式

```
AnisoPartLambdaV = sqrt((roughT·TdotV)² + (roughB·BdotV)² + NdotV²)
```

> ⚠️ **与子群组 A 的关键差异**：
> - 子群组 A（各向同性）：输出 **不含 sqrt**（外层不做 sqrt）
> - 子群组 B（各向异性）：输出 **已含 sqrt**（LENGTH 节点）
> - 外层各向异性路径：直接 `AnisoPartLambdaV × NdotL`（已是 ΛV）
> - 外层各向同性路径：`partLambdaV × NdotL`（**非** ΛV，而是 ΛV²×NdotL）

---

## 📌 子群组 C：DV_SmithJointGGX.IN（各向同性 D×V）

> 节点数：35 | 帧标签：`s` | `lambdaV` | `lambdaL` | `D` | `G`

### 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `lambdaV` | Float | 外层传入的 `partLambdaV × NdotL`（非 `NdotL × sqrt(partLambdaV)`） |
| `NdotH` | Float | — |
| `Abs_NdotL` | Float | — |
| `clampedNdotV` | Float | — |
| `a2` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `输出` | Float | D×V 结果 |

### Frame "s" — GGX NDF 分母

```
运算     (MULTIPLY): NdotH × a2           = NdotH·a2
运算.001 (SUBTRACT): NdotH·a2 - NdotH     = NdotH·(a2-1)
运算.002 (MULTIPLY): NdotH·(a2-1) × NdotH = NdotH²·(a2-1)
运算.003 (ADD +1.0): NdotH²·(a2-1) + 1.0  = s

s = 1 - NdotH²·(1-a2)    [各向同性 GGX 的关键分母项]
转接点(s帧) = s
```

### Frame "lambdaV" — Passthrough

```
转接点.001 ← 组输入.lambdaV
           = partLambdaV × NdotL  [直接路由，不做处理]
```

### Frame "lambdaL" — 计算 NdotV×ΛL

```
运算.005 (MULTIPLY × -1): NdotL × (-1.0)    = -NdotL
运算.006 (MULTIPLY):      -NdotL × a2       = -NdotL·a2
运算.007 (ADD):           -NdotL·a2 + NdotL = NdotL·(1-a2)
运算.008 (MULTIPLY):      NdotL·(1-a2) × NdotL = NdotL²·(1-a2)
运算.009 (ADD):           NdotL²·(1-a2) + a2   ← sqrt 内部量
运算.010 (SQRT):          sqrt(NdotL²·(1-a2)+a2) = ΛL    ← 这里有 sqrt
运算.019 (MULTIPLY):      ΛL × clampedNdotV = NdotV·ΛL
转接点.002(lambdaL帧)    = NdotV·ΛL
```

> ⚠️ **重要**：lambdaL 路径**有 sqrt**（运算.010），但 lambdaV 路径（传入的）**无 sqrt**。
> 这导致 Smith Joint GGX 分母是非对称近似：
> ```
> G_denom = NdotL × [(1-a2)·NdotV²+a2]   +   NdotV × sqrt[(1-a2)·NdotL²+a2]
>           ↑ 无 sqrt（近似项）                ↑ 有 sqrt（精确项）
> ```
> 对比标准 HDRP：`NdotL×sqrt(…) + NdotV×sqrt(…)`

### Frame "D" + Frame "G" — 向量打包技巧

Blender 把 D 和 G 各自的分子/分母打包进向量，一次性完成 D×G 计算：

```
// D 分量（帧.003=D）
a2 → 合并XYZ.X                       D 分子 = a2
运算.011 (MULTIPLY): s × s = s²
s² → 合并XYZ.Y                       D 分母 = s²

合并XYZ = (a2, s², 0)
转接点.003(D帧)

// G 分量（帧.004=G）
运算.012 (ADD): lambdaV_input + NdotV·ΛL = G_denom
G_denom → 合并XYZ.001.Y              G 分母 = G_denom
1.0(常数) → 合并XYZ.001.X            G 分子 = 1

合并XYZ.001 = (1.0, G_denom, 0)
转接点.004(G帧)
```

```
// 拆包并交叉相乘
分离XYZ   (D帧): X=a2,    Y=s²
分离XYZ.001(G帧): X=1.0,  Y=G_denom

运算.014 (MULTIPLY): a2 × 1.0            = 总分子
运算.016 (MULTIPLY): s² × G_denom        = 总分母
运算.017 (MAXIMUM, FLT_MIN=1.175e-38):   max(总分母, FLT_MIN)
运算.018 (DIVIDE):   总分子 / max(总分母) = a2 / (s²×G_denom)
运算.013 (纯常数):   0.3183099 × 0.5    = 1/(2π)
运算.015 (MULTIPLY): 1/(2π) × ratio      = 最终输出
```

### 最终公式

```
G_denom = NdotL × partLambdaV + NdotV × sqrt((1-a2)·NdotL²+a2)

DV_ISO = a2 / (2π · s² · max(G_denom, FLT_MIN))

其中：
  s           = (a2-1)·NdotH² + 1
  partLambdaV = (1-a2)·NdotV² + a2    [外层传入，无 sqrt]
  FLT_MIN     ≈ 1.175e-38
  1/(2π)      = 0.31830987 × 0.5（硬编码常数节点）
```

---

## 📌 子群组 D：DV_SmithJointGGXAniso（各向异性 D×V）

> 节点数：44 | 帧标签：`a2_Aniso` | `AnisoPartLambdaV` | `lambdaV` | `V` | `s` | `lambdaL` | `D` | `G`
> **注意**：简单 link 提取会丢失 3 条链接（同名 socket 导致覆盖），需带 input-index 提取

### 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `NdotH` | Float | — |
| `roughnessT` | Float | — |
| `roughnessB` | Float | — |
| `TdotH` | Float | — |
| `BdotH` | Float | — |
| `AnisoPartLambdaV` | Float | 已含 sqrt，来自子群组 B |
| `NdotL` | Float | — |
| `NdotV` | Float | — |
| `TdotL` | Float | — |
| `BdotL` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `Value` | Float | — |

### Frame "a2_Aniso" — 公因子预算

```
运算.001 (MULTIPLY): roughnessT × roughnessB = a2_Aniso = roughT·roughB
转接点.001 → 广播给后续 4 处使用（运算.004, 运算.009[x2], 运算.010）
```

### Frame "V" + Frame "s" — DOT_PRODUCT 计算 s_dot

```
运算.002 (MULTIPLY): TdotH × roughB         = TdotH·roughB
运算.003 (MULTIPLY): BdotH × roughT         = BdotH·roughT
运算.004 (MULTIPLY): a2_Aniso × NdotH       = roughT·roughB·NdotH

合并XYZ: X=TdotH·roughB,  Y=BdotH·roughT,  Z=roughT·roughB·NdotH
转接点.005(V帧)

矢量运算 (DOT_PRODUCT): dot(v, v) = ‖v‖²
= (TdotH·roughB)² + (BdotH·roughT)² + (roughT·roughB·NdotH)²
转接点.006(s帧) = s_dot
```

**数学展开**（理解 DOT_PRODUCT 的意义）：

```
s_dot = roughB²·TdotH² + roughT²·BdotH² + roughT²·roughB²·NdotH²
      = (roughT·roughB)² × [ TdotH²/roughT² + BdotH²/roughB² + NdotH² ]
      = (roughT·roughB)² × s_aniso

其中 s_aniso = TdotH²/roughT² + BdotH²/roughB² + NdotH²
```

通过 DOT_PRODUCT 一次性得到了 `(roughT·roughB)² × s_aniso`，避免手动展开加法。

### Frame "AnisoPartLambdaV" + Frame "lambdaV"

```
转接点(AnisoPartLambdaV帧) ← 组输入.AnisoPartLambdaV   passthrough

运算.005 (MULTIPLY):
  [in0] = AnisoPartLambdaV = sqrt((roughT·TdotV)²+(roughB·BdotV)²+NdotV²)
  [in1] = NdotL
  output = AnisoPartLambdaV × NdotL = lambdaV_aniso

转接点.002(lambdaV帧) = lambdaV_aniso
```

### Frame "lambdaL" — 各向异性 ΛL

```
运算.006 (MULTIPLY): TdotL × roughT     = roughT·TdotL
运算.007 (MULTIPLY): BdotL × roughB     = roughB·BdotL

合并XYZ.001: X=roughT·TdotL,  Y=roughB·BdotL,  Z=NdotL

矢量运算.001 (LENGTH): ‖合并XYZ.001‖
= sqrt((roughT·TdotL)² + (roughB·BdotL)² + NdotL²)   = ΛL_aniso

运算.008 (MULTIPLY): ΛL_aniso × NdotV  = NdotV·ΛL_aniso
转接点.003(lambdaL帧) = NdotV·ΛL_aniso
```

> lambdaV 与 lambdaL 的结构完全对称：
> - lambdaV = length(roughT·TdotV, roughB·BdotV, NdotV) × NdotL
> - lambdaL = length(roughT·TdotL, roughB·BdotL, NdotL) × NdotV

### Frame "D" — 向量打包（含隐藏链接）

> ⚠️ 简单提取时遗漏 2 条 link，需用 input-index 提取才能还原：

```
// 连乘 a2_Aniso 三次（经带索引确认）
运算.009 (MULTIPLY):
  [in0] = 转接点.001 = a2_Aniso      ← 同一来源连两个槽
  [in1] = 转接点.001 = a2_Aniso
  output = a2_Aniso² = (roughT·roughB)²

运算.010 (MULTIPLY):
  [in0] = 运算.009   = a2_Aniso²
  [in1] = 转接点.001 = a2_Aniso      ← 简单提取时丢失的 link！
  output = a2_Aniso³ = (roughT·roughB)³

运算.011 (MULTIPLY):
  [in0] = 转接点.006 = s_dot         ← 同一来源连两个槽
  [in1] = 转接点.006 = s_dot
  output = s_dot²

合并XYZ.002:
  X = 运算.010 = (roughT·roughB)³     ← 简单提取时 X 看起来是 0（丢失 link）
  Y = 运算.011 = s_dot²
转接点.004(D帧)
```

### Frame "G" + 最终 D×G

```
运算.012 (ADD): lambdaV_aniso + NdotV·ΛL_aniso = G_denom

合并XYZ.003:
  X = 1.0 (constant)                G 分子
  Y = G_denom                       G 分母

// 拆包并交叉相乘
分离XYZ   (G帧, from 合并XYZ.003): X=1.0,                Y=G_denom
分离XYZ.001(D帧, from 合并XYZ.002): X=(roughT·roughB)³,  Y=s_dot²

运算.013 (MULTIPLY): (roughT·roughB)³ × 1.0     = 总分子
运算.014 (MULTIPLY): s_dot² × G_denom            = 总分母
运算.015 (MAXIMUM, eps=0.001): max(总分母, 0.001) ← 比各向同性大 38 个数量级
运算.016 (DIVIDE):  总分子 / max(总分母, 0.001)
运算.017 (纯常数):  0.31830987 × 0.5 = 1/(2π)
运算.018 (MULTIPLY): ratio × 1/(2π)  = 最终输出
```

### 最终公式

```
G_denom = AnisoPartLambdaV · NdotL  +  NdotV · length(roughT·TdotL, roughB·BdotL, NdotL)

DV_ANISO = (roughT·roughB)³ / (2π · s_dot² · max(G_denom, 0.001))

展开 s_dot = (roughT·roughB)² · s_aniso：

DV_ANISO = (roughT·roughB)³ / (2π · (roughT·roughB)⁴ · s_aniso² · max(...))
         = 1 / (2π · roughT·roughB · s_aniso² · max(G_denom, 0.001))

对应数学分拆：
  D_GGXAniso  = 1 / (π · roughT·roughB · s_aniso²)
  Vis_aniso   = 0.5 / max(G_denom, 0.001)
  D × Vis     = D_GGXAniso × Vis_aniso  ✓
```

---

## 📌 两路对比汇总

| 项目 | 各向同性（C） | 各向异性（D） |
|------|------|------|
| **D 分子** | `a2 = roughness²` | `(roughT·roughB)³`（连乘3次） |
| **D 分母** | `s²`（展开加法） | `s_dot²`（DOT_PRODUCT trick） |
| **ΛV 计算** | `partLambdaV × NdotL`（**无 sqrt**） | `AnisoPartLambdaV × NdotL`（**有 sqrt**） |
| **ΛL 计算** | `NdotV × sqrt(…)`（有 sqrt） | `NdotV × length(…)`（有 sqrt） |
| **防零除 eps** | FLT_MIN ≈ 1.175e-38 | **0.001**（相差 38 个数量级） |
| **1/π 常数** | 0.31830**99**（略低精度） | 0.31830**98**7（略高精度） |
| **内部帧数** | 5 帧 | 8 帧 |
| **节点数** | 35 | 44 |
| **link 提取陷阱** | 无 | 3 条因同名 socket 丢失 |

---

## 💻 HLSL 实现（基于节点精确追踪）

```cpp
// ── 子群组 A ──────────────────────────────────────────────────────────────
// 注：返回 sqrt 内部量（不含 sqrt），外层直接 × NdotL 使用
float GetSmithJointGGXPartLambdaV(float NdotV, float a2)
{
    return (-NdotV * a2 + NdotV) * NdotV + a2;
    // = (1-a2)·NdotV² + a2
    // ≠ HDRP 版（HDRP 含 sqrt）
}

// ── 子群组 B ──────────────────────────────────────────────────────────────
float GetSmithJointGGXAnisoPartLambdaV(
    float TdotV, float BdotV, float NdotV,
    float roughT, float roughB)
{
    // LENGTH 节点 = sqrt，输出已含 sqrt
    return length(float3(roughT * TdotV, roughB * BdotV, NdotV));
}

// ── 子群组 C ──────────────────────────────────────────────────────────────
// lambdaV_in = partLambdaV × NdotL（非 NdotL×sqrt(partLambdaV)）
float DV_SmithJointGGX_ISO(
    float NdotH, float Abs_NdotL, float NdotV,
    float lambdaV_in, float a2)
{
    // Frame s
    float s = (a2 - 1.0) * NdotH * NdotH + 1.0;

    // Frame lambdaL（有 sqrt，与 lambdaV_in 不对称）
    float lambdaL = NdotV * sqrt((-Abs_NdotL * a2 + Abs_NdotL) * Abs_NdotL + a2);

    // Frame D×G（向量打包展开后的等价写法）
    float numerator   = a2;
    float denominator = s * s * (lambdaV_in + lambdaL);
    return numerator / (2.0 * UNITY_PI * max(denominator, REAL_MIN));
    // REAL_MIN ≈ FLT_MIN = 1.175e-38
}

// ── 子群组 D ──────────────────────────────────────────────────────────────
float DV_SmithJointGGXAniso(
    float NdotH,  float NdotL,   float NdotV,
    float TdotH,  float BdotH,
    float TdotL,  float BdotL,
    float roughT, float roughB,
    float AnisoPartLambdaV)  // 已含 sqrt，来自子群组 B
{
    // Frame a2_Aniso
    float a2_Aniso = roughT * roughB;

    // Frame V + s（DOT_PRODUCT trick 展开）
    float3 v = float3(TdotH * roughB, BdotH * roughT, a2_Aniso * NdotH);
    float s_dot = dot(v, v);  // = (roughT·roughB)² × s_aniso

    // Frame lambdaV
    float lambdaV = AnisoPartLambdaV * NdotL;

    // Frame lambdaL
    float lambdaL = NdotV * length(float3(roughT * TdotL, roughB * BdotL, NdotL));

    // Frame D×G（向量打包展开）
    float a2_3 = a2_Aniso * a2_Aniso * a2_Aniso;  // (roughT·roughB)³
    float numerator   = a2_3;
    float denominator = s_dot * s_dot * (lambdaV + lambdaL);
    return numerator / (2.0 * UNITY_PI * max(denominator, 1e-3));
    // eps = 0.001（比各向同性大 38 个数量级）
}

// ── 顶层封装 ──────────────────────────────────────────────────────────────
void DV_SmithJointGGX_Aniso_Full(
    float NdotH,   float Abs_NdotL,  float clampedNdotV,
    float clampedRoughness,
    float TdotH,   float BdotH,
    float TdotL,   float BdotL,
    float TdotV,   float BdotV,
    float roughnessT, float roughnessB,
    out float original,    // 各向同性输出
    out float anisotropy)  // 各向异性输出
{
    float a2 = clampedRoughness * clampedRoughness;

    // 各向同性路径（partLambdaV 无 sqrt，直接 × NdotL）
    float partLambdaV  = GetSmithJointGGXPartLambdaV(clampedNdotV, a2);
    float lambdaV_iso  = partLambdaV * Abs_NdotL;
    original = DV_SmithJointGGX_ISO(NdotH, Abs_NdotL, clampedNdotV, lambdaV_iso, a2);

    // 各向异性路径（AnisoPartLambdaV 含 sqrt）
    float anisoPartLambdaV = GetSmithJointGGXAnisoPartLambdaV(
        TdotV, BdotV, clampedNdotV, roughnessT, roughnessB);
    anisotropy = DV_SmithJointGGXAniso(
        NdotH, Abs_NdotL, clampedNdotV,
        TdotH, BdotH, TdotL, BdotL,
        roughnessT, roughnessB, anisoPartLambdaV);
}
```

---

## ❓ 遗留问题

- [ ] 各向同性路径 `partLambdaV × NdotL`（无 sqrt）是引擎故意的近似优化，还是节点 bug？
  待与 Goo Engine 源码或 HDRP 官方近似版本对照确认。
- ✅ ~~DeBug 输出含义：= `AnisoPartLambdaV`（各向异性 ΛV 原始值），调试用。~~
- ✅ ~~第三层子群组全部分析完成（2026-03-04）~~
