# GetPreIntegratedFGDGGXAndDisneyDiffuse

> 溯源：`docs/raw_data/GetPreIntegratedFGDGGXAndDisneyDiffuse_20260227.json` | 节点数：21
> HLSL 实现：`hlsl/SubGroups/SubGroups.hlsl` — `GetPreIntegratedFGDGGXAndDisneyDiffuse()` 函数

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
| `合并XYZ` | 组装 UV 向量（X=运算.001结果, Y=perceptualRoughness） |
| `群组.004 [Remap01ToHalfTexelCoord]` | 将 [0,1] 映射到有效纹素范围（避免边缘采样） |
| `分离XYZ` | 拆分 remapped UV，取 XY 送入采样 |
| `合并XYZ.001` | 重组为 2D UV 向量 |
| `图像纹理` | FGD 预积分 LUT 采样（RGBA 输出） |
| `分离XYZ.001` | 拆分 LUT 颜色为 R/G/B 三通道 |
| `分离XYZ.002` | 拆分 fresnel0 为 R/G/B 三分量 |
| `混合` / `混合.001` / `混合.002` | 三通道 lerp(LUT.R, LUT.G, f0.xyz)，等价于 f0·A + B |
| `合并XYZ.002` | 重组 specularFGD 三分量为输出向量 |
| `运算.001` | 对 clampedNdotV 做某种变换（类型待确认，可能 SQRT） |
| `运算` | 对 LUT.B 做变换后输出 diffuseFGD（类型待确认） |
| `转接点` ×3 | 信号路由（无计算） |

## 完整数据流（基于 JSON links 精确追踪，29 条链接）

```
─── UV 构建 ────────────────────────────────────────────────────────
clampedNdotV → [运算.001: 单目数学变换¹] → CombineXYZ.X
perceptualRoughness ─────────────────────→ CombineXYZ.Y

CombineXYZ → [群组.004: Remap01ToHalfTexelCoord] → SeparateXYZ → XY
XY → CombineXYZ.001 → 图像纹理 (FGD LUT)

─── LUT 采样与输出合成 ─────────────────────────────────────────────
图像纹理.Color → SeparateXYZ.001
    .X = LUT.R ─┬─ 混合.A / 混合.001.A / 混合.002.A
    .Y = LUT.G ─┼─ 混合.B / 混合.001.B / 混合.002.B
                └─────────────────────────────────→ 组输出.reflectivity（直接！）
    .Z = LUT.B → [运算²] ─────────────────────────→ 组输出.diffuseFGD

fresnel0 → SeparateXYZ.002
    .X = f0.R → 混合.Factor
    .Y = f0.G → 混合.001.Factor
    .Z = f0.B → 混合.002.Factor

混合 .Result (R) ─┐
混合.001.Result (G) ─┼─ CombineXYZ.002 ──────────────→ 组输出.specularFGD
混合.002.Result (B) ─┘
```

> ¹ `运算.001`：操作类型未知（JSON 中无 operation 字段），可能为 `SQRT(NdotV)` 以改善 LUT 边缘采样精度，或直通。
> ² `运算`：操作类型未知，可能为直通（Multiply×1）或 Clamp。

## LUT 通道布局（关键修正）

本实现 LUT 采用**重打包布局**，与 HDRP 标准不同：

| 通道 | 本 LUT 存储 | HDRP 标准存储 |
|------|------------|--------------|
| R | `B_term`（Schlick 第二积分项，f0=0 贡献） | `A_term`（f0=1 贡献） |
| G | `A_term + B_term`（总反射率） | `B_term`（f0=0 贡献） |
| B | Disney Diffuse FGD | Disney Diffuse FGD |

**数学等价性证明：**
`lerp(LUT.R, LUT.G, f0) = lerp(B, A+B, f0) = B·(1−f0) + (A+B)·f0 = B + A·f0 = f0·A + B` ✓

这是用 Mix lerp 替代 fma 的预计算优化：`reflectivity = LUT.G = A+B` 直接可读，无需 shader 内加法。

## 采样逻辑

```
// 1. 构建 LUT UV（U 可能经过 sqrt 变换）
U = [可能是 sqrt](clampedNdotV)
V = perceptualRoughness
UV = Remap01ToHalfTexelCoord(float2(U, V), texSize=512)

// 2. 采样 FGD LUT
sample = tex2D(FGD_LUT, UV)
// sample.R = B_term（Schlick 第二项，f0=0 积分）
// sample.G = A_term + B_term（总反射率，f0=1 积分）
// sample.B = Disney Diffuse FGD

// 3. 输出（per-channel lerp 等价于 f0·A + B）
specularFGD = lerp(sample.R, sample.G, fresnel0)  // = f0·A + B（等价公式）
diffuseFGD  = sample.B                              // 可能有 运算 变换
reflectivity = sample.G                             // = A + B，直接读取！
```

## HLSL 等价（修正版）

```hlsl
TEXTURE2D(_PreIntegratedFGD);
SAMPLER(sampler_PreIntegratedFGD);

// 注意：本 LUT 的 R/G 通道布局与 HDRP 标准相反
// R = B_term, G = A+B_term（已预加）
void GetPreIntegratedFGD(
    float clampedNdotV, float perceptualRoughness, float3 fresnel0,
    out float3 specularFGD, out float diffuseFGD, out float reflectivity)
{
    // U 坐标可能经过 sqrt 变换（运算.001，具体操作待确认）
    float u = clampedNdotV; // 或 sqrt(clampedNdotV)

    // 避免 LUT 边缘双线性插值误差（半纹素偏移，512px）
    float2 uv = float2(u, perceptualRoughness);
    uv = uv * (1.0 - 1.0 / 512.0) + 0.5 / 512.0;

    float4 s = SAMPLE_TEXTURE2D(_PreIntegratedFGD, sampler_PreIntegratedFGD, uv);
    // s.r = B_term, s.g = A+B, s.b = diffuseFGD

    // lerp(B, A+B, f0) == f0*A + B（数学等价，非标准写法）
    specularFGD = lerp(s.rrr, s.ggg, fresnel0);  // 等价于 fresnel0 * A + B
    diffuseFGD  = s.b;                             // 运算类型待确认
    reflectivity = s.g;                            // A+B 直接读取，无需加法
}

// Unity 迁移注意：HDRP 内置 LUT 通道顺序为 (A, B, diffuse)，
// 若复用官方 asset，需将 specularFGD 改为 fresnel0 * s.r + s.g
```

## 备注

- **reflectivity 直接来自 LUT.G**：原有分析"`reflectivity = sample.x + sample.y`"有误，实际节点直连 `分离XYZ.001.Y → 组输出.reflectivity`，无加法节点
- FGD LUT 是**预计算纹理**，需要从 Blender 内嵌图像导出（或按上表通道约定重新烘焙）
- `Remap01ToHalfTexelCoord` 是第三层子群组，分辨率参数推测 512
- **Unity 迁移**：若用 HDRP `PreIntegratedFGD_GGXDisneyDiffuse.asset`，LUT 通道顺序不同，需改为标准写法 `f0 * s.r + s.g`；reflectivity 需改为 `s.r + s.g`

## 待确认

- [ ] `运算.001` 的具体操作（SQRT / 直通 / 其他），影响 U 坐标精度
- [ ] `运算` 的具体操作（影响 diffuseFGD 输出值）
- [ ] FGD LUT 贴图实际分辨率（推测 512×512）
- [ ] LUT 是否从 HDRP 标准 asset 重新打包，或为自定义烘焙
