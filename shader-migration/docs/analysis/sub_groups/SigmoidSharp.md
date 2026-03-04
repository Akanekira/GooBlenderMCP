# SigmoidSharp

> 溯源：`docs/raw_data/SigmoidSharp_20260227.json` · 8 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `SigmoidSharp()` 函数
> 修订：2026-03-02，根据重提取数据补正 pow 节点与 ×-3 常量

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `x` | Float | — |
| `center` | Float | — |
| `sharp` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `值(明度)` | Float | — |

---

## 🔗 内部节点

| 节点 | 运算 | 输入（索引顺序） | 输出 |
|------|------|-----------------|------|
| 运算.004 | SUBTRACT | [0] x （linked）, [1] center （linked） | `x - center` |
| 运算.003 | MULTIPLY | [0] sharp （linked）, [1] **-3.0**（const） | `-3 · sharp` |
| 运算.005 | MULTIPLY | [0] (x-center)（from .004）, [1] (-3·sharp)（from .003） | `-3·sharp·(x-center)` |
| 运算.002 | **POWER** | [0] **100000.0**（const, 底数）, [1] t（from .005, 指数） | `100000^t` |
| 运算.006 | ADD | [0] **1.0**（const）, [1] pow_result（from .002） | `1 + 100000^t` |
| 运算.007 | DIVIDE | [0] **1.0**（const）, [1] sum（from .006） | `1 / (1 + 100000^t)` |

---

## 🧮 等价公式

```
t = -3 · sharp · (x - center)
sigmoid_sharp = 1 / (1 + pow(100000, t))
```

**注意**：底数不是自然常数 e（≈2.718），而是 **100000**。
`ln(100000) ≈ 11.51`，等价于一个陡峭系数极高的指数 Sigmoid：

```
sigmoid_sharp = 1 / (1 + exp(-3 · sharp · (x - center) · ln(100000)))
             ≈ 1 / (1 + exp(-34.54 · sharp · (x - center)))
```

`sharp=1` 时，距 center ±0.1 处输出已达 97% / 3%，远比 e-base Sigmoid 更适合 Toon 阶段感边缘。

---

## 💻 HLSL 等价

```cpp
float SigmoidSharp(float x, float center, float sharp)
{
    float t = -3.0 * sharp * (x - center);
    return 1.0 / (1.0 + pow(100000.0, t));
}
```

> `pow(100000, t)` 对正底数始终安全；底数 100000 是节点图内的硬编码常量。

---

## 📌 用途

在主群组中调用两次：
1. halfLambert 阴影边缘过渡（参数：`RemaphalfLambert_center/sharp`）
2. CastShadow 投影阴影过渡（参数：`CastShadow_center/sharp`）

---

## 📌 与标准 Sigmoid 的差异

| 项目 | 标准 Sigmoid（e-base） | SigmoidSharp（100000-base） |
|------|----------------------|-----------------------------|
| 底数 | e ≈ 2.718 | 100000 |
| 等效陡峭倍率 | 1× | ×11.51（per sharp unit） |
| -3 系数 | 无 | 内嵌在 sharp 前（运算.003） |
| Toon 适用性 | 软渐变 | 极锐利边缘，适合卡通分界 |

---

## 📝 备注

初版分析（2026-02-27）遗漏了两处关键信息：
1. 运算.003 的 **常量 -3.0**（旧提取脚本未记录未连线输入的 default_value）
2. 运算.002 的 **POWER 运算模式**（旧提取脚本未记录 `operation` 属性）

根本原因：`extract_nodes.py` 旧版只记录连线拓扑和接口类型，不记录 `node.operation` 和未连线 socket 的 `default_value`。已修复脚本（2026-03-02）。

---

## ❓ 待确认

- [ ] 待补充
