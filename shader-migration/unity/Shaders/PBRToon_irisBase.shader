Shader "Goo/PBRToon_irisBase"
{
    // =========================================================================
    // 虹膜高光材质 — 概念性 Unity URP ShaderLab
    // 溯源：docs/analysis/M_actor_laevat_iris_01/01_shader_arch.md
    // 对应 Blender 群组：Arknights: Endfield_PBRToon_irisBase
    //
    // 定位：纯 Emission-only 虹膜高光层，以 Additive Blend 叠加到虹膜基础材质上。
    //       使用 Matcap 贴图（视空间法线 UV）+ 光照角度控制高光强度。
    //       骨骼方向向量（headUp/Right/Forward + LightDirection）由 CPU 每帧通过
    //       MaterialPropertyBlock 传入（对应 Blender 几何属性 ATTRIBUTE 节点）。
    //
    // 注：概念性实现，不保证可直接运行。
    // =========================================================================

    Properties
    {
        [Header(Iris Color Input)]
        _IrisColor              ("Iris Color (D_RGB)", Color) = (1, 1, 1, 1)
        _IrisAlpha              ("Iris Alpha (D_Alpha)", Range(0, 1)) = 1.0

        [Header(Brightness Control)]
        _EyesBrightness         ("Eyes Brightness (base)", Float) = 1.0
        _EyesHighlightBrightness("Eyes Highlight Brightness (peak)", Float) = 2.0

        [Header(Matcap Textures)]
        _MatcapMain             ("Matcap Main (matcap_05)", 2D) = "white" {}
        _MatcapSub              ("Matcap Sub  (matcap_07)", 2D) = "white" {}
        _MatcapSubStrength      ("Matcap Sub Strength", Float) = 0.7
        _MatcapBlendFactor      ("Matcap ADD Blend Factor", Range(0, 1)) = 0.567

        [Header(Bone Direction Vectors)]
        // 以下属性由 CPU/骨骼系统每帧通过 MaterialPropertyBlock 更新，
        // 无需在 Inspector 手动设置。
        _HeadUp                 ("Head Up (WS)", Vector) = (0, 1, 0, 0)
        _HeadRight              ("Head Right (WS)", Vector) = (1, 0, 0, 0)
        _HeadForward            ("Head Forward (WS)", Vector) = (0, 0, 1, 0)
        _LightDirection         ("Light Direction (WS)", Vector) = (0, 1, 0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Transparent"
            "Queue"          = "Transparent+1"
        }

        // =====================================================================
        // Pass: ForwardLit — 主渲染（Additive Blend，叠加到虹膜基础材质之上）
        // =====================================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            // Additive 叠加：虹膜高光层直接 Add 到已渲染的虹膜底色
            Blend One One
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma vertex   PBRToon_irisBase_Vert
            #pragma fragment PBRToon_irisBase_Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PBRToon_irisBase.hlsl"

            ENDHLSL
        }

        // =====================================================================
        // Pass: ShadowCaster — 投影阴影（虹膜通常不投影，可选禁用）
        // =====================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }

        // =====================================================================
        // Pass: DepthOnly — 深度预通（供其他 Pass 的深度采样使用）
        // =====================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
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
    // 迁移注意事项（CustomEditor 注释区）
    //
    // 1. 骨骼数据传递：
    //    在 Unity 中，Blender 的 ATTRIBUTE 节点（headUp/Right/Forward/LightDirection）
    //    没有对应的内置机制。推荐方案：
    //    a) 自定义 MonoBehaviour 脚本，每帧从 Animator/Transform 计算方向向量，
    //       通过 renderer.SetPropertyBlock() 写入 _HeadUp、_HeadRight 等属性。
    //    b) 或使用 Custom Vertex Attribute（在 SkinnedMesh 中烘焙骨骼方向到 UV 通道）。
    //
    // 2. Additive 叠加方式：
    //    本 Shader 应作为独立材质（第二材质槽）附加到虹膜 Mesh 上，
    //    渲染队列比基础虹膜材质稍高（Transparent+1）。
    //
    // 3. Matcap UV 实现：
    //    使用 TransformWorldToViewDir(normalWS) 获取相机空间法线，
    //    再 *.xy * 0.5 + 0.5 得到 [0,1] UV。在 URP 中需确保使用正交归一化变换。
    //
    // 4. calculateAngel 的 Unity 实现：
    //    atan2 需使用 HLSL 内置 atan2(y, x)，注意参数顺序与 Blender 节点相同。
    // =========================================================================
}
