# 卡通渲染方案分享

> 面向 TA / 美术 + 程序的技术分享
> 参考实现：原神（赛璐璐路径）、明日方舟：终末地 PBRToonBase（PBR Toon 路径）

---

## 🎯 一、概述

卡通渲染（Toon Rendering）的本质不是"把游戏做成动漫风"，而是**在光照模型中注入美术意图**——用规则打破物理真实感，让角色在任意光照环境下都能呈现符合原画设计的色彩表达。

主流二次元游戏的渲染风格并没有泾渭分明的流派划分。实际上，**色彩鲜明、高光增强、在平涂基础上强化材质质感**是二次元画风的共同底色；真正区分风格的，是对 PBR 材质质感的还原程度——具体体现在法线强度的取舍、高光的物理精度与卡通化程度、阴影边缘的软硬处理等维度上。还原度越低，视觉结果越趋近平涂色块；还原度越高，材质之间的质感差异（布料/皮肤/金属）越显著，整体呈现出更强的体积感与厚涂感。

这种连续可调的"风格谱系"意味着，技术上需要同时掌握两端的实现手段：一端是赛璐璐式的风格化截断与色块控制，另一端是 Cook-Torrance / GGX 等基于物理的高光与间接光积分——大多数项目的实际方案都介于两者之间，按材质区域和美术需求分别调配。

本文将围绕**漫反射、高光、间接光**三个光照维度，以及描边、边缘光、面部阴影等风格化处理技巧，逐一介绍其实现原理与可调节的参数空间。

---

## 🎨 二、渲染方案

### 💡 2.1 光照模型

#### 🌑 漫反射

漫反射是最直接影响视觉风格的光照分量。光影分界线的清晰程度决定了体积感的强弱：边缘越硬，阴影越趋近平涂色块，造型感扁平；边缘越软，明暗过渡越连续，体积感越显著。卡通漫反射的设计可以拆解为两个**相互独立**的维度：先由 NdotL **塑形**出 shadow 值，再将 shadow 值**着色**为最终颜色。

---

##### 阴影形状

阴影形状由两部分决定：**边缘软硬**（映射函数）和**分界线位置**（偏移修正）。

###### 边缘软硬

阴影边缘的软硬是风格谱系上最直观的调节轴——从完全二值色块到柔和渐变，由 NdotL 的映射函数连续控制：

| 函数 | 特点 | 适用偏向 |
|------|------|---------|
| `step(t, x)` | 完全二值，零过渡 | 极硬平涂风格 |
| `smoothstep(t-s, t+s, x)` | 固定宽度线性过渡，softness 控制宽窄 | 可调软硬，softness→0 退化为 step |
| `SigmoidSharp(x, center, sharp)` | S 形曲线，sharp 连续控制从极软到极硬 | 连续软硬控制，sharp→∞ 退化为 step |

```hlsl
// step / smoothstep（硬边平涂）
float halfLambert = NdotL * 0.5 + 0.5;
float shadow = smoothstep(threshold - softness, threshold + softness, halfLambert);
// softness → 0 时等价于 step，产生清晰的二值色块

// SigmoidSharp（连续软硬控制，终末地 PBRToonBase 方案）
float SigmoidSharp(float x, float center, float sharp)
{
    float t = -3.0 * sharp * (x - center);
    return 1.0 / (1.0 + pow(100000.0, t));
}
// sharp 大 → 边缘极硬（趋近 step）；sharp 小 → 边缘柔和渐变
```

###### 分界线位置修正（阴影偏移贴图）

当阴影边缘设置较硬时，阴影边缘对法线质量极度敏感——法线稍有不均，step/smoothstep 就会在造型关键处产生不可控的形状破坏。解决方式是由美术绘制**阴影偏移贴图**，逐像素微调明暗分界线的位置，效果所见即所得。

> **前提**：模型需要**全展 UV**（Full UV Unwrap），偏移值才能精确对应到各部位。

```hlsl
// _CelShadowOffsetTex：全展 UV，R 通道 [0,1] → 重映射为偏移量 [-1,1]
half celShadowOffsetTex   = SAMPLE_TEXTURE2D(_CelShadowOffsetTex, sampler_LinearRepeat, uv).r;
half celShadowOffsetValue = _UseCelOffsetTex ? (1.0 - celShadowOffsetTex) * 2 - 1 : 0; // 取反后重映射：白(1)→负偏移(受光扩大)，黑(0)→正偏移(阴影扩大)

// 将偏移叠加到基础阈值，平移明暗交界线
half celShadowMidPoint    = _CelShadeMidPoint + celShadowOffsetValue;
half shadow               = smoothstep(celShadowMidPoint, celShadowMidPoint + _CelShadowSoftness, NoL);
```

- **R > 0.5**（白色）：取反后为负偏移，阈值左移，受光侧扩大 → 在高光或发丝造型处卡出亮区
- **R < 0.5**（黑色）：取反后为正偏移，阈值右移，背光侧扩大 → 强化局部体积感阴影
- **R = 0.5**（中灰）：取反后偏移为零，等效于纯参数驱动，不施加任何修正

###### 角色自身投影（Self Shadow）

NdotL 只反映法线与光线的夹角，无法表达几何遮挡关系——头发遮脸、衣领遮颈、手臂遮躯干，这些都需要采样 Shadowmap 才能判断。直接复用场景级 Shadowmap（CSM）精度不足：CSM 的正交视锥体以**相机可见距离**为基准划分（固定半径或 Cascade 分层），覆盖半径 50 m 时 4096² 分辨率下每纹素约 2.4 cm，大量纹素耗费在地面和场景几何上，根本无法表达头发/衣领级别的遮挡边缘。因此单独为角色构建一张专用阴影图：以角色 AABB 在光源空间的投影范围作为正交视锥体，架设一盏正交相机渲染角色深度 RT（**Close-Fit AABB**）。AABB 约 0.5 m × 0.5 m，512² 分辨率即可达到 ~0.05 cm/纹素，精度提升约 **50 倍**；片元着色器将当前片元世界坐标变换到该相机的 NDC 空间采样深度 RT，判断是否被遮挡。

