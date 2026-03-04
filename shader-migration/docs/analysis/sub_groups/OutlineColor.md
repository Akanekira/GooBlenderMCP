# OutlineColor

> 溯源：`docs/raw_data/OutlineColor_20260301.json` · 7 节点 | 连线数：8
> HLSL 实现：`hlsl/M_actor_laevat_hair_01/SubGroups/SubGroups.hlsl` — `OutlineColor()` 函数
> 首次出现材质：`M_actor_laevat_hair_01`（PBRToonBaseHair）
> 归属 Frame：Frame.012（Rim & Outline）

---

## 接口

| 📥 输入 | 类型 | 说明 |
|---------|------|------|
| `Fresnel attenuation` | VALUE | 边缘 Fresnel 衰减值（来自 FresnelAttenuation 子群组） |
| `Vertical attenuation` | VALUE | 垂直方向衰减值（来自 VerticalAttenuation 子群组） |

| 📤 输出 | 类型 | 说明 |
|---------|------|------|
| `OutlineColor` | RGBA | 描边颜色遮罩（实际为灰度 float 广播至 RGBA） |

---

## 🔗 内部节点

| 节点名 | 类型 | 操作 | 说明 |
|--------|------|------|------|
| `运算.033` | MATH | SUBTRACT（1.0 - x） | 反转 Fresnel attenuation |
| `颜色渐变.001` | VALTORGB | ColorRamp（Linear） | 映射反转 Fresnel → 边缘遮罩 |
| `运算.032` | MATH | MULTIPLY | crampA × fresnel_attenuation |
| `颜色渐变.002` | VALTORGB | ColorRamp（Linear） | 映射 vertical_attenuation → 垂直遮罩 |
| `运算.034` | MATH | MULTIPLY | 合并两个遮罩 → 最终 OutlineColor |
| `组输入` | GROUP_INPUT | — | 接收外部输入 |
| `组输出` | GROUP_OUTPUT | — | 输出 OutlineColor |

### ColorRamp 色带定义

| ColorRamp | 控制点 pos | 控制点颜色 | 用途 |
|-----------|-----------|-----------|------|
| 颜色渐变.001 | 0.000 | 白 (1,1,1,1) | Fresnel 反转遮罩 |
| 颜色渐变.001 | 0.495 | 黑 (0,0,0,1) | 过渡截止点 |
| 颜色渐变.002 | 0.000 | 白 (1,1,1,1) | 垂直遮罩 |
| 颜色渐变.002 | 0.295 | 黑 (0,0,0,1) | 垂直截止点（比 rim 更激进） |

---

## 📊 计算流程

```
输入: fresnel_atten, vertical_atten

[运算.033] sub = 1.0 - fresnel_atten
                ↓
[颜色渐变.001] crampA = ColorRamp(sub)          // 0→white, 0.495→black
                ↓
[运算.032] mid = crampA * fresnel_atten         // 边缘亮度 × 边缘强度

[颜色渐变.002] crampB = ColorRamp(vertical_atten)  // 0→white, 0.295→black
                ↓
[运算.034] OutlineColor = mid * crampB          // 最终遮罩
```

---

## 🧮 等价公式

```
// 线性 ColorRamp（两停：stop0=1, stop1=0 at threshold）
crampA = saturate(1.0 - sub / 0.495)
       = saturate((fresnel_atten - 1.0) / 0.495 + 1.0)

crampB = saturate(1.0 - vertical_atten / 0.295)

OutlineColor = (crampA × fresnel_atten) × crampB
```

**语义**：
- `crampA × fresnel_atten`：边缘遮罩，在 Fresnel 强（视角掠射）且 crampA 为白时最大
- `crampB`：垂直遮罩，在角色下方（vertical_atten≈0）最大，在上方（>0.295）截断为零
- 最终：**仅在掠射角 + 角色下方区域出现描边颜色**

---

## 💻 HLSL 等价

```cpp
// --- OutlineColor ---
// 溯源：docs/analysis/sub_groups/OutlineColor.md
// 功能：基于 Fresnel 衰减和垂直方向衰减生成描边颜色遮罩
// 首次用于：PBRToonBaseHair（M_actor_laevat_hair_01）

float3 OutlineColor(float fresnel_attenuation, float vertical_attenuation)
{
    // ColorRamp(1 - fresnel_atten): white@0 -> black@0.495
    float sub = 1.0 - fresnel_attenuation;
    float crampA = saturate(1.0 - sub / 0.495);

    // mid = crampA × fresnel
    float mid = crampA * fresnel_attenuation;

    // ColorRamp(vertical_atten): white@0 -> black@0.295
    float crampB = saturate(1.0 - vertical_attenuation / 0.295);

    // Final outline mask (grayscale → broadcast to RGB)
    float mask = mid * crampB;
    return float3(mask, mask, mask);
}
```

---

## 📝 备注

- **无对应 URP/HDRP 标准函数**：此子群组是 GooEngine Arknights: Endfield 专属描边逻辑
- 输出为**灰度遮罩**（RGBA 中 R=G=B=mask），配合 Rim_Color 等实际颜色参数在上层合成
- 两个 ColorRamp 的截止点（0.495 / 0.295）均来自 Blender 中设置的默认值，实际项目中可能通过参数调整
- 该子群组 **不直接生成颜色**，只生成控制描边可见区域的浮点遮罩
- 与标准 outline 方案（反法线描边、外扩顶点）不同，本方案为屏幕空间 Rim 近似，不依赖几何扩展

---

## ❓ 待确认

- [ ] 上层如何将 OutlineColor 遮罩与实际描边颜色（`_OutlineColor` 参数）组合
- [ ] 两个 ColorRamp 的插值方式是否真的为 LINEAR（还是 EASE/CONSTANT）
