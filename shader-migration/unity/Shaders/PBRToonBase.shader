// =============================================================================
// PBRToonBase.shader
// 概念性 Unity URP ShaderLab 包装
// 目的：供理解渲染流程使用，非可直接编译版本
// 溯源：docs/analysis/01_shader_arch.md
// 对应 HLSL：hlsl/PBRToonBase.hlsl
// =============================================================================

Shader "Goo/PBRToonBase"
{
    Properties
    {
        // -----------------------------------------------------------------------
        // 贴图
        // -----------------------------------------------------------------------
        [Header(Textures)]
        _D              ("Diffuse/Albedo (sRGB)",           2D) = "white" {}
        _N              ("Normal Map (Non-Color XY)",       2D) = "bump"  {}
        _P              ("Param Map (R=Metal G=AO B=Smooth A=RampUV)", 2D) = "white" {}
        _E              ("Emission Map",                    2D) = "black" {}
        _M              ("Mask Map (未使用)",                2D) = "white" {}
        _RampLUT        ("Toon Ramp LUT (5×N 竖向)",        2D) = "white" {}
        _FGD_LUT        ("Pre-Integrated FGD LUT",          2D) = "white" {}
        _ThinFilmLUT    ("ThinFilm / 彩虹 LUT",             2D) = "white" {}

        // -----------------------------------------------------------------------
        // 开关
        // -----------------------------------------------------------------------
        [Header(Switches)]
        [Toggle] _IsSkin                ("Is Skin?",                   Float) = 0
        [Toggle] _UseAnisotropy         ("Use Anisotropy?",            Float) = 0
        [Toggle] _UseToonAniso          ("Use Toon Aniso?",            Float) = 0
        [Toggle] _UseNormalTex          ("Use Normal Tex?",            Float) = 1
        [Toggle] _UseRSEff              ("Use RS_Eff?",                Float) = 0
        [Toggle] _UseSimpleTransmission ("Use Simple Transmission?",   Float) = 0
        _RSModel                        ("RS Model",                   Float) = 0

        // -----------------------------------------------------------------------
        // 粗糙度 / 金属度
        // -----------------------------------------------------------------------
        [Header(Roughness Metallic)]
        _SmoothnessMax          ("Smoothness Max",          Range(0,1)) = 1
        _Aniso_SmoothnessMaxT   ("Aniso Smoothness Max T",  Range(0,1)) = 0.5
        _Aniso_SmoothnessMaxB   ("Aniso Smoothness Max B",  Range(0,1)) = 0.5
        _MetallicMax            ("Metallic Max",            Range(0,1)) = 1

        // -----------------------------------------------------------------------
        // 阴影 / 漫反射
        // -----------------------------------------------------------------------
        [Header(Shadow Diffuse)]
        _RemaphalfLambert_center        ("HalfLambert Center",     Range(0,1)) = 0.5
        _RemaphalfLambert_sharp         ("HalfLambert Sharp",      Range(0,50)) = 5
        _CastShadow_center              ("CastShadow Center",      Range(0,1)) = 0.5
        _CastShadow_sharp               ("CastShadow Sharp",       Range(0,50)) = 5
        _RampIndex                      ("Ramp Index",             Range(0,4))  = 0
        _dirLight_lightColor            ("Dir Light Color",        Color) = (1,1,1,1)
        _directOcclusionColor           ("Direct Occlusion Color", Color) = (0,0,0,1)
        _AmbientLightColorTint          ("Ambient Light Tint",     Color) = (1,1,1,1)
        _GlobalShadowBrightnessAdjustment ("Shadow Brightness Adj", Range(0,1)) = 1
        _ColorDesaturationAttenuation   ("Shadow Desaturation",   Range(0,1)) = 0

        // -----------------------------------------------------------------------
        // 高光
        // -----------------------------------------------------------------------
        [Header(Specular)]
        _SpecularColor      ("Specular Color",          Color)      = (1,1,1,1)
        _NormalStrength     ("Normal Strength",         Range(0,2)) = 1
        _specularFGDStrength("Specular FGD Strength",  Range(0,2)) = 1

        // -----------------------------------------------------------------------
        // Fresnel / ToonFresnel
        // -----------------------------------------------------------------------
        [Header(Fresnel ToonFresnel)]
        _fresnelInsideColor     ("Fresnel Inside Color",  Color)       = (0,0,0,1)
        _fresnelOutsideColor    ("Fresnel Outside Color", Color)       = (1,1,1,1)
        _ToonfresnelPow         ("Toon Fresnel Pow",      Range(0,10)) = 5
        _ToonfresnelSMO_L       ("Toon Fresnel SMO Low",  Range(0,1))  = 0.3
        _ToonfresnelSMO_H       ("Toon Fresnel SMO High", Range(0,1))  = 0.7
        _LayerWeightValue       ("Layer Weight Value",    Range(0,2))  = 1
        _LayerWeightValueOffset ("Layer Weight Offset",   Range(-1,1)) = 0

        // -----------------------------------------------------------------------
        // Rim 边缘光
        // -----------------------------------------------------------------------
        [Header(Rim Light)]
        _Rim_DirLightAtten  ("Rim DirLight Atten",  Range(0,1)) = 0.2
        _Rim_width_X        ("Rim Width X",          Range(0,0.1)) = 0.01
        _Rim_width_Y        ("Rim Width Y",          Range(0,0.1)) = 0.01
        _Rim_Color          ("Rim Color",            Color)        = (1,1,1,1)
        _Rim_ColorStrength  ("Rim Color Strength",   Range(0,5))   = 1

        // -----------------------------------------------------------------------
        // RS 特效
        // -----------------------------------------------------------------------
        [Header(RS Effect)]
        _RS_Index       ("RS Index",         Float)      = 0
        _RS_Strength    ("RS Strength",      Range(0,2)) = 1
        _RS_MultiplyValue ("RS Multiply",    Range(0,2)) = 1
        _RS_ColorTint   ("RS Color Tint",    Color)      = (1,1,1,1)

        // -----------------------------------------------------------------------
        // 其他
        // -----------------------------------------------------------------------
        [Header(Other)]
        _Alpha                  ("Alpha",                  Range(0,1)) = 1
        _AnisotropicMask        ("Anisotropic Mask",       Range(0,1)) = 1
        _SimpleTransmissionValue ("Simple Transmission",  Range(0,1)) = 0
        _RS_Index2              ("RS Index2",              Float)      = 0
    }

    SubShader
    {
        // -------------------------------------------------------------------
        // Pass 0 — ForwardLit（主渲染 Pass）
        // -------------------------------------------------------------------
        Tags
        {
            "RenderPipeline"  = "UniversalPipeline"
            "RenderType"      = "Transparent"
            "Queue"           = "Transparent"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            // 半透明混合
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM

            // URP 必要宏
            #pragma vertex   PBRToonBase_Vert
            #pragma fragment PBRToonBase_Frag

            // URP 变体关键字
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fog

            // 引入 URP 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 顶点输入（补充 Attributes 结构）
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
            };

            // 主 HLSL 逻辑
            #include "../../hlsl/PBRToonBase.hlsl"

            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Pass 1 — ShadowCaster（投影阴影 Pass，URP 标准写法）
        // -------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma vertex   ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Pass 2 — DepthOnly（深度预通 Pass，供 DepthRim 等屏幕效果使用）
        // -------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }

    // -------------------------------------------------------------------
    // 回退 Shader（不支持 URP 时）
    // -------------------------------------------------------------------
    FallBack "Hidden/Universal Render Pipeline/FallbackError"

    // -------------------------------------------------------------------
    // 自定义编辑器（可选，供 Material Inspector 使用）
    // -------------------------------------------------------------------
    // CustomEditor "PBRToonBaseGUI"
}