```hlsl
// 采样阶段核心（片元着色器）
// 世界坐标 → 自投影相机裁剪空间
float4 posCS = mul(_SelfShadowWorldToClip, float4(positionWS, 1));
float2 uv    = posCS.xy * 0.5 + 0.5;       // NDC → [0,1] UV
float  depth = posCS.z + depthBias;         // 深度 + 偏移（跨平台符号修正）

// 硬件 PCF 采样：0 = 完全在阴影中，1 = 完全不在阴影中
float selfShadow = SAMPLE_TEXTURE2D_SHADOW(_SelfShadowMap, sampler_SelfShadowMap,
                                           float3(uv, depth));
// 距离衰减：shadowRange 边缘平滑过渡到无阴影，避免硬截断
selfShadow = lerp(selfShadow, 1.0, saturate((depth - (shadowRange - 2)) / 2));

// 与 NdotL 阴影合并：多路阴影取最暗值
shadowCombined = min(shadowNdotL, selfShadow);
```

关键处理细节：

| 问题 | 处理方式 |
|------|---------|
| **Shadow Acne** | Depth Bias 偏移 + 跨平台符号修正（OpenGL/DX/Metal NDC 方向不同） |
| **背光侧 Acne** | NdotL Fix：`shadow × smoothstep(0.1, 0.2, NdotL)`，强制背光侧压入阴影 |
| **脸部穿模** | 脸部像素**跳过 Shadowmap 采样**，脸部阴影由 SDF 独立处理（见第③节） |
| **边缘硬截断** | shadowRange 边缘 2 米内线性 lerp 到 1（无阴影） |

以上三步（NdotL 映射 / 偏移贴图修正 / 自身投影遮挡）共同决定最终 shadow 值 `[0,1]`，再流入下方的着色路径。

---

##### 阴影着色

shadow 值确定之后，需要将其映射为美术预设的颜色，而非物理上的单一灰度值。主要有两条路径：

###### 路径 A：Ramp 贴图

```
shadow值 [0,1] → 查 1D Ramp 贴图 → 风格化阴影颜色
```

Ramp 贴图的核心作用是定义**明暗交界线处的颜色过渡**——美术可以自由设计亮部到暗部的颜色（如蓝紫冷色阴影与暖黄亮部形成色相对比）。不同材质区域通常使用独立的 Ramp 图，最常见的分法是**皮肤 Ramp** 与**衣服 Ramp**，使两者的阴影色调和过渡感各自独立可控。

###### 路径 B：ColorID + ColorTint

```
ColorID 贴图（逐像素材质标签）→ 按 ID 索引亮色/暗色参数
shadow值 → 阈值判定 → lerp(darkColor[id], litColor[id], shadow)
```

模型 UV 展开后按材质区域涂不同 ID 值（皮肤/布料/金属各一个 ID），运行时按 ID 索引独立的亮色和暗色，美术在材质面板直接调色，所见即所得。代价是只有二值明暗（无中间色带渐变），适合追求硬边平涂效果。

两条路径也可**混用**：ColorID 划分材质区域，每个区域各自采样独立的 Ramp 行，兼顾区域独立性与色带灵活性。

---

#### ✨ 高光

高光处理的差异直接体现了材质区分度的高低。高光可以按各向同性/各向异性分为两类，分别适用不同材质：

##### 各向同性高光（金属、皮肤等）

适用于大多数材质——金属、皮肤、硬质甲片等，高光形状以 NdotH 为中心对称扩散，与观察方向的旋转无关。

**风格化截断方案**

通常使用 Phong 或 Blinn-Phong 的简化版，配合卡通化的 step 截断：

```hlsl
// 风格化截断高光
float spec = pow(NdotH, shininess);
spec = step(specThreshold, spec); // 二值化，形成硬边高光斑
float3 specular = spec * specColor;
```

- 高光形状不区分金属/非金属，所有材质相近
- 常用固定颜色（白色或浅色），不随粗糙度变化
- 视觉效果偏卡通，高光像"贴上去的高亮斑"

**微表面物理模型**

完整的 Cook-Torrance 微表面模型：

```hlsl
// F × D × V（Fresnel × Distribution × Visibility）
float3 F = F_Schlick(fresnel0, float3(1,1,1), LdotH);
// fresnel0 = lerp(0.04, albedo, metallic) — 金属/非金属完整区分

// 等向 GGX（绝大多数材质）
float D_iso = a² / (PI * pow(NdotH² * a² + (1-a²), 2));
float V_iso = 0.5 / (NdotL * sqrt(...) + NdotV * sqrt(...));

// 各向异性 GGX（布料、拉丝金属等）
float D_aniso = 1 / (PI * roughT * roughB * f²);
// 沿织物纹理方向拉长的高光，T/B 轴粗糙度独立控制
```

- 金属件（枪械扣件、甲片）/ 非金属（布料、皮肤）高光形状完全不同
- 粗糙度越高，高光越扩散、越暗——这是 PBR Toon"厚涂感"的来源之一
- 各向异性模式下，布料高光沿纹理方向延伸，视觉上更有织物质感
- roughness 通常由 `1 - smoothness` 再平方得到（`α = (1-smoothness)²`），极光滑表面高光峰值极高，LDR 管线需设置最小粗糙度（`max(α, 0.04)`）或在进 Ramp 前 `saturate` 截断，防止过曝

**Matcap 贴图方案**

Matcap（Material Capture）将预渲染好的材质球光照存储为贴图，用视角空间法线 xy 作为 UV 索引，不依赖运行时动态光照：

```
UV = normalVS.xy * 0.5 + 0.5    →    采样 MatcapTex
```

