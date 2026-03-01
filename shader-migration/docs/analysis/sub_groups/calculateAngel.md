# calculateAngel

> 溯源：`docs/raw_data/calculateAngel_20260302.json` | 节点数：30
> HLSL 实现：`hlsl/M_actor_laevat_iris_01/SubGroups/SubGroups.hlsl` — `CalculateAngleThreshold()` 函数
> 首次引用：`M_actor_laevat_iris_01` / `Arknights: Endfield_PBRToon_irisBase`

---

## 接口

| 方向 | 名称 | 类型 | 说明 |
|------|------|------|------|
| 输入 | `LightDirection` | Vector | 主光源方向（世界空间，来自几何属性） |
| 输入 | `headUp` | Vector | 头部向上轴（世界空间骨骼坐标） |
| 输入 | `headRight` | Vector | 头部向右轴（世界空间骨骼坐标） |
| 输入 | `headForward` | Vector | 头部前向轴（世界空间骨骼坐标） |
| 输出 | `AngleThreshold` | Float | 光源相对头部水平旋转角度（映射到 [0,1] 区间） |
| 输出 | `Flip threshold` | Float | = `sX`（光源在头部坐标系中的左右分量，用于高光翻转判断） |

---

## 内部 Frame 结构

| Frame 标签 | 内容节点 | 作用 |
|-----------|----------|------|
| `lightDirectionProjHeadWS` | VecMath.011（NORMALIZE）及相关转接点 | 光源方向在头部水平面的投影（归一化） |
| `sZ` | VecMath.020（DOT），转接点.008 | dot(-headForward, L_hor_norm) = 前后分量 |
| `sX` | VecMath.017（DOT），转接点.006 | dot(headRight, L_hor_norm) = 左右分量 |
| `angleThreshold` | 运算.003-007，混合.001，转接点.019 | atan2 计算与角度区间映射 |
| `Flip threshold` | 转接点.113 | 输出 sX 作为翻转参考 |

---

## 内部节点

| 节点 | 操作 | 输入 | 作用 |
|------|------|------|------|
| `Vector Math.008` | DOT_PRODUCT | LightDirection, headUp | `sY = dot(L, headUp)`（光源垂直分量） |
| `Vector Math.009` | MULTIPLY | headUp, sY | `sY_proj = headUp × sY`（垂直投影向量） |
| `Vector Math.010` | SUBTRACT | LightDirection, sY_proj | `L_hor = L - sY_proj`（水平投影，去掉垂直分量） |
| `Vector Math.011` | NORMALIZE | L_hor | `L_hor_norm = normalize(L_hor)` |
| `值(明度)` | VALUE | -1.0 | 用于翻转 headForward |
| `Vector Math.019` | MULTIPLY | headForward, -1.0 | `-headForward` |
| `Vector Math.020` | DOT_PRODUCT | -headForward, L_hor_norm | `sZ = dot(-headForward, L_hor_norm)` |
| `Vector Math.017` | DOT_PRODUCT | headRight, L_hor_norm | `sX = dot(headRight, L_hor_norm)` |
| `运算.003` | ARCTAN2 | sX, sZ | `angle = atan2(sX, sZ)` |
| `运算.004` | DIVIDE | angle, π | `angle_norm = angle / π ∈ [-1, 1]` |
| `运算.005` | GREATER_THAN | angle_norm, 0.0 | `isPositive = angle_norm > 0` |
| `运算.006` | ADD | angle_norm, 1.0 | `angle_norm + 1`（负角映射到正区间） |
| `运算.007` | SUBTRACT | angle_norm, 1.0 | `angle_norm - 1`（正角映射，备用） |
| `混合.001` | MIX FLOAT | Factor=isPositive, A=angle_norm+1, B=angle_norm-1 | 区间映射选择器 |

---

## 计算流程

```
LightDirection, headUp, headRight, headForward
    ↓
Step 1: sY = dot(L, headUp)                       # 光源的垂直分量
Step 2: L_hor = L - headUp * sY                   # 水平投影（去掉垂直分量）
Step 3: L_hor_norm = normalize(L_hor)             # 归一化水平方向
    ↓
Step 4: sX = dot(headRight, L_hor_norm)           # 左右分量 → Frame.sX
Step 5: sZ = dot(-headForward, L_hor_norm)        # 前后分量 → Frame.sZ
    ↓
Step 6: angle = atan2(sX, sZ)                     # 头部水平坐标系内光源方位角
Step 7: angle_norm = angle / π                    # 归一化到 [-1, 1]
    ↓
Step 8: if angle_norm <= 0:
            AngleThreshold = angle_norm + 1.0     # [-1,0] → [0,1]
        else:
            AngleThreshold = angle_norm - 1.0     # (0,1] → (-1,0]
    ↓
Flip threshold = sX                               # 左右分量，供外部翻转判断
```

