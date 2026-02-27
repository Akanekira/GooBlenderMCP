# AgX Display Transform — 原理与 URP 还原方案

> 适用场景：将 Blender（Goo Engine）使用 AgX 色彩管理的渲染效果迁移至 Unity URP。
> 文档版本：2026-02-28

---

## 目录

1. [AgX 是什么](#1-agx-是什么)
2. [AgX 完整计算流程](#2-agx-完整计算流程)
3. [本项目 Blender 场景的额外后处理](#3-本项目-blender-场景的额外后处理)
4. [URP 还原方案对比](#4-urp-还原方案对比)
5. [方案 A — 自定义 Renderer Feature](#5-方案-a--自定义-renderer-feature)
6. [方案 B — LUT 烘焙](#6-方案-b--lut-烘焙)
7. [常见问题](#7-常见问题)

---

## 1. AgX 是什么

AgX 是由 Troy Sobotka 设计的 **Display Transform（显示变换）**，在 Blender 4.0 中替代了 Filmic 成为默认选项。

### 与 Tonemapping 的区别

"AgX 是 Tonemapping"是一种通俗说法。准确定义：

| 概念 | 含义 |
|------|------|
| **Tonemapping** | 仅将 HDR 压缩到 LDR 的映射函数，如 Reinhard、ACES |
| **Display Transform** | 包含色域旋转 + Log 压缩 + Tonemapping + 输出还原的完整管道 |
| **AgX** | Display Transform，Tonemapping 只是其中一步 |

### AgX 解决的核心问题

普通 Tonemapping（Reinhard / ACES）在处理高饱和度高光时会产生**色相偏移**：

```
纯红色高光  →  Reinhard/ACES  →  偏橙黄色   ✗
纯红色高光  →  AgX            →  保持红色   ✓
```

根本原因：普通 Tonemapping 直接在 sRGB 空间做 S 曲线，三通道压缩速率不一致导致色相漂移。AgX 通过前置色域旋转解决了这一问题。

---

## 2. AgX 完整计算流程

```
场景线性 sRGB
      │
      ▼
┌─────────────────────────────────┐
│  Step 1  色域旋转                │  场景 sRGB → AgX 工作色域
│          3×3 矩阵乘法            │
└─────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────┐
│  Step 2  Log2 编码               │  HDR 动态范围压缩到 [0,1]
│          -10 EV ~ +6.5 EV        │  共 16.5 档
└─────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────┐
│  Step 3  逐通道 S 曲线           │  Tonemapping 部分
│          多项式拟合 Sigmoid       │  每通道独立压缩
└─────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────┐
│  Step 4  Look（可选）            │  Medium High Contrast 等
│          对比度曲线叠加           │
└─────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────┐
│  Step 5  输出色域还原             │  AgX 工作色域 → sRGB 显示
│          逆矩阵乘法               │
└─────────────────────────────────┘
      │
      ▼
屏幕显示值 [0,1]
```

### Step 1 — 色域旋转矩阵

来源：Blender OCIO config（AgX v0.1.6）

```
输入矩阵（sRGB → AgX 工作色域）：
┌ 0.8566  0.1373  0.1119 ┐
│ 0.0951  0.7612  0.0768 │
└ 0.0483  0.1014  0.8113 ┘

输出矩阵（AgX 工作色域 → sRGB，上矩阵的近似逆）：
┌  1.1271  -0.1413  -0.1413 ┐
│ -0.1106   1.1578  -0.1106 │
└ -0.0165  -0.0165   1.2519 ┘
```

矩阵的作用：让每个通道的能量分布更均匀，使后续逐通道 S 曲线不会引起色相偏移。

### Step 2 — Log2 编码

```
AgX_Log(x) = saturate( (log2(x) - (-10)) / (6.5 - (-10)) )
           = saturate( (log2(x) + 10) / 16.5 )
```

将场景光照值的 16.5 档动态范围线性映射到 [0, 1]。

### Step 3 — S 曲线（多项式近似）

AgX 使用拟合多项式逼近 Sigmoid，实时渲染中的标准近似：

```hlsl
float3 AgXCurve(float3 x)
{
    float3 x2 = x * x;
    float3 x4 = x2 * x2;
    float3 x6 = x4 * x2;
    return  -17.86 * x6 * x
            + 78.01 * x6
            - 126.7 * x4 * x
            +  92.06 * x4
            -  28.72 * x2 * x
            +   4.361 * x2
            -   0.1718 * x
            +   0.002857;
}
```

**逐通道**独立计算是 AgX 色相稳定的关键（而非对 luminance 做压缩）。

### Step 4 — Look：Medium High Contrast

在 S 曲线之后叠加的对比度曲线，以中灰（0.5）为轴心向两侧推：

```hlsl
float3 AgXLookMedHighContrast(float3 x)
{
    float3 pivot    = 0.5;
    float3 contrast = 1.35;
    return (x - pivot) * contrast + pivot;
}
```

---

## 3. 本项目 Blender 场景的额外后处理

**场景**：`chr_0017_yvonne_uimodel`（Goo Engine 4.4）

除 AgX 本身外，合成器节点链和 EEVEE 后处理也参与了最终图像：

### 合成器节点链（全部启用）

| 节点 | 关键参数 | 效果 |
|------|----------|------|
| 色调映射 | RD_PHOTORECEPTOR, intensity=0.0 | 基本中性 |
| 色彩校正 | gain=**1.1**, saturation=1.025 | 整体亮度 +10% |
| 色彩平衡 | lift_G=**0.977**, lift_B=**0.987** | 阴影偏暖（轻微去蓝绿） |
| 色相/饱和度 | 接近默认 | 影响较小 |

### EEVEE 后处理

| 效果 | 参数 |
|------|------|
| Bloom | 启用，intensity=0.1 |
| SSR | 启用 |

### 颜色偏差优先级

```
1. AgX + Medium High Contrast  ← 最主要（色相/对比整体偏移）
2. 自定义色彩曲线              ← 次要
3. 合成器 gain=1.1             ← 整体偏亮 10%
4. 色彩平衡 lift               ← 阴影偏暖
5. Bloom                       ← 高光溢出
```

---

## 4. URP 还原方案对比

| 方案 | 精度 | 实现难度 | 适用场景 |
|------|------|----------|---------|
| **A. 自定义 Renderer Feature** | 最高，参数可调 | 中（需写 C# + Shader） | 需要精确还原且动态调整 |
| **B. LUT 烘焙** | 很高（取决于 LUT 精度） | 低（无需写代码） | 快速上线，效果固定 |
| **C. 内置参数近似** | 中等 | 最低 | 视觉预览，不追求精确 |

> Unity HDRP 2022.2+ 内置了 AgX（Volume → Tonemapping → AgX），如使用 HDRP 直接选用即可，无需以下方案。

---

## 5. 方案 A — 自定义 Renderer Feature

### 文件结构

```
Assets/
├── Rendering/
│   ├── AgXRendererFeature.cs
│   └── Shaders/
│       └── Hidden_AgX.shader
```

### AgXRendererFeature.cs

```csharp
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AgXRendererFeature : ScriptableRendererFeature
{
    class AgXPass : ScriptableRenderPass
    {
        Material _mat;
        RTHandle _tempRT;

        public AgXPass(Material mat)
        {
            _mat = mat;
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData data)
        {
            var desc = data.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref _tempRT, desc, name: "_AgXTemp");
        }

        public override void Execute(ScriptableRenderContext ctx, ref RenderingData data)
        {
            var cmd = CommandBufferPool.Get("AgX");
            var src = data.cameraData.renderer.cameraColorTargetHandle;
            Blitter.BlitCameraTexture(cmd, src, _tempRT, _mat, 0);
            Blitter.BlitCameraTexture(cmd, _tempRT, src);
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            _tempRT?.Release();
        }
    }

    [SerializeField] Shader _shader;
    Material _mat;
    AgXPass _pass;

    public override void Create()
    {
        if (_shader == null) return;
        _mat = CoreUtils.CreateEngineMaterial(_shader);
        _pass = new AgXPass(_mat);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData data)
    {
        if (_mat == null) return;
        renderer.EnqueuePass(_pass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(_mat);
    }
}
```

### Hidden_AgX.shader

```hlsl
Shader "Hidden/AgX"
{
    SubShader
    {
        Pass
        {
            ZTest Always ZWrite Off Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // ── 矩阵（来源：Blender AgX OCIO config v0.1.6）─────────────────
            static const float3x3 AGX_INSET = float3x3(
                0.8566, 0.1373, 0.1119,
                0.0951, 0.7612, 0.0768,
                0.0483, 0.1014, 0.8113
            );
            static const float3x3 AGX_OUTSET = float3x3(
                 1.1271, -0.1413, -0.1413,
                -0.1106,  1.1578, -0.1106,
                -0.0165, -0.0165,  1.2519
            );

            // ── Log2 压缩（-10EV ~ +6.5EV）──────────────────────────────────
            float3 AgXLog(float3 x)
            {
                x = max(x, 1e-10);
                return saturate((log2(x) + 10.0) / 16.5);
            }

            // ── S 曲线（多项式拟合 Sigmoid）──────────────────────────────────
            float3 AgXCurve(float3 x)
            {
                float3 x2 = x * x;
                float3 x4 = x2 * x2;
                float3 x6 = x4 * x2;
                return  -17.86 * x6 * x
                        + 78.01 * x6
                        - 126.7 * x4 * x
                        +  92.06 * x4
                        -  28.72 * x2 * x
                        +   4.361 * x2
                        -   0.1718 * x
                        +   0.002857;
            }

            // ── Look：Medium High Contrast ───────────────────────────────────
            float3 AgXLookMedHighContrast(float3 x)
            {
                return (x - 0.5) * 1.35 + 0.5;
            }

            // ── 合成器叠加（对应本项目 Blender 场景）────────────────────────
            float3 ApplyCompositor(float3 x)
            {
                // 色彩校正 gain=1.1
                x *= 1.1;
                // 色彩平衡 lift：阴影偏暖（去蓝绿）
                x.g = x.g + (-0.023) * (1.0 - x.g);
                x.b = x.b + (-0.013) * (1.0 - x.b);
                return x;
            }

            // ── 主函数 ───────────────────────────────────────────────────────
            float3 ApplyAgX(float3 col)
            {
                col = mul(AGX_INSET, col);
                col = AgXLog(col);
                col = AgXCurve(col);
                col = saturate(col);
                col = AgXLookMedHighContrast(col);
                col = mul(AGX_OUTSET, col);
                return saturate(col);
            }

            half4 Frag(Varyings i) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, i.texcoord);
                col.rgb = ApplyAgX(col.rgb);
                col.rgb = ApplyCompositor(col.rgb);
                return col;
            }
            ENDHLSL
        }
    }
}
```

### 接入步骤

1. 将两个文件放入 Unity 项目
2. URP Renderer Asset（`UniversalRenderer.asset`）→ Add Renderer Feature → **AgX Renderer Feature**
3. 将 `Hidden/AgX` shader 拖入 Feature 的 Shader 槽
4. 确保 URP 的 Tonemapping 设置为 **None**（避免双重 Tonemap）

---

## 6. 方案 B — LUT 烘焙

无需写代码，将 Blender 完整颜色管道烘焙为一张 LUT 图。

### 步骤

**1. 生成 Identity Hald CLUT**

下载一张中性 Hald CLUT 图（32级，即 32×32×32 个颜色样本，图像尺寸 1024×1024）。
也可用 Python 生成：

```python
# 生成 32 级 Hald CLUT Identity 图（在任意 Python 环境中运行）
import numpy as np
from PIL import Image

level = 32
size = level * level
img = np.zeros((size, size, 3), dtype=np.uint8)
for b in range(level):
    for g in range(level):
        for r in range(level):
            x = (b % level) * level + r
            y = (b // level) * level + g
            img[y, x] = [
                int(r / (level - 1) * 255),
                int(g / (level - 1) * 255),
                int(b / (level - 1) * 255),
            ]
Image.fromarray(img).save("identity_hald_clut.png")
```

**2. 在 Blender 中处理**

- 打开 Blender，将 Identity 图作为平面贴图或在合成器中以 Image 节点加载
- 确保场景色彩管理全部开启（AgX + 合成器节点）
- 渲染输出，保存结果图为 `agx_lut.png`

**3. 在 Unity 中应用**

```
Volume → Color Grading
  Mode: Low Dynamic Range
  Lookup Texture: agx_lut（拖入）
```

> LUT 图导入设置：关闭 sRGB，Filter Mode = Bilinear，不生成 Mipmap。

---

## 7. 常见问题

**Q: 为什么关闭 AgX 后颜色比 Unity 暗？**
合成器 gain=1.1 被一起关闭了。单独还原 AgX 时，Unity 那边可以用 Post Exposure +0.15 补偿。

**Q: URP 中是否需要关闭内置 Tonemapping？**
是，必须将 Volume 中的 Tonemapping 设为 **None**，否则会出现双重映射导致画面过曝。

**Q: Look 曲线的对比度系数 1.35 是从哪来的？**
通过对比 Blender AgX Medium High Contrast 在中间调的斜率拟合得出的近似值，非官方数值。如需精确还原建议使用 LUT 方案。

**Q: 这个方案能还原 Bloom 吗？**
不能。Bloom 需要另外在 URP Volume 中开启并调整参数（intensity ≈ 0.1，threshold 根据场景调整）。

---

*文档对应场景：`chr_0017_yvonne_uimodel` / Goo Engine 4.4 / BlenderMCP v1.26.0*