对于**平涂赛璐璐风格**，Matcap 是兼顾风格化与物理正确感的理想方案：物理上 Matcap 本身来自真实材质球的光照捕获，天然具备合理的 Fresnel 衰减、边缘柔化和镜面形状；风格上美术可以自由控制高光的色相、软硬和位置，无需理解 GGX 参数。与 step 截断的硬边高光相比，Matcap 能以极低的运行时成本呈现介于"贴图高光"和"物理高光"之间的过渡质感——这正是赛璐璐风格追求的"看起来对，但不物理"的平衡点。

适合**风格化金属扣件、皮肤高光、布料光泽**等——美术可以直接在贴图上画出想要的光照质感，不受场景灯光影响。

```hlsl
float2 matcapUV  = normalVS.xy * (0.5 * _UvScale) + 0.5;
half4  matcapTex = SAMPLE_TEXTURE2D(_MatCapTex, sampler_LinearRepeat, matcapUV);

// ADD 模式：叠加高光，不改变暗部
albedo += matcapTex.rgb * matcapTex.a;

// Blend 模式：覆盖式替换，适合整面积材质替换
albedo  = lerp(albedo, matcapTex.rgb, _MatcapBlend);
```

- **旋转问题**：角色旋转时 Matcap UV 会随视角空间法线滚动，纯装饰性高光可接受；若需固定 Matcap 方向，可在视角空间 normalVS 中手动锁定 z 轴旋转分量
- **与 Rim 的区别**：Rim 描述几何轮廓边缘，Matcap 描述整个材质面的光照感，两者可叠加使用
- **不随灯光变化**：与风格化截断方案同属"固定高光"范畴，适合风格化优先路径；若需光照响应，改用 GGX 方案

**三种各向同性高光方案对比**

| | 风格化截断（Phong+step） | Matcap 贴图 | GGX 微表面 |
|--|------------------------|------------|------------|
| 光源响应 | 有（NdotH 驱动） | 无（固定） | 有（完整 BRDF） |
| 美术控制 | 参数（shininess/threshold） | 直接绘制贴图 | 参数（roughness/metallic） |
| 材质区分度 | 低 | 中（贴图决定） | 高（金属/非金属完全不同） |
| 实现成本 | 极低 | 低 | 中等 |
| 过曝风险 | 低 | 无 | 高（光滑表面需限幅） |

---

##### 各向异性高光（头发）

**头发各向异性高光**

头发在微观层面是鳞片状排列的，光照沿发丝方向天然呈现各向异性（Anisotropic）高光。两类实现策略在美术控制权与物理响应性上各有侧重。

**手绘遮罩方案**

手绘遮罩方案不追求物理精度，头发高光直接由美术在贴图上"画"出来，运行时用 NdotV（视角正对度）驱动强度，让高光在掠射角时自然衰减：

```hlsl
// _HairSpecMask：美术手绘高光形状贴图，R 通道存遮罩
float hairMask = SAMPLE_TEXTURE2D(_HairSpecMask, sampler_HairSpecMask, uv).r;
float NdotV    = saturate(dot(N, V));
float hairSpec = hairMask * NdotV * _HairSpecIntensity;
float3 hairSpecColor = hairSpec * _HairSpecColor;
```

- **遮罩贴图**：美术在 DCC（Photoshop / Substance Painter）中按设计稿直接绘制高光形状，位置与形状完全由美术控制
- **NdotV 调制**：正对相机时高光最强，掠射角（头部侧面）时衰减为零，模拟基础视角依赖感
- **优点**：所见即所得，美术成本极低，无 UV 方向限制，高光形状可任意设计
- **局限**：高光不随光源方向变化，为纯风格化固定效果

**Kajiya-Kay 各向异性方案**

Kajiya-Kay 方案采用基于 Kajiya-Kay 模型的各向异性高光，核心是用**径向切线（Radial Tangent）**代替 UV 切线，保证无论 UV 如何展开，高光始终呈现水平环绕头部的天使环形状。

```hlsl
// Step 1：计算径向切线（绕头部中心旋转的水平切线）
float3 V_offset = positionOS - centerOS;               // 相对头部中心偏移
float3 rawTangent = float3(-V_offset.z, 0, V_offset.x); // 绕 Y 轴旋转 90°
float3 worldRawTangent = mul((float3x3)objectToWorld, rawTangent);
// 两次叉积正交化：将径向切线投影到网格表面
float3 bitangent    = cross(worldRawTangent, worldNormal);
float3 radialTangent = cross(worldNormal, bitangent);  // 最终水平环绕切线

// Step 2：Kajiya-Kay 各向异性项
// TdotH 衡量切线与半角向量的对齐程度；sin²(T,H) = 1 - dot(T,H)²
float TdotH    = dot(normalize(radialTangent), halfDir);
float anisoTerm = sqrt(max(0.0, 1.0 - TdotH * TdotH));

// Step 3：多层遮罩精细控制
float fresnelMask = pow(saturate(dot(N, V)), 5);        // 抑制边缘处的硬高光
float shadowMask  = lerp(1.0, shadowArea, _ShadowIntensity); // 阴影区域减弱高光

float spec = pow(anisoTerm, _HairShininess) * fresnelMask * shadowMask;
float3 hairSpecular = spec * _HairSpecColor * _HairSpecIntensity;
```

径向切线只依赖顶点的**对象空间位置**相对于头部中心的方位，与 UV 展开完全无关——但**前提是发型几何体近似球形**。对于马尾、长直发、侧编辫等纵向延伸发型，径向切线方向与发丝不符，需改用 **UV 切线**（美术须将 UV 的 U 轴沿发丝走向规整排布）。两者可通过顶点色权重混合：

```hlsl
// _RadialTangentMask：1 = 径向切线（球形发区），0 = UV 切线（特殊发型）
float3 finalTangent = normalize(lerp(TBN_WS[0], radialTangent, _RadialTangentMask));
```

| 发型类型 | 推荐方案 | 美术配合 |
|----------|----------|---------|
| 头顶 / 刘海 / 短发 | 径向切线 | 仅传头部中心点，无需处理 UV |
| 马尾 / 长直发 / 编辫 | UV 切线 | U 轴沿发丝走向规整排布 |
| 混合发型 | 两者混合 | 顶点色 R 通道刷权重分区 |

