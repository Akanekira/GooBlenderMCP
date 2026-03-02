// =============================================================================
// PBRToonBase_Cloth05.shader
// 概念性 Unity URP ShaderLab — M_actor_laevat_cloth_05
// 溯源：docs/analysis/M_actor_laevat_cloth_05/01_shader_arch.md
// 对应 HLSL：hlsl/M_actor_laevat_cloth_05/PBRToonBase_Cloth05.hlsl
// 注：非可直接编译版本，供理解渲染流程使用
//
// 与 PBRToonBase.shader（pelica_cloth_04）的差异：
//   - _M 贴图从"未使用"改为实际接入（T_actor_laevat_cloth_03_M.png）
//   - _E 贴图保留声明但默认为 black（未连线）
//   - 默认参数值更新为本材质实际值
//   - RS Effect 组增加 _M 遮罩说明
// =============================================================================

Shader "Goo/PBRToonBase_Cloth05"
{
    Properties
    {
        // -----------------------------------------------------------------------
        // 贴图（laevat_cloth_05 实际资产）
        // -----------------------------------------------------------------------
        [Header(Textures)]
        _D              ("Diffuse/Albedo (sRGB) — laevat_cloth_02_D",     2D) = "white" {}
        _N              ("Normal Map (Non-Color XY) — laevat_cloth_02_N", 2D) = "bump"  {}
        _P              ("Param (R=Metal G=AO B=Smooth A=RampUV) — laevat_cloth_02_P", 2D) = "white" {}
        _E              ("Emission Map — 未连线（保留声明）",               2D) = "black" {}
        _M              ("Mask Map — laevat_cloth_03_M（经SmoothStep送入_M槽）", 2D) = "white" {}
        _RampLUT        ("Toon Ramp LUT (5×N 竖向)",                       2D) = "white" {}
        _FGD_LUT        ("Pre-Integrated FGD LUT",                         2D) = "white" {}
        _ThinFilmLUT    ("ThinFilm / 彩虹 LUT",                            2D) = "white" {}

        // -----------------------------------------------------------------------
        // 开关（本材质实际值）
        // -----------------------------------------------------------------------
        [Header(Switches)]
        [Toggle] _IsSkin                ("Is Skin?",                   Float) = 0
        [Toggle] _UseAnisotropy         ("Use Anisotropy?",            Float) = 1
        [Toggle] _UseToonAniso          ("Use Toon Aniso?",            Float) = 1
        [Toggle] _UseNormalTex          ("Use Normal Tex?",            Float) = 1
        [Toggle] _UseRSEff              ("Use RS_Eff?",                Float) = 1
        [Toggle] _UseSimpleTransmission ("Use Simple Transmission?",   Float) = 0
        _RSModel                        ("RS Model",                   Float) = 1

        // -----------------------------------------------------------------------
        // 粗糙度 / 金属度（各向异性参数，布料特征值）
        // -----------------------------------------------------------------------
        [Header(Roughness Metallic)]
        _SmoothnessMax          ("Smoothness Max",          Range(0,1)) = 1.0
        _Aniso_SmoothnessMaxT   ("Aniso Smoothness Max T", Range(0,1)) = 0.2197
        // ↑ 切线方向较粗糙（0.22），产生沿切线方向扩散的高光
        _Aniso_SmoothnessMaxB   ("Aniso Smoothness Max B", Range(0,1)) = 0.6689
        // ↑ 副切线方向较光滑（0.67），高光在副切线方向更集中
        _MetallicMax            ("Metallic Max",           Range(0,1)) = 1.0

        // -----------------------------------------------------------------------
        // 阴影 / 漫反射
        // -----------------------------------------------------------------------
        [Header(Shadow Diffuse)]
        _RemaphalfLambert_center        ("HalfLambert Center",     Range(0,1))  = 0.570
        _RemaphalfLambert_sharp         ("HalfLambert Sharp",      Range(0,50)) = 0.180
        _CastShadow_center              ("CastShadow Center",      Range(0,1))  = 0.0
        _CastShadow_sharp               ("CastShadow Sharp",       Range(0,50)) = 0.170
        _RampIndex                      ("Ramp Index",             Range(0,4))  = 0.0
        _dirLight_lightColor            ("Dir Light Color",        Color) = (1,1,1,1)
        _directOcclusionColor           ("Direct Occlusion Color", Color) = (0,0,0,1)
        _AmbientLightColorTint          ("Ambient Light Tint",     Color) = (1,1,1,1)
        _GlobalShadowBrightnessAdjustment ("Shadow Brightness Adj", Range(-3,1)) = -1.800
        // ↑ 较深的阴影压暗（-1.8），布料暗部明显
        _ColorDesaturationAttenuation   ("Shadow Desaturation",   Range(0,1)) = 0.900

        // -----------------------------------------------------------------------
        // 高光
        // -----------------------------------------------------------------------
        [Header(Specular)]
        _SpecularColor      ("Specular Color",         Color)      = (1,1,1,1)
        _NormalStrength     ("Normal Strength",        Range(0,3)) = 1.446
        _specularFGDStrength("Specular FGD Strength", Range(0,2)) = 1.0

        // -----------------------------------------------------------------------
        // Fresnel / ToonFresnel
        // -----------------------------------------------------------------------
        [Header(Fresnel ToonFresnel)]
        _fresnelInsideColor     ("Fresnel Inside Color",  Color)       = (0,0,0,1)
        _fresnelOutsideColor    ("Fresnel Outside Color", Color)       = (1,1,1,1)
        _ToonfresnelPow         ("Toon Fresnel Pow",      Range(0,10)) = 1.700
        _ToonfresnelSMO_L       ("Toon Fresnel SMO Low",  Range(0,1))  = 0.0
        _ToonfresnelSMO_H       ("Toon Fresnel SMO High", Range(0,1))  = 0.500
        _LayerWeightValue       ("Layer Weight Value",    Range(0,2))  = 0.0
        _LayerWeightValueOffset ("Layer Weight Offset",   Range(-1,1)) = 0.0

        // -----------------------------------------------------------------------
        // Rim 边缘光（Strength=5.0 布料边缘光较亮但宽度较细）
        // -----------------------------------------------------------------------
        [Header(Rim Light)]
        _Rim_DirLightAtten  ("Rim DirLight Atten",   Range(0,1))   = 0.962
        _Rim_width_X        ("Rim Width X",           Range(0,0.1)) = 0.04185
        _Rim_width_Y        ("Rim Width Y",           Range(0,0.1)) = 0.01911
        _Rim_Color          ("Rim Color",             Color)        = (1,1,1,1)
        _Rim_ColorStrength  ("Rim Color Strength",    Range(0,10))  = 5.0

        // -----------------------------------------------------------------------
        // RS 特效（_M 贴图在此作为区域遮罩参与）
        // -----------------------------------------------------------------------
        [Header(RS Effect — M Mask Enabled)]
        // _M 贴图 (T_actor_laevat_cloth_03_M.png) 经 SmoothStep 后作为 RS 区域遮罩
        // RSModel=True → 使用模型 B 效果（具体效果待 Group 内连线确认）
        _RS_Index       ("RS Index",          Float)      = 0.0
        _RS_Strength    ("RS Strength",       Range(0,2)) = 1.0
        _RS_MultiplyValue ("RS Multiply",     Range(0,2)) = 1.0
        _RS_ColorTint   ("RS Color Tint",     Color)      = (1,1,1,1)

        // -----------------------------------------------------------------------
        // 其他
        // -----------------------------------------------------------------------
        [Header(Other)]
        _Alpha                  ("Alpha",                  Range(0,1)) = 1.0
        _AnisotropicMask        ("Anisotropic Mask",       Range(0,1)) = 0.0
        _SimpleTransmissionValue ("Simple Transmission",  Range(0,1)) = 0.0
    }

    SubShader
    {
        // -------------------------------------------------------------------
        // SubShader Tags（不透明角色，优先于 Transparent）
        // laevat_cloth_05 Alpha=1.0，使用 Opaque 渲染队列
        // -------------------------------------------------------------------
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Opaque"
            "Queue"          = "Geometry"
        }

        // -------------------------------------------------------------------
        // Pass 0 — ForwardLit（主渲染 Pass）
        // -------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            // 不透明：关闭混合，开启深度写入
            Blend One Zero
            ZWrite On
            Cull Back

            HLSLPROGRAM

            #pragma vertex   PBRToonBase_Cloth05_Vert
            #pragma fragment PBRToonBase_Cloth05_Frag

            // URP 变体
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fog

            // _M 贴图激活的编译器关键字（可选，用于 shader_feature 分支）
            #pragma shader_feature_local _M_MASK_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 主 HLSL（含 _M 预处理逻辑）
            #include "../../hlsl/M_actor_laevat_cloth_05/PBRToonBase_Cloth05.hlsl"

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
        // Pass 2 — DepthOnly（深度预通 Pass，供 DepthRim 屏幕空间采样使用）
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
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"

    // =========================================================================
    // 材质说明（CustomEditor 用，供编辑器面板文档注释）
    // =========================================================================
    // 贴图约定：
    //   _D  = T_actor_laevat_cloth_02_D.png  (sRGB)
    //   _N  = T_actor_laevat_cloth_02_N.png  (Non-Color)
    //   _P  = T_actor_laevat_cloth_02_P.png  (Non-Color, RGBA)
    //   _M  = T_actor_laevat_cloth_03_M.png  (Non-Color) ← 本材质特有，实际连线
    //   _E  = 未使用（黑色，无自发光）
    //
    // _M 处理链：Sample(_M, uv) → SmoothStep(0,1) → mMask → RS EFF 区域遮罩
    //
    // 渲染设置：
    //   RenderType  = Opaque（Alpha=1.0，不透明）
    //   Queue       = Geometry
    //   Cull Back
    //
    // DepthRim 依赖 DepthOnly Pass 写入的相机深度纹理。
    // 确保 URP Renderer Asset 中开启 "Depth Texture" 选项。
    // =========================================================================
}
