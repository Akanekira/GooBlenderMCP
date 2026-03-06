// =============================================================================
// PBRToonBaseFace.shader
// 概念性 Unity URP ShaderLab 包装 — 面部着色器
// 目的：供理解渲染流程使用，非可直接编译版本
// 溯源：docs/analysis/Materials/M_actor_pelica_face_01/01_shader_arch.md
// 对应 HLSL：hlsl/M_actor_pelica_face_01/PBRToonBaseFace.hlsl
// =============================================================================

Shader "Goo/PBRToonBaseFace"
{
    Properties
    {
        // -----------------------------------------------------------------------
        // 贴图
        // -----------------------------------------------------------------------
        [Header(Textures)]
        _D              ("Diffuse/Albedo (sRGB)",                      2D) = "white" {}
        _P              ("Param Map (R=Metal G=AO B=Smooth)",          2D) = "white" {}
        _SDF            ("SDF Shadow Map (Non-Color)",                 2D) = "white" {}
        _ChinMask       ("Chin Mask (Non-Color)",                      2D) = "black" {}
        _HighlightMask  ("Face Highlight Mask (hl_M)",                 2D) = "black" {}
        _RampLUT        ("Toon Ramp LUT",                              2D) = "white" {}
        _FGD_LUT        ("Pre-Integrated FGD LUT",                     2D) = "white" {}
        _CustomMask     ("Custom Mask (Screen Rim)",                   2D) = "white" {}
        _CustomMask2    ("Custom Mask 2",                              2D) = "white" {}

        // -----------------------------------------------------------------------
        // 粗糙度 / 金属度
        // -----------------------------------------------------------------------
        [Header(Roughness Metallic)]
        _SmoothnessMax      ("Smoothness Max",          Range(0,1)) = 1
        _MetallicMax        ("Metallic Max",            Range(0,1)) = 1

        // -----------------------------------------------------------------------
        // 阴影 / SDF
        // -----------------------------------------------------------------------
        [Header(Shadow SDF)]
        _SDF_RemaphalfLambert_center    ("SDF HalfLambert Center",  Range(0,1))  = 0.57
        _SDF_RemaphalfLambert_sharp     ("SDF HalfLambert Sharp",   Range(0,50)) = 0.16
        _chin_RemaphalfLambert_center   ("Chin HalfLambert Center", Range(0,1))  = 0
        _chin_RemaphalfLambert_sharp    ("Chin HalfLambert Sharp",  Range(0,50)) = 0
        _CastShadow_center             ("CastShadow Center",       Range(0,1))  = 0
        _CastShadow_sharp              ("CastShadow Sharp",        Range(0,50)) = 0
        _GlobalShadowBrightnessAdjustment ("Shadow Brightness Adj", Range(0,1)) = 0
        _ColorDesaturationAttenuation   ("Shadow Desaturation",     Range(0,1)) = 1

        // -----------------------------------------------------------------------
        // 光照
        // -----------------------------------------------------------------------
        [Header(Lighting)]
        _dirLight_lightColor    ("Dir Light Color",     Color) = (1,1,1,1)
        _AmbientLightColorTint  ("Ambient Light Tint",  Color) = (1,1,1,1)

        // -----------------------------------------------------------------------
        // 高光
        // -----------------------------------------------------------------------
        [Header(Specular)]
        _SpecularColor          ("Specular Color (HDR)",    Color)      = (3.0, 1.46, 1.34, 1)
        _specularFGDStrength    ("Specular FGD Strength",   Range(0,2)) = 1

        // -----------------------------------------------------------------------
        // 面部特有
        // -----------------------------------------------------------------------
        [Header(Face)]
        _sphereNormal_Strength  ("Sphere Normal Strength",  Range(0,1))  = 0
        _FrontRColor            ("Front R Color (SSS)",     Color)       = (0,0,0,1)
        _FrontRPow              ("Front R Pow",             Range(0,10)) = 2
        _FrontRSmo              ("Front R Smo",             Range(0,1))  = 0
        _nose_shadow_Color      ("Nose Shadow Color",       Color)       = (0,0,0,1)
        _FaceFinalBrightness    ("Face Final Brightness",   Range(0,3))  = 1.15
        _EyesWhiteFinalBrightness ("Eyes White Brightness", Range(0,3))  = 1.3
        _LipsHighlightColor     ("Lips Highlight Color",    Color)       = (0,0,0,1)

        // -----------------------------------------------------------------------
        // Rim
        // -----------------------------------------------------------------------
        [Header(Rim Light)]
        _Rim_Color              ("Rim Color",               Color) = (1,1,1,1)
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

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM

            #pragma vertex   PBRToonBaseFace_Vert
            #pragma fragment PBRToonBaseFace_Frag

            // URP 变体关键字
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            // URP 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 顶点输入
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
            };

            // 主 HLSL 逻辑
            #include "../../hlsl/M_actor_pelica_face_01/PBRToonBaseFace.hlsl"

            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Pass 1 — ShadowCaster（投影阴影 Pass）
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
        // Pass 2 — DepthOnly（深度预通 Pass）
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

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
