# F_Schlick

> 溯源：`docs/raw_data/F_Schlick_20260227.json` | 节点数：19
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `F_Schlick()` 函数

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `f0` | Color |
| 输入 | `f90` | Color |
| 输入 | `u` | Float |
| 输出 | `输出` | Color |

## 内部节点

19 个节点（含 REROUTE），核心为 MATH×6 + VECT_MATH×2 的五次方曲线：

```
u ──→ MATH.001(1-u) → MATH.002(×自身) → MATH.004(×MATH.001结果) → MATH.003(×自身) → MATH.005 → poly
f90-f0 ──→ VECT_MATH.001(MULTIPLY × poly)
f0 + result ──→ VECT_MATH → output
```

## 等价公式

Schlick Fresnel 近似：
```
F(f0, f90, u) = f0 + (f90 - f0) × (1 - u)^5
```

其中 `u` 通常为 `LdotH`（半角向量与光向量的点积）。

展开的 `(1-u)^5` 计算链：
```
t  = 1 - u
t2 = t * t        // MATH.002
t4 = t2 * t2      // MATH.003
t5 = t4 * t       // MATH.005 (= t4 × t1)
```

## HLSL 等价

```hlsl
float3 F_Schlick(float3 f0, float3 f90, float u)
{
    float t = 1.0 - u;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (f90 - f0) * t5;
}
```

## 用途

计算高光的 Fresnel 响应。参数来源：
- `f0` = `ComputeFresnel0` 的输出（基础反射率）
- `f90` = 推测为 `(1,1,1)` 或 `float3(1,1,1)`（掠射角下完全反射）
- `u` = `LdotH`（来自 `Get_NoH_LoH_ToH_BoH`）

## 备注

与 HDRP `F_Schlick(f0, f90, u)` 实现完全相同，可直接复用 HDRP 的公式。
