# DepthRim

> 溯源：`docs/raw_data/DepthRim_20260227.json` · 21 节点
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `DepthRim()` 函数

---

## 接口

| 📥 输入 | 类型 | 来源 |
|---------|------|------|
| `Rim_width_X` | Float | — |
| `Rim_width_Y` | Float | — |

| 📤 输出 | 类型 | 下游 |
|---------|------|------|
| `DepthRim` | Float | — |

---

## 🔗 内部节点

| 节点 | 类型 | 作用 |
|------|------|------|
| `ScreenspaceInfo` | SCREENSPACEINFO (Goo Engine) | 屏幕空间信息 #1 |
| `ScreenspaceInfo.001` | SCREENSPACEINFO | 屏幕空间信息 #2（偏移采样） |
| `NEW_GEOMETRY.001` | NEW_GEOMETRY | 几何法线 |
| `TEX_COORD` | TEX_COORD | 纹理坐标（屏幕空间 UV） |
| `VectorTransform` | VECT_TRANSFORM | 坐标变换（世界→视图） |
| `SeparateXYZ.002` | SEPXYZ | 分离 XYZ |
| `CombineXYZ.002` | COMBXYZ | 合并 XYZ |
| `MapRange` | MAP_RANGE | 映射范围 |
| `CLAMP` | CLAMP | 截断 |
| `MATH.016~031` | MATH ×8 | 数学运算 |

---

## 📊 逻辑流程

```
1. 获取当前像素屏幕坐标 (ScreenspaceInfo)
2. 根据 Rim_width_X/Y 计算偏移量（法线方向偏移）
3. 用偏移后的 UV 采样深度 (ScreenspaceInfo.001)
4. 深度差 = depth(偏移位置) - depth(当前位置)
5. 若深度差 > 阈值 → 判定为边缘 → DepthRim = 1
6. 经 MapRange 映射 + Clamp 输出 [0,1] 遮罩
```

---

## 💻 HLSL 等价

```cpp
// 需要 Unity _CameraDepthTexture
float DepthRim(float2 screenUV, float3 normalVS, float rimWidthX, float rimWidthY)
{
    // 计算法线偏移 UV
    float2 offset = float2(normalVS.x * rimWidthX, normalVS.y * rimWidthY);
    float2 offsetUV = screenUV + offset;

    // 采样当前深度和偏移深度
    float depthCenter = SampleSceneDepth(screenUV);
    float depthOffset = SampleSceneDepth(offsetUV);

    // 深度差判定
    float depthDiff = depthOffset - depthCenter;
    return saturate(remapRange(depthDiff, threshold_low, threshold_high, 0, 1));
}
```

---

## ❓ 待确认

- [ ] **`ScreenspaceInfo`（Goo Engine 特有节点）**：具体输出字段不明（推测为屏幕 UV + 深度），需查阅 Goo Engine 源码确认
- [ ] 偏移量的具体计算（是否乘以屏幕分辨率缩放系数）
- [ ] MapRange 的 from/to 范围参数值

---

## 📝 备注

这是整个 Shader 中最难移植的部分，因为依赖 Goo Engine 特有的屏幕空间节点。
Unity 中需要：
1. 在 URP 开启 `Depth Texture`
2. 在 HLSL 中手动实现深度采样和对比逻辑
