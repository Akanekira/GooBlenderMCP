# IBL 理论与实现参考

> 溯源：基于 `GetPreIntegratedFGDGGXAndDisneyDiffuse` 子群组深度分析整理
> 适用材质：`PBRToonBase` 系列（Arknights: Endfield 风格）
> 相关文件：`sub_groups/GetPreIntegratedFGDGGXAndDisneyDiffuse.md`、`01_shader_arch.md § Frame.011`

---

## 1. 问题的起点：渲染方程

IBL 要解决的是**来自整个环境的间接光照**如何用于实时渲染：

```
Lo(ωo) = ∫_Ω  fr(ωi, ωo) · Li(ωi) · (n·ωi)  dωi
```

| 符号 | 含义 |
|------|------|
| `Lo(ωo)` | 向观察方向 `ωo` 出射的辐亮度 |
| `Li(ωi)` | 来自方向 `ωi` 的入射辐亮度（由环境贴图提供） |
| `fr(ωi, ωo)` | BRDF（材质对该入射/出射对的响应） |
| `n·ωi` | Lambert 余弦项 cosθ |

**实时的困难**：`Li` 来自全方向环境贴图，积分域是整个上半球，没有解析解，暴力蒙特卡洛不可用。

---

## 2. Split Sum 近似（Epic Games, SIGGRAPH 2013）

将镜面积分拆成两个可独立预计算的部分之积：

```
∫ fr · Li · cosθ dωi  ≈  [∫ Li · D dωi]  ×  [∫ fr · cosθ dωi]
                          ────────────────    ────────────────────
                           第一项               第二项
                         预过滤环境贴图          FGD 积分 LUT
                         (按 roughness 模糊)    (按 NdotV, roughness 查表)
```

> **注意**：这是一个近似，成立条件为环境光 `Li` 与 BRDF 的频域大致解耦。在大多数材质下误差可接受。

---

## 3. 第一项：预过滤环境贴图（Prefiltered Envmap）

**原理**：光滑材质只需采样反射方向附近一点；粗糙材质需要对整个半球平均。离线将环境 Cubemap 按不同粗糙度预积分存入多个 Mip 级别。

```
Mip 0  → roughness = 0.0  → 锐利镜面反射
Mip 1  → roughness = 0.2
...
Mip N  → roughness = 1.0  → 完全漫射模糊
```

实时采样：

```hlsl
float3 R = reflect(-V, N);                          // 镜面反射方向
float  mip = roughness * MAX_REFLECTION_LOD;
float3 envColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, sampler, R, mip);
```

---

## 4. 第二项：FGD 积分 LUT

### 4.1 数学推导

对 GGX + Schlick Fresnel 展开：

```
F(cosθ) = f0 + (1 - f0)·(1 - cosθ)⁵

FGD(NdotV, r, f0) = ∫ F·G·D·cosθ dωi
                  = f0 · ∫[(1-(1-cosθ)⁵)·G·D·cosθ dωi]  +  ∫[(1-cosθ)⁵·G·D·cosθ dωi]
                         ──────────────────────────────        ──────────────────────────
                                   A_term                             B_term
```

**关键**：A 和 B 只依赖 `(NdotV, roughness)`，与材质的具体 f0 无关。
因此离线积分，存入 2D LUT，实时查表：

```
specularFGD = f0 · A_term + B_term
```

### 4.2 LUT 坐标轴

| 轴 | 变量 | 物理含义 |
|----|------|---------|
| U（X轴）| `NdotV`（可能经过 `sqrt` 重映射） | 视线与法线夹角，决定掠射效果 |
| V（Y轴）| `perceptualRoughness` | 粗糙度，决定高光形状 |

**为什么 `U = sqrt(NdotV)` ？**

NdotV 在掠射角（→0）附近 FGD 变化极剧烈，用 sqrt 做非线性重映射：

```
NdotV:  0.00  0.01  0.04  0.09  0.16  0.25  1.0
sqrt→U: 0.00  0.10  0.20  0.30  0.40  0.50  1.0
        ←── 低角度区被拉伸，精度提升 ───────────→
```

### 4.3 本项目 LUT 的通道布局（非标准重打包）

> 通过对 `GetPreIntegratedFGDGGXAndDisneyDiffuse_20260227.json` 的 29 条 links 精确追踪确认。

| 通道 | 本 LUT 存储值 | HDRP 标准存储值 |
|------|-------------|----------------|
| **R** | `B_term`（f0=0 积分） | `A_term`（f0=1 积分） |
| **G** | `A_term + B_term`（总反射率） | `B_term`（f0=0 积分） |
| **B** | Disney Diffuse FGD | Disney Diffuse FGD |

