# GetPreIntegratedFGDGGXAndDisneyDiffuse

> 溯源：`docs/raw_data/GetPreIntegratedFGDGGXAndDisneyDiffuse_20260227.json` | 节点数：21

## 接口

| 方向 | 名称 | 类型 |
|------|------|------|
| 输入 | `clampedNdotV` | Float |
| 输入 | `perceptualRoughness` | Float |
| 输入 | `fresnel0` | Color |
| 输出 | `specularFGD` | Color |
| 输出 | `diffuseFGD` | Float |
| 输出 | `reflectivity` | Float |

## 内部节点

| 节点 | 作用 |
|------|------|
| `CombineXYZ` / `SeparateXYZ` ×3 | 组装/拆分 UV 坐标和查找结果 |
| `TEX_IMAGE` | FGD 预积分 LUT 贴图 |
| `MIX` ×3 | 通道混合 |
| `MATH` ×2 | 数学处理 |
| `群组.004 [Remap01ToHalfTexelCoord]` | 将 [0,1] 映射到有效纹素范围（避免边缘采样） |

## 采样逻辑

```
// 构建 LUT UV
U = clampedNdotV          → Remap01ToHalfTexelCoord(U)
V = perceptualRoughness   → Remap01ToHalfTexelCoord(V)
UV = float2(remappedU, remappedV)

// 采样 FGD LUT（RGBA）
sample = tex2D(FGD_LUT, UV)
// sample.x = FGD_a（Schlick 积分第一项）
// sample.y = FGD_b（Schlick 积分第二项）
// sample.z = diffuseFGD（Disney Diffuse FGD）

// 输出计算
specularFGD = fresnel0 * sample.x + sample.y  // = f0×FGDa + FGDb
diffuseFGD  = sample.z
reflectivity = sample.x + sample.y             // 总能量反射率
```

## HLSL 等价

```hlsl
TEXTURE2D(_PreIntegratedFGD);
SAMPLER(sampler_PreIntegratedFGD);

void GetPreIntegratedFGD(
    float clampedNdotV, float perceptualRoughness, float3 fresnel0,
    out float3 specularFGD, out float diffuseFGD, out float reflectivity)
{
    // 避免 LUT 边缘采样的半纹素偏移
    float2 uv = float2(clampedNdotV, perceptualRoughness);
    uv = uv * (1.0 - 1.0 / 512.0) + 0.5 / 512.0; // Remap01ToHalfTexelCoord

    float4 s = SAMPLE_TEXTURE2D(_PreIntegratedFGD, sampler_PreIntegratedFGD, uv);
    specularFGD = fresnel0 * s.x + s.y;
    diffuseFGD = s.z;
    reflectivity = s.x + s.y;
}
```

## 备注

- FGD LUT 是**预计算纹理**，需要从 Blender 内嵌图像导出（或使用标准 HDRP FGD 表替代）
- `Remap01ToHalfTexelCoord` 是第三层子群组，防止在 LUT 边缘因双线性插值采样错误
- 与 HDRP `GetPreIntegratedData(NdotV, perceptualRoughness, fresnel0)` 完全对应
- **Unity 迁移**：可使用 HDRP 的 `PreIntegratedFGD_GGXDisneyDiffuse.asset` 直接复用

## 待确认

- [ ] FGD LUT 贴图分辨率（512×512? 256×256?）
- [ ] LUT 中 Disney Diffuse FGD 存储在哪个通道（推测 Z/Blue）