**两种方案对比**

| | 手绘遮罩方案 | Kajiya-Kay 各向异性方案 |
|--|----------------|----------------------|
| 高光驱动 | 手绘遮罩 × NdotV | 径向/UV切线 × 半角向量 |
| 光源响应 | 无（固定位置） | 有（随灯光实时变化） |
| UV 依赖 | 无 | 球形发区无需，特殊发型需规整UV |
| 形状控制 | 美术完全自由绘制 | 参数控制宽度/强度/颜色 |
| 实现成本 | 极低 | 中等（球形区传中心点；特殊发型需UV规范） |
| 视觉效果 | 平涂固定高光 | 动态天使环各向异性高光 |

---

#### 🌤️ 间接光

间接光是最容易被忽视、但一旦缺失便会整体拉低材质区分度的维度。**间接光是"体积感"与"平涂感"最根本的分水岭**：平涂风格的间接光通常是一个与法线、材质无关的均匀环境色常量，而物理还原路径则让法线方向、粗糙度、金属度、AO 遮蔽共同参与间接光的积分——这些参数的差异会直接显现为材质间视觉上的质感分离。

---

##### 法线参与间接光采样

平涂方案中环境光是常量，不随法线变化，暗部和亮部的间接光完全一致——体积感因此消失。物理路径中，间接漫反射方向由**法线贴图解码后的世界空间法线**驱动：

```hlsl
// 从法线贴图解码切线空间法线，变换到世界空间
float3 normalTS  = DecodeNormal(_NormalTex, uv);          // tangent space
float3 normalWS  = TransformTangentToWorld(normalTS, TBN); // world space

// 间接漫反射：用世界空间法线方向从球谐光照（SH）采样
float3 indirectDiffuse = SampleSH(normalWS) * albedo * (1.0 - metallic);

// 间接镜面：用反射方向 + 粗糙度从 IBL 探针采样
float3 reflectDir    = reflect(-viewDir, normalWS);
float  mipLevel      = perceptualRoughness * MAX_REFLECTION_LOD;
float3 indirectSpec  = SampleCubemapLOD(unity_SpecCube0, reflectDir, mipLevel);
```

法线贴图质量直接影响间接光的方向分布：法线细节越丰富，间接光随表面起伏越有层次感——这是厚涂插画感"每个面都有朝向"的物理来源。

---

##### 材质参数驱动间接光分配

金属度（Metallic）和粗糙度（Roughness）决定间接光在漫射与镜面之间的能量分配，这是平涂和 PBR Toon 材质区分度最核心的差异：

```hlsl
// fresnel0：金属使用 albedo 颜色作为 F0，非金属使用 0.04
float3 fresnel0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

// FGD 预积分查表（以 NdotV、感知粗糙度、fresnel0 为索引）
// specularFGD：预积分 Fresnel-GGX，反映镜面方向的能量比例
// diffuseFGD：Disney 漫反射积分项（偏离朗伯体的修正）
// reflectivity：总反射率，用于能量守恒
GetPreIntegratedFGD(NdotV, perceptualRoughness, fresnel0,
    /*out*/ specularFGD, diffuseFGD, reflectivity);

// 间接漫射：能量守恒 — 被高光反走的能量不再进漫反射
float3 indirectDiffuse = diffuseFGD * albedo * (1.0 - reflectivity) * (1.0 - metallic);

// 间接镜面：IBL 采样结合 FGD 预积分系数
float3 indirectSpec    = indirectIBL * specularFGD;
```

粗糙度的影响是连续可感的：**光滑金属**（低粗糙度）镜面能量集中、反射清晰，与暗部形成强对比，视觉上有金属光泽；**粗糙布料**（高粗糙度）镜面能量扩散、反射模糊，漫射主导，表面呈现更均匀的哑光感。平涂方案中这两者几乎无法区分。

---

##### AO 遮蔽参与间接光

AO（环境光遮蔽）贴图记录了几何凹陷处的遮蔽程度，正确的使用方式是**只遮蔽间接光**，不遮蔽直接光（直接光的自遮蔽已由 NdotL 和 Shadowmap 处理）：

```hlsl
// _P 贴图 G 通道：directOcclusion / AO，[0,1]
float ao = SAMPLE_TEXTURE2D(_PTex, sampler_P, uv).g;

// AO 仅作用于间接光，保留直接光的完整强度
float3 lighting =
    (indirectDiffuse + indirectSpec) * ao   // 间接光受 AO 遮蔽
  + directDiffuse + directSpec;             // 直接光不受 AO 影响
```

平涂方案中 AO 通常直接乘进 albedo，导致阴影形状固化在贴图里，与光照方向脱节；物理路径中 AO 只压制间接光，保留了光照的动态响应。

---

##### Kulla-Conty 能量补偿

微表面 BRDF 的单次散射假设光线在粗糙表面只弹射一次，实际上多次弹射损失的能量在粗糙表面可达 30%+，导致高粗糙度表面看起来"过暗"甚至"消失"。Kulla-Conty 补偿将丢失的多次散射能量补回：

```hlsl
float ecFactor = 1.0 / max(reflectivity, 1e-4) - 1.0;

// 路径A（修正直接高光）：ecFactor 按 F0 比例补回直接高光中的多次散射损失
float3 correctedDirectSpec = directSpec * (fresnel0 * ecFactor + 1.0);

// 路径B（补充间接高光）：ecFactor 乘 FGD 系数，作为间接多次散射贡献
float3 indirectSpecComp    = ecFactor * specularFGD * indirectIBL;

float3 totalLighting = correctedDirectSpec + directDiffuse
                     + indirectSpecComp   + indirectDiffuse;
```

补偿效果在**高粗糙度金属**上最明显——未补偿时粗糙金属暗如哑光塑料，补偿后能量守恒，材质的"厚实感"和"体积感"得以保留。

---

##### 两种间接光方案对比