**重打包的数学等价性**（Blender Mix 节点实际使用 lerp 而非 fma）：

```
lerp(LUT.R, LUT.G, f0)
= lerp(B, A+B, f0)
= B·(1-f0) + (A+B)·f0
= B + A·f0
= f0·A + B  ✓
```

**附带优化**：`reflectivity = LUT.G = A+B` 可直接读出，无需 shader 内再做加法。

### 4.4 半纹素偏移（Remap01ToHalfTexelCoord）

避免双线性插值时采样到纹理边界外：

```hlsl
float2 RemapToHalfTexel(float2 uv, float texSize)
{
    return uv * ((texSize - 1.0) / texSize) + (0.5 / texSize);
    // 等价于 uv * (1 - 1/N) + 0.5/N，推测 texSize = 512
}
```

---

## 5. 漫射 IBL：两种实现方案

漫射 BRDF 近似均匀半球分布，`Li` 加权积分即可预计算。

### 5.1 球谐函数（SH，Spherical Harmonics）

```hlsl
float3 L_diffuse = SampleSH(N);  // Unity 内置，9个L0~L2阶系数
```

优点：极省带宽，完整方向响应（上下左右均正确）。
Unity 的 `unity_SHAr/SHAg/SHAb/SHBr...` 即此。

### 5.2 半球双色近似（本项目用法）

```hlsl
float  hemisphereT     = normalWS.y * 0.5 + 0.5;
float3 ambientSphereColor = lerp(unity_AmbientGround.rgb, unity_AmbientSky.rgb, hemisphereT);
```

优点：更快，可在 Inspector 直接调色。
缺点：只区分上下，侧向法线的环境色不够准确。

### 5.3 Goo Engine 原始实现

```
AmbientLightColorTint × SHADERINFO.AmbientLighting
```

`SHADERINFO` 是 Goo Engine 专有节点，Unity 迁移时替换为方案 A 或 B。

---

## 6. Disney Diffuse FGD 修正（LUT.B）

**问题**：Lambert 漫射假设光线折射进入材质后 100% 散射出去，但实际上折射本身也受 Fresnel 影响。

Disney Diffuse 对此进行修正，修正系数同样只依赖 `(NdotV, roughness)`，因此打包进 FGD LUT 的 B 通道，一次采样取三路数据：

```
diffuseFGD = LUT.B
indirectDiffuse = albedo · (1 - metallic) · diffuseFGD · ambientColor
```

---

## 7. 多重散射能量守恒（Multi-Scatter / Kulla-Conty）

### 7.1 问题

单次散射 GGX 在粗糙表面会**漏掉能量**：光线在微表面多次弹射后某些路径被丢弃，导致高粗糙度材质偏暗。

### 7.2 本项目使用的简化修正

```
reflectivity = LUT.G = A_term + B_term     // 单次散射总反射率
ecFactor     = 1 / reflectivity - 1        // 能量补偿系数
```

物理含义：`ecFactor` 代表"应该存在但被单次散射模型丢失的那部分能量的比例"。

| roughness | reflectivity（典型值） | ecFactor |
|-----------|----------------------|---------|
| 0.0（镜面）| ≈ 1.0 | ≈ 0 |
| 0.5（中等）| ≈ 0.7 | ≈ 0.43 |
| 1.0（粗糙）| ≈ 0.4 | ≈ 1.5 |

### 7.3 在 Shader 中的应用

```hlsl
// Blender 原始（Frame.011）
float3 indirectSpecComp = ecFactor * (specularFGD * specularFGD_Strength);
// 意义：把丢失的能量按 specularFGD 的分布加回来

// Unity 还原（完整写法）
float3 indirectSpecular_base = envColor * specFGD;
float3 indirectSpecular_ms   = indirectSpecular_base * ecFactor;
float3 indirectSpecular      = indirectSpecular_base + indirectSpecular_ms;
// 简化等价：= envColor * specFGD / reflectivity
```

> **常见错误**：`specFGD * ecFactor` 不乘 `envColor`，导致 indirectSpecular 几乎为黑（specFGD ≈ 0.04~0.1，ecFactor ≈ 0.5，结果 ≈ 0.02~0.05）。

---

## 8. 完整 IBL 管线总览

