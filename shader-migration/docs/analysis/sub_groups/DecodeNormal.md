# DecodeNormal

> 溯源：`docs/raw_data/DecodeNormal_20260227.json` · 12 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `DecodeNormal()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `X` | Float | — |
| `Y` | Float | — |
| `NormalStrength` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `NormalWS` | Vector | — |

---

## 🔗 内部节点

```
GROUP_INPUT
    X, Y → CombineXYZ(X,Y,0) → VectorMath.DOT_PRODUCT with itself → Value
    Value → CLAMP → MATH(1-x) → MATH.001(√x) → MATH.002 → MATH.003 → CombineXYZ.001.Z
    X → CombineXYZ.001.X
    Y → CombineXYZ.001.Y
    CombineXYZ.001 → NORMAL_MAP(Strength=NormalStrength) → GROUP_OUTPUT.NormalWS
```

---

## 🧮 等价公式

```
// 从切线空间 XY 重建 Z 分量
float lenSq = X*X + Y*Y;
float Z = sqrt(max(0, 1 - lenSq));
float3 normalTS = normalize(float3(X, Y, Z));
// 应用法线强度并转换到世界空间（Blender Normal Map节点行为）
NormalWS = NormalMap(normalTS, NormalStrength);
```

---

## 💻 HLSL 等价

```cpp
float3 DecodeNormal(float X, float Y, float normalStrength, float3x3 TBN)
{
    float z = sqrt(max(0.0, 1.0 - X * X - Y * Y));
    float3 normalTS = float3(X, Y, z);
    normalTS = lerp(float3(0, 0, 1), normalTS, normalStrength);
    normalTS = normalize(normalTS);
    return normalize(mul(normalTS, TBN)); // 切线空间 → 世界空间
}
```

---

## 📝 备注

- 输入 X/Y 来自 `_N` 贴图的两个通道（Non-Color）
- Blender `NORMAL_MAP` 节点内部包含切线空间到世界空间的变换，Unity 中需通过 TBN 矩阵或 `UnpackNormalScale` 实现
- 坐标轴差异：Blender Y+ up，Unity Y+ up but DX tangent space → 可能需要翻转 Y 通道

---

## ❓ 待确认

- [ ] 待补充