| | 极简方案 | 物理还原方案 |
|--|----------|------------|
| **法线参与** | 无，环境光常量 | SH/IBL 按法线方向采样，体积感随法线起伏变化 |
| **材质区分** | 金属/非金属间接光几乎相同 | Metallic/Roughness 完整驱动漫射/镜面分配 |
| **AO 使用** | 直接乘 albedo（固化阴影） | 仅遮蔽间接光，直接光不受影响 |
| **能量守恒** | 无 | FGD 预积分 + Kulla-Conty 补偿，粗糙金属不消失 |
| **体积感来源** | 仅靠直接光 NdotL | 间接光随法线/视角/材质连续响应，自然补充暗部体积 |
| **运行成本** | 极低 | 中等（LUT 查表 + IBL 采样） |

---

#### 📊 光照模型总结对比

以下以两端极端配置为参照，实际项目通常按材质区域混用。

| 维度 | 风格化优先 | 物理还原优先 |
|------|--------|---------|
| **漫反射** | 着色：ColorID/单行Ramp；边缘：step/smoothstep 硬边，追求平涂色块 | 着色：多行Ramp（RampIndex 分区）；边缘：SigmoidSharp 软硬可调 + 双路阴影合并 |
| **高光** | Phong/Blinn-Phong 简化，step 截断，不区分材质；或 Matcap 贴图（固定光照，美术直接绘制） | Cook-Torrance GGX（等向+各向异性），F_Schlick，金属度/粗糙度完整响应；需注意光滑表面过曝 |
| **间接光** | 环境色常量或省略，无能量守恒 | FGD 预积分 + Kulla-Conty 能量补偿，间接漫反射+间接高光完整 |
| **材质区分度** | 低（布料/皮肤/金属接近） | 高（不同材质参数驱动截然不同的视觉结果） |
| **运行成本** | 低 | 中等（LUT 查表 + 多路合并） |

---

### 🖌️ 2.2 基于传统光照模型增加的风格化处理

这些技巧直接作用于几何与光照计算，补充光照模型难以呈现的风格化效果，也是两种路径（赛璐璐/PBR Toon）都会用到的共性手段。

---

#### ① ✏️ 描边（Outline）

描边是卡通渲染最标志性的视觉特征，主要有两类技术路线：

**背面法线外扩**（Vertex Shader Outline）

在顶点着色器阶段，将背面的顶点沿法线方向向外偏移，正面渲染时看到的"背面轮廓"即为描边：

```hlsl
// 顶点着色器中
float3 normalCS = normalize(mul((float3x3)UNITY_MATRIX_VP,
                                mul((float3x3)UNITY_MATRIX_M, v.normal)));
o.positionCS.xy += normalCS.xy * _OutlineWidth;
```

- 优点：实现简单，几乎零额外 Draw Call（背面 Pass 与正面 Pass 共用材质）
- 缺点：弯曲处易断线；顶点法线插值不均匀时描边粗细不一致
- 卡通风格建议：描边颜色不用纯黑，而是取 Albedo 的暗色版本（HSV 降低 V），让描边融入材质色调

**模型空间平滑法线**

对法线进行烘焙预处理，将硬边模型的折叠法线在顶点着色器外扩前做平均，解决弯曲处断线问题——代价是需要离线烘焙步骤。

存储方案上，平滑法线（单位向量，3 float）通常塞进 UV2 或 Tangent 的空余通道。为节省带宽，可用**八面体压缩**将其编码为 2 float（共 16 bit 即可接受精度）。

八面体压缩（Octahedral Normal Encoding）将单位向量从 3 float 压缩为 2 float：把球面投影到八面体展开为 `[-1,1]²` 正方形，编解码仅需加减乘除，无三角函数开销。`RG8` 精度约 1.5°，`RG16` 约 0.3°，卡通描边场景完全可接受。顶点着色器中从 UV2 解码出平滑法线后，正常替换原始法线用于外扩即可。

