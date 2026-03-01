// =============================================================================
// PBRToon_irisBase.hlsl
// 虹膜高光材质 — 主着色函数（按数据流分支顺序组装）
// 溯源：docs/analysis/M_actor_laevat_iris_01/01_shader_arch.md
// 注：伪代码级 HLSL，供理解渲染流程使用
//
// 架构说明：
//   本群组为纯 Emission-only 着色器，无 Frame 层级。
//   输出为 Emission 颜色（float4），供外部以 Additive 方式叠加到虹膜基础 BSDF 上。
//   对应 Blender 节点：ADD_SHADER → GROUP_OUTPUT.Emission
// =============================================================================

#include "PBRToon_irisBase_Input.hlsl"
#include "SubGroups/SubGroups.hlsl"

// =============================================================================
// GetMatcapUV — Matcap UV 计算
// 对应节点：纹理坐标 → 矢量变换(World→Camera) → 矢量运算(×0.5) → 矢量运算.001(+0.5)
// =============================================================================
float2 GetMatcapUV(float3 normalWS)
{
    // 世界空间法线转换到相机空间
    float3 normalCS = TransformWorldToViewDir(normalWS, true); // 矢量变换 World→Camera VECTOR
    // Matcap UV 标准映射: N_cam * 0.5 + 0.5 (仅 XY 分量)
    float2 matcapUV = normalCS.xy * 0.5 + 0.5;               // 矢量运算 MULTIPLY + ADD
    return matcapUV;
}

// =============================================================================
// GetIrisSurfaceData — 表面数据采样
// =============================================================================
IrisSurfaceData GetIrisSurfaceData(Varyings input)
{
    IrisSurfaceData sd;

    // 群组接口输入（由外部材质传入）
    sd.irisColor = _IrisColor.rgb;   // 群组输入 D_RGB
    sd.irisAlpha = _IrisAlpha;       // 群组输入 D_Alpha

    // Matcap UV
    sd.matcapUV = GetMatcapUV(normalize(input.normalWS));

    // 采样两张 Matcap 贴图（图像纹理.001 / .002）
    sd.matcapMain = SAMPLE_TEXTURE2D(_MatcapMain, sampler_MatcapMain, sd.matcapUV).rgb;
    sd.matcapSub  = SAMPLE_TEXTURE2D(_MatcapSub,  sampler_MatcapSub,  sd.matcapUV).rgb;

    return sd;
}

// =============================================================================
// PBRToon_irisBase_Frag — 主片元着色函数
// 输出：虹膜高光 Emission 颜色（用于 Additive 叠加）
// =============================================================================
float4 PBRToon_irisBase_Frag(Varyings input) : SV_Target
{
    IrisSurfaceData sd = GetIrisSurfaceData(input);

    // -------------------------------------------------------------------------
    // 分支 A — 角度阈值
    // 对应节点：属性×4 → calculateAngel → 运算(SUBTRACT) → 钳制(CLAMP) → 混合(MIX MULTIPLY)
    // -------------------------------------------------------------------------
    AngleThresholdResult angleResult = CalculateAngleThreshold(
        _LightDirection,
        _HeadUp,
        _HeadRight,
        _HeadForward
    );

    // 运算 (SUBTRACT): AngleThreshold - 0.5
    float angleShifted = angleResult.AngleThreshold - 0.5;

    // 钳制 (CLAMP, min=0.5, max=1.0)
    float angleClamp = clamp(angleShifted, 0.5, 1.0);

    // 混合 (MIX RGBA MULTIPLY, A=D_RGB, B=angleClamp)
    // 角度权重调制虹膜颜色（float → RGBA 广播为灰色）
    float3 angle_iris = sd.irisColor * angleClamp;  // MULTIPLY blend, factor=1.0

    // -------------------------------------------------------------------------
    // 分支 B — Matcap UV 与主高光
    // 对应节点：TEX_COORD → VECT_TRANSFORM → VECT_MATH×2 → TEX_IMAGE.001 → 混合.003 → 混合.002
    // -------------------------------------------------------------------------

    // 混合.003 (MIX RGBA MULTIPLY, A=matcap_05, B=D_RGB): Matcap 以虹膜颜色着色
    float3 matcap_tinted = sd.matcapMain * sd.irisColor;    // factor=1.0 MULTIPLY

    // 混合.002 (MIX RGBA ADD, factor=0.567, A=angle_iris, B=matcap_tinted)
    // lerp(A, A+B, factor) = A + B * factor  (ADD blend mode)
    float3 main_color = angle_iris + matcap_tinted * _MatcapBlendFactor;

    // -------------------------------------------------------------------------
    // 分支 D — 亮度控制
    // 对应节点：运算.001(MULTIPLY) → 混合.001(MIX FLOAT) → 自发光(发射)
    // -------------------------------------------------------------------------

    // 运算.001 (MULTIPLY): (AngleThreshold - 0.5) * Eyes_HightLight_brightness
    float angle_strength = angleShifted * _EyesHighlightBrightness;

    // 混合.001 (MIX FLOAT, Factor=D_Alpha, A=Eyes_brightness, B=angle_strength)
    float emission_strength = lerp(_EyesBrightness, angle_strength, sd.irisAlpha);

    // 自发光(发射) EMISSION: Color=main_color, Strength=emission_strength
    float3 emission_main = main_color * emission_strength;  // Emission = color × strength

    // -------------------------------------------------------------------------
    // 分支 C — 辅助 Matcap 高光（固定层）
    // 对应节点：图像纹理.002 → 自发光(Strength=0.7)
    // -------------------------------------------------------------------------
    float3 emission_sub = sd.matcapSub * _MatcapSubStrength; // Strength=0.7

    // -------------------------------------------------------------------------
    // 相加着色器 (ADD_SHADER) → GROUP_OUTPUT.Emission
    // -------------------------------------------------------------------------
    float3 finalEmission = emission_main + emission_sub;

    return float4(finalEmission, 1.0);
}

// =============================================================================
// PBRToon_irisBase_Vert — 顶点着色函数
// =============================================================================
Varyings PBRToon_irisBase_Vert(Attributes input)
{
    Varyings output;

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs   normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.positionCS = vertexInput.positionCS;
    output.positionWS = vertexInput.positionWS;
    output.normalWS   = normalInput.normalWS;
    output.uv         = input.uv0;

    return output;
}
