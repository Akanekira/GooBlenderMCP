# 00 — 材质概览：M_actor_laevat_iris_01

> 主节点群：`Arknights: Endfield_PBRToon_irisBase`
> 提取日期：20260302 | 溯源：`docs/raw_data/Arknights__Endfield_PBRToon_irisBase_20260302.json`
> 相关文件：`hlsl/M_actor_laevat_iris_01/PBRToon_irisBase_Input.hlsl` | `hlsl/M_actor_laevat_iris_01/PBRToon_irisBase.hlsl` | `unity/Shaders/PBRToon_irisBase.shader`

---

## 材质定性

`PBRToon_irisBase` 是一个**纯自发光（Emission-only）** 虹膜高光着色器。它不执行任何 PBR 或 Toon 光照计算，而是以 `Emission` 节点输出为最终结果，供外部 ADD_SHADER 叠加到虹膜基础 BSDF 上。

核心思路：
- 利用角色**骨骼坐标轴属性**（headUp / headRight / headForward）计算光照角度
- 使用 **Matcap 贴图**（视空间法线 UV 采样）提供镜面感高光
- 光照角度阈值控制高光亮度，D_Alpha 控制高光遮罩

---

## 群组规模

| 指标 | 数量 |
|------|------|
| 总节点数 | 25 |
| 连线数 | 29 |
| 顶级 Frame 数 | 0（无 Frame 结构，节点完全平铺） |
| 子群组调用数 | 1（1 个唯一群组：`calculateAngel`） |

---

## 贴图输入

本群组**不直接引用外部 _D / _N / _P 贴图**，仅通过群组接口接收外部采样结果。

| 内部纹理槽 | 贴图名 | 语义 |
|-----------|--------|------|
| `图像纹理.001` | `T_actor_common_matcap_05_D.png` | 主 Matcap 高光（视空间法线采样） |
| `图像纹理.002` | `T_actor_common_matcap_07_D.png` | 辅助 Matcap 高光（固定强度 0.7 叠加） |

两个贴图使用相同的 Matcap UV（世界法线→相机空间 → `*0.5+0.5`）。

---

## 群组接口输入（参数）

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `D_RGB` | Color（RGBA） | 虹膜 Diffuse 颜色（由外部材质采样 _D 贴图后传入） |
| `D_Alpha` | Float | 虹膜遮罩（_D 贴图 Alpha 通道），控制亮度混合权重 |
| `Eyes brightness` | Float | 眼睛基础亮度（光照角不达标时的最低强度） |
| `Eyes HightLight brightness` | Float | 眼睛高光峰值亮度（光照角达标时的最大强度倍率） |

---

## 几何属性输入（Geometry Attribute）

本群组通过 `ATTRIBUTE` 节点读取网格几何属性（由骨骼控制器写入）：

| 属性名 | 类型 | 说明 |
|--------|------|------|
| `LightDirection` | Vector | 主光源方向（世界空间，by vertex attribute） |
| `headUp` | Vector | 头部向上轴（世界空间骨骼坐标） |
| `headRight` | Vector | 头部向右轴（世界空间骨骼坐标） |
| `headForward` | Vector | 头部前向轴（世界空间骨骼坐标） |

---

## 输出

| 输出名 | 类型 | 说明 |
|--------|------|------|
| `Emission` | Shader | 虹膜高光自发光（合并两个 EMISSION 节点之后输出） |

本群组输出的是 Shader 类型，供外部使用 `ADD_SHADER` 与虹膜主着色器叠加。

---

## 子群组列表

| 子群组 | 状态 | 文档 |
|--------|------|------|
| `calculateAngel` | **新增** | `docs/analysis/sub_groups/calculateAngel.md` |
