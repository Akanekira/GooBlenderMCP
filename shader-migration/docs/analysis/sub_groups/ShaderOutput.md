# ShaderOutput

> 溯源：`docs/raw_data/ShaderOutput_20260227.json` · 5 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `ShaderOutput()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `Alpha` | Float | — |
| `着色结果` | Color | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `着色结果` | Shader | — |

---

## 🔗 内部节点

```
着色结果 ──→ Emission(放射).Color → Emission BSDF
Transparent BSDF ─────────────────┐
Emission BSDF ────────────────────┤ → MIX_SHADER(Fac=Alpha)
Alpha ─────────────────────────── ┘
MIX_SHADER → GROUP_OUTPUT.着色结果
```

---

## 🧮 等价公式

```
// Blender 逻辑：
// Alpha=0 → 完全透明
// Alpha=1 → 完全不透明（Emission 输出着色结果）
output = mix(Transparent, Emission(着色结果), Alpha)
```

在 Blender 中，由于节点图已经手动计算了所有光照，用 `Emission BSDF` 输出最终颜色（关闭额外光照计算），再与透明 BSDF 混合实现 Alpha 透明。

---

## 🎮 Unity URP 迁移要点

```cpp
// Unity 中不需要 Emission/Transparent BSDF
// 直接输出颜色和 Alpha 即可
outColor = float4(shadingResult, alpha);
// 根据材质设置选择：
// - Transparent：Blend SrcAlpha OneMinusSrcAlpha
// - Cutout：clip(alpha - _Cutoff)
```

---

## 📝 备注

- Blender 使用 Emission + Transparent 的原因：节点图已完成所有 PBR 光照计算，不希望 Blender 再叠加额外光照
- 这是 Blender 自定义 Shader 的标准输出模式（区别于 Principled BSDF 的 PBR 输出）
- Unity 侧只需将 `shadingResult` 直接作为 `SV_Target` 输出，配合材质 Alpha 混合设置

---

## ❓ 待确认

- [ ] 待补充