> 参考：[Octahedron Normal Vector Encoding — Krzysztof Narkowicz](https://knarkowicz.wordpress.com/2014/04/16/octahedron-normal-vector-encoding/)

**外扩宽度控制**

统一固定宽度的描边在远景会过粗、近景会过细。两种常用补偿手段：

- **顶点色调制**：在模型上刷顶点色 R 通道 `[0,1]`，`finalWidth = _OutlineWidth * vertexColor.r`。R=0 处描边消失，可精确消除眼睛、细节部位的不需要描边。
- **FOV + 深度屏占比修正**：保证描边在屏幕上的像素宽度恒定，不随距离变化：

```hlsl
// positionVS.z 为视图空间深度（负值），tanHalfFov 由相机参数传入
float screenCorrection = abs(positionVS.z) / (unity_CameraProjection._m11 * _ScreenParams.y * 0.5);
float finalWidth = _OutlineWidth * screenCorrection;
```

**描边深度偏移**

对描边 Pass 做深度偏移，可隐藏不需要的描边（眼睛穿透头发的描边、布料动画穿模产生的内部描边），且不影响 xy 投影位置：

```hlsl
// 核心：利用 positionCS.w == -positionVS.z，在视图空间偏移深度后转回裁剪空间
float offsetVSZ   = abs(positionCS.w) - _DepthOffset;          // 视图空间深度偏移
float offsetCSZ   = offsetVSZ * UNITY_MATRIX_P[2].z + UNITY_MATRIX_P[2].w;
positionCS.z      = offsetCSZ * positionCS.w / -offsetVSZ;     // 手动做透视除法（抵消后续硬件除法）
```

---

#### ② 🔆 边缘光（Rim Light）

边缘光让角色在背光或侧光场景中轮廓依然清晰可见，是卡通渲染中兼顾造型感和立体感的关键效果。

**传统 Fresnel Rim**（NoV 驱动）

```hlsl
float rimFactor = pow(1.0 - saturate(dot(N, V)), _RimPow);
float3 rim = rimFactor * _RimColor;
```

- 简单，适用广，但与几何形态无关——正对相机的平面也会产生 Rim
- 不随场景光源方向变化，有时与整体光照脱节
- 依赖法线质量，法线不均匀时轮廓边缘会不规则——建议配合**遮罩贴图**框定产生边缘光的区域和形状（如只允许肩部、手臂、头顶出现 Rim），压制法线质量差的部位

**屏幕空间深度 Rim**（终末地方案）

通过法线方向偏移 UV 后采样深度图，检测几何边缘：

```hlsl
// 偏移 UV 采样深度差
float2 offsetUV = screenUV + normalVS.xy * _Rim_width;
float currentDepth = SampleDepth(screenUV);
float offsetDepth  = SampleDepth(offsetUV);
float depthRim = saturate(offsetDepth - currentDepth); // 边缘处深度突变
```

深度 Rim 的优势：只在真实几何边缘产生 Rim，平面中间不会产生，准确度远高于 Fresnel Rim。

但单纯的深度差过于"机械"，终末地方案引入**四因子遮罩链**做精细控制：

```
rimMask = DirLightAtten × FresnelAtten × VerticalAtten × min(DepthRim, 0.5)
```

| 因子 | 计算 | 作用 |
|------|------|------|
| **DepthRim** | 深度差 | 检测几何轮廓，精准定位边缘 |
| **FresnelAttenuation** | `(1 - NoV)^4` | 掠射角加强，正对相机处抑制 |
| **DirectionalLightAttenuation** | `lerp(adj, 1.0, saturate(NoL))` | 光照方向响应，背光侧保留，受光侧自然减弱 |
| **VerticalAttenuation** | `saturate(normalWS.y)` | 顶部强、底部弱，防止脚底 Rim 过亮 |

最终结果以 **ADD 加法**叠入主色，Rim 是一种"补光"而非"改色"。

**两种 Rim 的混合使用**

深度 Rim 位置准确但形状"死板"（轮廓有多厚 Rim 就有多厚，难以做造型定制）。两者混合时，用 Fresnel 因子调制深度 Rim 的强度，让 Rim 在掠射角时自然增强、正对相机时自然收敛，遮罩贴图进一步约束哪些部位允许出现 Rim：

```hlsl
float depthRimFactor  = saturate(offsetDepth - currentDepth);
float fresnelFactor   = pow(1.0 - saturate(dot(N, V)), _RimPow);
float rimMask         = SAMPLE_TEXTURE2D(_RimMask, sampler_RimMask, uv).r; // 美术绘制的区域遮罩
float rim             = depthRimFactor * fresnelFactor * rimMask;
```

---

#### ③ 💇 刘海投影（Fringe Shadow）

脸部处理是二次元渲染的核心重点，而刘海投影是构建脸部光影层次的关键细节——它在额头/眼部形成清晰的暗区色块，配合 Ramp 冷色偏移，强化"头发在脸前方"的空间层次感。SDF 阴影无法覆盖该区域，角色级 Shadowmap 分辨率也不足，因此需要专项处理。

**方案 A（深度图采样）** 提取的是**内轮廓**——与深度边缘光的外轮廓（`offsetDepth > selfDepth`）方向相反，这里是刘海在脸部前方，偏移后采样到的深度（刘海）小于当前像素深度（脸部），深度差极小，需要放大处理：

```hlsl
// 边缘光（外轮廓，对比参考）
float depthRim = saturate(offsetDepth - selfDepth - threshold);

// 刘海投影（内轮廓）
// selfDepth:   当前片元（脸部）深度
// offsetDepth: 法线方向偏移后采样的深度（刘海区域）
// 深度差极小，×50 放大后 clamp 到 [0,1] 阴影值
float depthDiffShadow = 1.0 - saturate((selfDepth - offsetDepth - threshold) * 50.0 / 0.1);
```

可直接复用深度边缘光的采样环节，共享同一次 depth RT 读取，零额外 Draw Call，移动端友好。缺点是拉远视角时深度范围扩大，微小深度差被淹没，效果退化。

**方案 B（单独渲染 RT）** 将刘海几何体单独渲染为深度 RT，脸部 Pass 采样此 RT 判断投影区域，精度完全可控，可配合 PCF 做软阴影边缘；代价是额外 Draw Call 与模型拆分的管线成本，适合近景展示等精度要求高的场景。

---

#### ④ 👤 面部 SDF 阴影

脸部阴影若直接用 NdotL 驱动，法线质量和光照方向会导致阴影形状不可控。更通用的方案是预先绘制多角度的面部 SDF 贴图，通过光源与脸部坐标系的夹角实时查表：

**基础 SDF 阴影**

```hlsl
// 构建脸部坐标系（faceRight / faceUp / faceForward 来自骨骼方向）
float3 xzForward        = normalize(float3(faceForward.x, 0, faceForward.z));
float3 faceRightDirWS   = -cross(_FaceUpDirection, xzForward);
float3x3 worldToHead    = float3x3(faceRightDirWS, _FaceUpDirection, xzForward);

// 光源转到脸部空间，只取 XZ 平面
float3 lightHead        = mul(worldToHead, lightDir);
lightHead.y             = 0;
float2 lightXZ          = normalize(lightHead).xz;

// x > 0 为右侧光，UV 水平翻转；y 决定阈值（前向夹角）
float2 flipUV           = uv * float2(sign(lightXZ.x), 1);
float  sdfValue         = SAMPLE_TEXTURE2D(_FaceSDFTex, sampler_LinearRepeat, flipUV).r;
float  threshold        = 1 - (lightXZ.y * 0.5 + 0.5);
float  shadow           = smoothstep(threshold, threshold + _SDFSoftness, sdfValue);
```

**双通道 SDF 提升精度**

单通道 SDF 灰度值有限，smoothstep 插值时易产生色带。将 SDF 拆成 RG 双通道，R 存左半脸、G 存右半脸，阈值映射到 [0,2] 后分段读取：

```hlsl
float2 sdfRG     = SAMPLE_TEXTURE2D(_FaceSDFTex, sampler_LinearRepeat, uv * float2(sign(lightXZ.x), 1)).rg;
float  threshold = Remap(-lightXZ.y, float2(-1,1), float2(0,2));

float  switchT   = smoothstep(0.95, 1.0, threshold);                        // 0→1 段用R，1→2 段用G
float  sdfLerp   = lerp(sdfRG.r, sdfRG.g, switchT);
float  threshLerp= lerp(threshold, smoothstep(1, 2, threshold), switchT);   // 两段各自映射回 [0,1]
float  shadow    = smoothstep(threshLerp, threshLerp + _SDFSoftness, sdfLerp);
```

**抬头低头阴影跳变处理**

脸部骨骼的 y 方向细微变化会导致 SDF 阈值突变。对 y 值影响做 smoothstep 压制，0.5 以内阴影保持稳定：

```hlsl
float ySign     = smoothstep(0.5, 0.8, abs(faceForward.y));
faceForward.y  *= ySign;                                            // [0,0.5] 范围内 y 不参与计算
faceForward     = normalize(faceForward);
// 上方向同理：小角度内固定为世界 up，超过阈值才过渡到真实骨骼 up
float3 faceUp   = lerp(float3(0, sign(_FaceUpDirection.y), 0), _FaceUpDirection, ySign);
```

> **SDF 的维度局限与图集扩展方案**
>
> 上述 smoothstep 压制本质上是一种"规避"而非"解决"：**面部 SDF 贴图天然是二维的**，只编码了光源在水平轴绕脸旋转的阴影变化，没有 Z 轴（俯仰）方向的信息。
>
> 更彻底的方案是**全角度 SDF 图集**：把所有方向的光照 SDF 切片都画出来，打包成一张图集（每格对应一个光照方向），用光源的完整三维方向同时索引行列，替代单层水平轴 SDF。代价是美术制作量成倍增加，通常用于主角或近景高精度展示。
>
> 参考：[知乎 · 全角度面部SDF阴影方案](https://zhuanlan.zhihu.com/p/670837192)

---

### 🔧 2.3 额外的 Trick

光照计算之外，还有一些不依赖材质模型、更偏"工程技巧"的风格化手段，适配性更广，通常按角色类型或场景需求按需启用。

---

#### ① 👁️ 眼睛半透（Iris Transparency）

卡通角色头发遮挡眼睛时，眼睛需要"透出来"。一种干净的方案是：**先用独立 Pass 将眼睛深度预渲染到单独的 RT，再在眼睛主 Pass 里对比场景深度，被遮挡时主动降低自身 Alpha**。

```
预渲染 Pass：眼睛几何体 → 深度写入 EyeDepthTex（不含头发）
主渲染 Pass：头发不透明写入深度缓冲
眼睛 Pass（AlphaBlend）：
    diffSelf = 自身深度 - 场景深度        // 正值 = 被头发遮挡
    diffEye  = 自身深度 - EyeDepthTex    // 对齐预渲染深度，过滤无效像素
    occluded = diffSelf > 阈值
    alpha    = lerp(alpha, occludedAlpha, occluded)  // 被遮挡时降 Alpha
             * (diffEye < 阈值)                       // 过滤无效像素
             * (diffSelf < 0.1)                       // 深度差过大时完全裁除
```

- 眼睛自己管自己，头发 Shader 无需修改，工程侵入性低
- `occludedAlpha`（如 0.7）控制被遮挡时的透明程度，美术可独立调节
- `diffSelf < 0.1` 硬裁除眼睛被深度完全压住的像素，防止在深处仍渗出颜色

---

#### ② 📐 移除透视（Orthographic-like Character Display）

在角色展示/图鉴界面，3D 角色透视感过强时画面会显得"立体违和"。可以用**固定深度的透视除法**替代硬件的逐顶点透视，使所有顶点都投影到同一平面，消除远近缩放差异，产生类似正交投影的平面化效果。

```hlsl
// 顶点着色器中：
// 1. 抵消硬件即将执行的透视除法（乘以 w 恢复裁剪空间坐标）
// 2. 改用中心点的视图深度（centerPosVSz，来自头骨骼）做统一除法
float2 newPosXY   = positionCS.xy * abs(positionCS.w);  // 还原为未除以 w 的裁剪坐标
newPosXY         *= rcp(abs(centerPosVSz));             // 用中心深度统一做透视
positionCS.xy     = newPosXY;
```

效果：将深度不同的像素都压到以 `centerPosVSz` 为基准的正交平面，远处手臂与近处躯干投影尺度一致，消除透视拉伸。

- `centerPosVSz`：通常取头骨骼或角色中心点的视图空间 z 值，由 CPU 传入
- 对近处大角度动作（如伸手向镜头）效果最明显
- 只适用于角色展示等固定镜头场景，战斗/主场景不适用

---

#### ③ 🌈 视角色变（ThinFilmFilter / Rainbow Specular）

模拟薄膜干涉效应（皂泡、昆虫翅鞘、特种织物），随视角产生彩虹色谱偏移：

物理原理：薄膜两界面的反射光存在光程差 `ΔL = 2nd·cos(θ_t)`，不同波长在不同视角满足相长/相消干涉条件，产生随角度变化的彩虹色。

实时近似：预烘焙 RS（Rainbow Specular）LUT，用视角-法线夹角作为横向 UV 查表：

```hlsl
// Facing ≈ pow(1 - saturate(dot(N, V)), 1 / _LayerWeightValue)
float facing = LayerWeight_Facing(N, V, _LayerWeightValue);
float facingAdj = saturate(facing + _LayerWeightValueOffset);

// RS 贴图 UV：横轴=视角，纵轴固定0.5（本质是1D LUT包装成2D贴图）
float2 rsUV = float2(facingAdj, 0.5);

// 双贴图混合，支持不同色谱风格
float4 rsAurora = SAMPLE_TEXTURE2D(_RS_Tex_Aurora, sampler_RS, rsUV);
float4 rsYvonne = SAMPLE_TEXTURE2D(_RS_Tex_Yvonne, sampler_RS, rsUV);
float4 rsBlend  = lerp(rsAurora, rsYvonne, _RS_Index);

// 光照调制（Fresnel 路径）：阴影区域不显示色变
rsBlend *= clampedNdotL * shadowScene;

// LIGHTEN 混合（取亮）：只提亮，不影响暗部
finalColor = max(finalColor, rsBlend * _RS_Strength);
```

关键设计点：
- **LIGHTEN（取亮）混合**：`max(A, B)` 确保色变只增亮、不消减暗部，符合彩虹高光直觉
- **双 RS 贴图**：不同角色可以配置不同色谱预设，通过 `_RS_Index` 插值
- **双路径切换**：`RS_Model=0` 保留光照调制（近真实感），`RS_Model=1` 剥离光照调制（纯风格化固定亮度）

---

### 🖼️ 2.4 后处理调色（Tonemapping）

卡通渲染的光照输出通常在线性 HDR 空间，最终送往屏幕前需要经过一个 **Tonemapping** 步骤将 HDR 压缩到 LDR。选择合适的 Tone Curve 对最终画面的色调倾向影响极大——同一套 Shader，Reinhard 和 ACES 出来的颜色感受可能截然不同。

**Gran Turismo Tonemap（Hajime Uchimura，2016 CEDEC）**

GT Curve 将色调曲线分为三段：**Toe（幂曲线暗部）/ Linear（线性中间调）/ Shoulder（指数高光）**，三段用 smoothstep 权重平滑衔接，每段独立可控。

```hlsl
float GranTurismoTonemap(float x)
{
    float P = 1, a = 1, m = 0.22, l = 0.4, c = 1.33, b = 0;
    // P: 峰值白  a: 线性斜率  m: Toe/Linear 分界  l: 线性段宽  c: Toe 幂次

    float l0 = (P - m) * l / a;
    float S0 = m + l0,  S1 = m + a * l0,  C2 = a * P / (P - S1);

    float T_x = m * pow(x / m, c) + b;                         // Toe
    float L_x = m + a * (x - m);                               // Linear
    float S_x = P - (P - S1) * exp(-C2 * (x - S0) / P);       // Shoulder

    float w0 = 1 - smoothstep(0, m, x);
    float w2 = smoothstep(S0, S0, x);
    float w1 = 1 - w0 - w2;

    return T_x * w0 + L_x * w1 + S_x * w2;
}

// 逐通道应用（保留色相比例）
float3 GranTurismoTonemap3(float3 c) { return float3(GranTurismoTonemap(c.r), GranTurismoTonemap(c.g), GranTurismoTonemap(c.b)); }
```

**ACES / GT / Neutral 的选择**

| 方案 | 特点 | 卡通渲染适配性 |
|------|------|----------------|
| ACES | 对比强，高光偏蓝，暗部压得深 | 慎用，卡通阴影色块容易被压暗，Ramp 冷色偏移会变灰 |
| **GT Curve** | 分段可控，暗部柔和，高光自然收敛 | **推荐**，线性段宽、Toe 弯曲轻，Ramp 颜色保真度高 |
| Neutral | 接近线性，对比度克制，色相几乎不偏移 | 适合需要精准色彩还原的项目，画面对比感弱，需后期补对比 |

> **卡通渲染特别注意**：Ramp 阴影颜色是美术精心设计的色块，Tonemapping 对这些颜色的挤压程度直接影响最终效果。建议在实现 Ramp 时即在 Tonemapping 后的显示空间校对颜色，避免调 Shader 时看到的颜色和实机不符。

---

## 📝 三、总结

**· ⚖️ 混合策略平衡写实与风格化**
两种路径并非对立，混合策略才是当前主流。赛璐璐侧重平涂色块感，适合角色数量多、追求统一画风的项目；PBR Toon 侧重材质区分度与体积感，适合精品角色或写实场景中的卡通人物。终末地 PBRToonBase 就是典型混合案例：漫反射走 Toon 路径（SigmoidSharp + Ramp），高光走 PBR 路径（GGX + 能量守恒），Rim / ThinFilm 等风格化效果叠加在上层。卡通成分越重画面越平涂，PBR 成分越重体积感越强，两者构成一个可连续调节的风格谱系。

**· ⚠️ 前期对齐规范，规避自由度风险**
高自由度意味着，若项目初期没有明确美术风格定位，各角色各自为政地调整 PBR/Toon 比例，很容易导致跨角色阴影软硬度不统一、Ramp/Rim/Fresnel 颜色叠加时色相冲突，后期统一修正成本远高于前期约定。建议美术和 TA 在开发阶段共同确定核心参数基准值（阴影边缘软硬度、Ramp 色调倾向、Rim 强度范围），描边、边缘光、面部 SDF 阴影、视角色变等风格化技巧同样纳入统一规范，各角色在基准上微调而非独立设定。

**· 🗂️ 贴图规范与 DCC 所见即所得**
二次元渲染对贴图的依赖远比写实渲染复杂——SDF 贴图、Ramp 贴图、阴影偏移贴图、Rim 遮罩……每张都承载特定风格化意图，且许多需美术在 DCC 中直接绘制，无法纯参数化生成。项目初期须明确通道语义、分辨率、色彩空间与命名约定。更重要的是打通 DCC 与引擎的所见即所得：Ramp 在 Substance Painter 中调出的颜色经 Tonemapping 后可能面目全非，建议在 DCC 侧搭建与引擎一致的预览环境（Marmoset Toolbag / Substance 自定义 Shader），或提供引擎内实时调参工具，减少"提交→出图→修改"的往返成本。

---

*参考资料*
*终末地 PBRToonBase 节点分析：`docs/PBRToonBase_ToonRendering_Summary.md`*
*Rim Frame 详细分析：`docs/analysis/Frames/Frame009_Rim.md`*
*ThinFilmFilter 详细分析：`docs/analysis/Frames/Frame011_ThinFilmFilter.md`*