---

## 等价公式

设光源世界空间方向为 **L**，骨骼坐标轴为 **U**（up）、**R**（right）、**F**（forward）：

```
L_hor = L - (L·U) × U                       — 光源水平投影
L_norm = normalize(L_hor)                   — 归一化
sX = dot(R, L_norm)                         — 左右分量
sZ = dot(-F, L_norm)                        — 前后分量
θ  = atan2(sX, sZ)  ∈ (-π, π]              — 水平方位角
θ' = θ / π          ∈ (-1, 1]              — 归一化
AngleThreshold = θ' + sign(θ' ≤ 0) × 1.0   — 区间映射
```

**映射结果**：光源位于头部正侧面或后侧时（`θ' ≈ -1` 或 `+1`）→ AngleThreshold ≈ 0；
光源位于头部正前方时（`θ' ≈ 0`）→ AngleThreshold ≈ 1（但因 GREATER_THAN 分支切换，实际会回绕）。

> **注意**：此映射不连续，在 θ=0 处存在区间切换（混合.001 Factor 由 0→1 跳变）。这是一种将循环角度映射到线性范围的 trick，具体哪个区间对应最大亮度取决于骨骼坐标系约定。

---

## HLSL 等价

```hlsl
// --- calculateAngel ---
// 计算光源相对于角色头部坐标系的水平方位角（用于虹膜高光角度控制）

struct AngleThresholdResult
{
    float AngleThreshold;  // 光源水平方位角映射值，供外部 CLAMP 使用
    float FlipThreshold;   // = sX，光源左右分量（正=右侧光）
};

AngleThresholdResult CalculateAngleThreshold(
    float3 lightDirection,   // 主光源方向（世界空间）
    float3 headUp,           // 头部向上轴（世界空间骨骼坐标）
    float3 headRight,        // 头部向右轴（世界空间骨骼坐标）
    float3 headForward       // 头部前向轴（世界空间骨骼坐标）
)
{
    AngleThresholdResult result;

    // Step 1-3: 光源水平投影
    float  sY         = dot(lightDirection, headUp);
    float3 L_hor      = lightDirection - headUp * sY;
    float3 L_hor_norm = normalize(L_hor);

    // Step 4-5: 头部坐标系分量
    float sX = dot(headRight, L_hor_norm);                  // 左右分量
    float sZ = dot(-headForward, L_hor_norm);               // 前后分量

    // Step 6-8: 方位角计算与区间映射
    float angle      = atan2(sX, sZ);
    float angleNorm  = angle / 3.14159265;                  // [-1, 1]
    float isPositive = angleNorm > 0.0 ? 1.0 : 0.0;

    float angleA = angleNorm + 1.0;                         // 负角区间 → [0, 1]
    float angleB = angleNorm - 1.0;                         // 正角区间 → (-1, 0]

    result.AngleThreshold = lerp(angleA, angleB, isPositive);
    result.FlipThreshold  = sX;

    return result;
}
```

---

## 备注

- **无对应 HDRP/URP 标准函数**：这是专为角色虹膜高光设计的自定义算法，在标准渲染管线中没有现成等价函数。
- **骨骼数据传递**：Unity 中没有 Blender 几何属性机制。需要通过自定义 `MaterialPropertyBlock` 或顶点 attribute（从 `SkinnedMeshRenderer` 骨骼矩阵提取）将这四个向量传入 shader。
- **atan2 坐标约定**：`atan2(sX, sZ)` 而非 `atan2(sZ, sX)`，注意参数顺序。
- **`Flip threshold` 在本材质中未使用**：输出 sX 为后续其他材质预留接口。

---

## 待确认

- [ ] AngleThreshold 区间映射的意图：哪个角度范围映射到最高亮度（接近 1.0）？需要结合外层 `SUBTRACT(-0.5)` + `CLAMP(0.5, 1.0)` 确认有效角度窗口。
- [ ] 骨骼坐标系约定：`headForward` 是角色面朝方向还是从角色看出的方向？影响 sZ 的符号。