```
离线预计算
├── 预过滤 Cubemap（N 个 mip 级别，按 roughness 积分）
├── FGD LUT（512×512，R=B_term, G=A+B, B=diffuseFGD）  ← Non-Color/Linear!
└── SH 系数（9个，来自环境漫射积分）

实时 Fragment Shader
├── 查 FGD LUT（GetPreIntegratedFGD）
│     输入：NdotV, perceptualRoughness, fresnel0
│     输出：specFGD, diffFGD, reflectivity
│
├── 间接漫射
│     indirectDiffuse = albedo * (1-metallic) * diffFGD * ambientColor
│
├── 间接镜面（主项）
│     R = reflect(-V, N)
│     envColor = SampleCubemap(R, roughness_mip)
│     indirectSpecular_base = envColor * specFGD
│
└── 多重散射补偿
      ecFactor = 1/reflectivity - 1
      indirectSpecular = indirectSpecular_base * (1 + ecFactor)
                       = indirectSpecular_base / reflectivity
                       = envColor * specFGD / reflectivity
```

---

## 9. Unity 迁移对照

| 模块 | Goo Engine（Blender） | Unity URP/Built-in |
|------|----------------------|-------------------|
| 预过滤环境 | SHADERINFO.AmbientLighting（专有） | `unity_SpecCube0`（反射探针） |
| 漫射环境 | SHADERINFO.AmbientLighting | `SampleSH(N)` 或双色半球 |
| FGD LUT | 内嵌 Blender 图像 | 导出 PNG，sRGB 必须关闭 |
| LUT 通道 | R=B, G=A+B, B=diffuse | HDRP标准：R=A, G=B, B=diffuse |
| reflectivity | 直接读 LUT.G | HDRP 内加 `s.r + s.g` |
| specularFGD | `lerp(LUT.R, LUT.G, f0)` | `f0 * s.r + s.g`（HDRP） |

### Unity HLSL 参考实现

```hlsl
TEXTURE2D(_fgdLUT);
SAMPLER(linear_clamp_sampler);

void GetPreIntegratedFGD(TEXTURE2D_PARAM(lut, s),
    float NdotV, float perceptualRoughness, float3 fresnel0,
    out float3 specFGD, out float diffFGD, out float reflectivity)
{
    // 半纹素偏移（推测分辨率 512）
    float2 uv = float2(NdotV, perceptualRoughness);
    uv = uv * (1.0 - 1.0 / 512.0) + 0.5 / 512.0;

    float4 s = SAMPLE_TEXTURE2D(lut, s, uv);
    // 本 LUT 布局: R=B_term, G=A+B, B=diffuseFGD
    specFGD      = lerp(s.rrr, s.ggg, fresnel0); // = f0*A + B
    diffFGD      = s.b;
    reflectivity = s.g;                           // = A+B，直接读取
}

// 调用示例
float3 fresnel0     = lerp(0.04, surfaceData.albedo, surfaceData.metallic);
float  NoV          = saturate(dot(normalWS, viewDirWS));
float  perceptualR  = 1.0 - surfaceData.smoothness;

float3 specFGD; float diffFGD, reflectivity;
GetPreIntegratedFGD(TEXTURE2D_ARGS(_fgdLUT, linear_clamp_sampler),
                    NoV, perceptualR, fresnel0,
                    specFGD, diffFGD, reflectivity);

// 间接漫射
float3 ambientColor  = lerp(unity_AmbientGround.rgb, unity_AmbientSky.rgb,
                            normalWS.y * 0.5 + 0.5);
float3 indirectDiff  = surfaceData.albedo * (1 - surfaceData.metallic)
                     * diffFGD * ambientColor;

// 间接镜面（含多重散射补偿）
float3 R             = reflect(-viewDirWS, normalWS);
float  mip           = perceptualR * UNITY_SPECCUBE_LOD_STEPS;
float3 envColor      = DecodeHDREnvironment(
                           SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0,
                               samplerunity_SpecCube0, R, mip),
                           unity_SpecCube0_HDR);
float3 indirectSpec  = envColor * specFGD / max(reflectivity, 1e-4);
//     等价于：envColor * specFGD * (1 + ecFactor)，其中 ecFactor = 1/r - 1
```

---

## 10. 常见陷阱

| 问题 | 错误写法 | 正确写法 |
|------|---------|---------|
| FGD LUT 色彩空间 | 勾选 sRGB | **必须 Non-Color / Linear** |
| specular 缺环境色 | `specFGD * ecFactor` | `envColor * specFGD / reflectivity` |
| reflectivity 为 0 | 直接除法 | `max(reflectivity, 1e-4)` 保护 |
| HDRP LUT 通道混用 | 直接复用，不调整读法 | 改为 `f0*s.r + s.g`，`reflectivity=s.r+s.g` |
| fresnel0 基准值 | 任意写 | 非金属 `0.04`（标准）或 `0.08`（高反射材质） |
