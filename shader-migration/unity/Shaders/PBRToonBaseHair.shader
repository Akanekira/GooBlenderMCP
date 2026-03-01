// =============================================================================
// PBRToonBaseHair.shader
// 概念性 Unity URP ShaderLab 包装 — M_actor_laevat_hair_01
// 目的：供理解渲染流程使用，非可直接编译版本
// 溯源：docs/analysis/M_actor_laevat_hair_01/01_shader_arch.md
// 对应 HLSL：hlsl/M_actor_laevat_hair_01/PBRToonBaseHair.hlsl
// =============================================================================

Shader "Goo/PBRToonBaseHair"
{
    Properties
    {
        // -----------------------------------------------------------------------
        // 贴图
        // -----------------------------------------------------------------------
        [Header(Textures)]
        _D              ("Diffuse/Albedo (sRGB) RGB=Hair Color A=Alpha",        2D) = "white" {}
        _HN             ("Hair Normal (Non-Color) RGB=TangentDir A=Reserved",   2D) = "bump"  {}
        _P              ("Param Map (Non-Color) R=Metal G=AO B=Smooth A=RampUV",2D) = "white" {}
        _HairRampTex    ("Hair Ramp LUT (T_actor_common_hair_01_RD)",           2D) = "white" {}
        _FGD_LUT        ("Pre-Integrated FGD LUT",                              2D) = "white" {}

        // -----------------------------------------------------------------------
        // 开关
        // -----------------------------------------------------------------------
        [Header(Switches)]
        [Toggle] _UseFusionFaceColor    ("Use Fusion Face Color?",  Float) = 0
        [Toggle] _UseRimLimitation      ("Use Rim Limitation?",     Float) = 0

        // -----------------------------------------------------------------------
        // 基础颜色
        // -----------------------------------------------------------------------
        [Header(Base Color)]
        _BaseColor              ("Base Color",              Color)       = (1,1,1,1)
        _FusionFaceColor        ("Fusion Face Color",       Color)       = (1,1,1,1)

        // -----------------------------------------------------------------------
        // 粗糙度 / 金属度
        // -----------------------------------------------------------------------
        [Header(Roughness Metallic)]
        _SmoothnessMax          ("Smoothness Max",          Range(0,1))  = 1.0
        _MetallicMax            ("Metallic Max",            Range(0,1))  = 1.0

        // -----------------------------------------------------------------------
        // 法线
        // -----------------------------------------------------------------------
        [Header(Normal)]
        _NormalStrength         ("Normal Strength",         Range(0,2))  = 1.0
        _HNormalStrength        ("Hair Normal Strength",    Range(0,2))  = 1.0

        // -----------------------------------------------------------------------
        // 阴影 / 漫反射
        // -----------------------------------------------------------------------
        [Header(Shadow Diffuse)]
        _RemapHalfLambertCenter ("HalfLambert Center",      Range(0,1))  = 0.5
        _RemapHalfLambertSharp  ("HalfLambert Sharp",       Range(0,50)) = 5.0
        _CastShadowCenter       ("CastShadow Center",       Range(0,1))  = 0.5
        _CastShadowSharp        ("CastShadow Sharp",        Range(0,50)) = 5.0
        _GlobalShadowBrightness ("Shadow Brightness Adj",   Range(0,2))  = 1.0
        _DirLightColor          ("Dir Light Color",         Color)       = (1,1,1,1)
        _DirectOcclusionColor   ("Direct Occlusion Color",  Color)       = (0,0,0,1)
        _ColorDesatInShadow     ("Shadow Color Desaturation", Range(0,1)) = 0.0

        // -----------------------------------------------------------------------
        // 高光
        // -----------------------------------------------------------------------
        [Header(Specular)]
        _SpecularColor          ("Specular Color",          Color)       = (1,1,1,1)

        // -----------------------------------------------------------------------
        // Fresnel / ToonFresnel
        // -----------------------------------------------------------------------
        [Header(Fresnel ToonFresnel)]
        _FresnelInsideColor     ("Fresnel Inside Color",    Color)       = (1,1,1,1)
        _FresnelOutsideColor    ("Fresnel Outside Color",   Color)       = (1,1,1,1)
        _ToonFresnelPow         ("ToonFresnel Pow",         Range(0,10)) = 4.0
        _ToonFresnelSMO_L       ("ToonFresnel SMO L",       Range(0,1))  = 0.4
        _ToonFresnelSMO_H       ("ToonFresnel SMO H",       Range(0,1))  = 0.6

        // -----------------------------------------------------------------------
        // Rim Light
        // -----------------------------------------------------------------------
        [Header(Rim Light)]
        _RimColor               ("Rim Color",               Color)       = (1,1,1,1)
        _RimColorStrength       ("Rim Color Strength",      Range(0,5))  = 1.0
        _RimDirLightAtten       ("Rim Dir Light Atten",     Range(0,1))  = 0.5
        _RimWidthX              ("Rim Width X",             Range(0,1))  = 0.3
        _RimWidthY              ("Rim Width Y",             Range(0,1))  = 0.3

        // -----------------------------------------------------------------------
        // 发丝各向异性高光（Hair Anisotropic Highlight）
        // -----------------------------------------------------------------------
        [Header(Hair Anisotropic Highlight)]
        _HighLightColorA        ("HighLight Color A",           Color)       = (1,1,1,1)
        _HighLightColorB        ("HighLight Color B",           Color)       = (0.8,0.8,0.8,1)
        _FHighLightPos          ("HighLight Pos Offset",        Range(-1,1)) = 0.0
        _HighlightLength        ("Highlight Length",            Range(0,2))  = 0.5
        _FinalBrightness        ("Final Brightness",            Range(0,5))  = 1.0
        _HairHLColorLerpSMOMin  ("HL Color Lerp SMO Min",       Range(0,1))  = 0.2
        _HairHLColorLerpSMOMax  ("HL Color Lerp SMO Max",       Range(0,1))  = 0.8
        _HairHLColorLerpSMOOffset ("HL Color Lerp SMO Offset",  Range(-1,1)) = 0.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Transparent"
            "Queue"          = "Transparent"
        }

        // -----------------------------------------------------------------------
        // Pass 1: ForwardLit — 主渲染
        // -----------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            // 半透明混合（发丝透明）
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off    // 双面渲染，发丝需要

            HLSLPROGRAM
            #pragma vertex   PBRToonBaseHair_Vert
            #pragma fragment PBRToonBaseHair_Frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "../../hlsl/M_actor_laevat_hair_01/PBRToonBaseHair.hlsl"
            ENDHLSL
        }

        // -----------------------------------------------------------------------
        // Pass 2: ShadowCaster — 投影阴影
        // -----------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex   ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // -----------------------------------------------------------------------
        // Pass 3: DepthOnly — 深度预通
        // 供 DepthRim 子群组采样 _CameraDepthTexture
        // -----------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex   DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"

    // -----------------------------------------------------------------------
    // 自定义 Inspector（概念示意，引用 Unity Editor 标准 ShaderGUI）
    // -----------------------------------------------------------------------
    // CustomEditor "UnityEditor.Rendering.Universal.ShaderGUI.LitShader"
}
