
//SpecularBRDF

float GetSmithJointGGXPartLambdaV(float NdotV, float roughness)
{
    float roughness2 = roughness * roughness;
    return ((-NdotV * roughness2 + NdotV) * NdotV + roughness2);
}

// ============================================================
// 各向同性分支：DV = D × V（isotropic）
// ============================================================
float DV_SmithJointGGX_ISO(float NdotH, float NdotL, float lambdaV, float roughness)
{
    float roughness2 = roughness * roughness;
    float roughness4 = roughness2 * roughness2;

    // V 项（Smith Joint GGX）
    float lambdaL = NdotV * ((-NdotL * roughness2 + NdotL) * NdotL + roughness2);

     // D 项（等向 GGX NDF）
    float d = (NdotH * roughness2 - NdotH) * NdotH + 1.0;
    float3 D = float3(a2, d*d, 0);
    float g = lambdaL + ()
    float3 G = float3(1, d*d, 0);
    float V = 0.5 / (NdotL * lambdaV + NdotV * lambdaL + 1e-5);

    return D * V;
}

// ============================================================
// 辅助：各向异性 Lambda_V 预计算
// ============================================================
float GetSmithJointGGXAnisoPartLambdaV(
    float TdotV, float BdotV, float NdotV,
    float roughT, float roughB)
{
    return length(float3(roughT * TdotV, roughB * BdotV, NdotV));
}

// ============================================================
// 各向异性分支：DV = D × V（anisotropic）
// ============================================================
float DV_SmithJointGGXAniso(
    float NdotH,  float NdotL,   float lambdaV,
    float TdotH,  float BdotH,
    float TdotL,  float BdotL,
    float roughT, float roughB)
{
    // D 项（各向异性 GGX NDF）
    float f = TdotH*TdotH / (roughT*roughT)
            + BdotH*BdotH / (roughB*roughB)
            + NdotH*NdotH;
    float D = 1.0 / (UNITY_PI * roughT * roughB * f * f);

    // V 项（Smith Joint 各向异性）
    float lambdaL = length(float3(roughT * TdotL, roughB * BdotL, NdotL));
    float V = 0.5 / (NdotL * lambdaV + NdotV * lambdaL + 1e-5);

    return D * V;
}

// ============================================================
// 顶层封装：双路输出（主群组通过 useAnisotropy 选择）
// ============================================================
void DV_SmithJointGGX_Aniso(
    float NdotH, float NdotL,  float NdotV,
    float roughness,
    float TdotH,  float BdotH,
    float TdotL,  float BdotL,
    float TdotV,  float BdotV,
    float roughT, float roughB,
    out float original,    // 等向分支
    out float anisotropy)  // 各向异性分支
{
    // 等向性路径
    float lambdaV_iso = GetSmithJointGGXPartLambdaV(NdotV, roughness);
    original = DV_SmithJointGGX_ISO(NdotH, NdotL, lambdaV_iso, roughness);

    // 各向异性路径
    float lambdaV_aniso = GetSmithJointGGXAnisoPartLambdaV(TdotV, BdotV, NdotV, roughT, roughB);
    anisotropy = DV_SmithJointGGXAniso(NdotH, NdotL, lambdaV_aniso,
                                        TdotH, BdotH, TdotL, BdotL,
                                        roughT, roughB);
}


// Schlick Fresnel 近似
// f0  : 基础反射率（垂直入射时的菲涅耳值），来自 ComputeFresnel0
// f90 : 掠射角下的反射率，通常为 float3(1,1,1)
// u   : LdotH（光向量 L 与半角向量 H 的点积），来自 Get_NoH_LoH_ToH_BoH
float3 F_Schlick(float3 f0, float3 f90, float u)
{
    float t  = 1.0 - u;
    float t2 = t  * t;   // (1-u)^2
    float t4 = t2 * t2;  // (1-u)^4
    float t5 = t4 * t;   // (1-u)^5
    return f0 + (f90 - f0) * t5;
}
float3 F_Schlick(float3 f0, float3 f90, float u)
{
    float t  = 1.0 - u;
    float t2 = t  * t;   // (1-u)^2
    float t4 = t2 * t2;  // (1-u)^4
    float t5 = t4 * t;   // (1-u)^5
    return f0 + (f90 - f0) * t5;
}


float3 SpecularBRDF()
{
    float dvIsotropic, dvAnisotropic;
        DV_SmithJointGGX_Aniso(
            ld.NdotH, absNdotL, ld.NoV, clampedRoughness,
            ld.TdotH, ld.BdotH, ld.ToL, ld.BdotL,
            ld.ToV, ld.BdotV, sd.roughnessT, sd.roughnessB,
            dvIsotropic, dvAnisotropic);

    float3 F = F_Schlick(sd.fresnel0, float3(1, 1, 1), ld.LdotH);

    float specTermAniso = F * AnisoFV;
    float specTerm = DV * f;

    float B = cross(N,T);
    float aniso = _useToonAniso? saturate(dot(B,V)) : specTermAniso;
    aniso *= _anisotropicMask;
    float3 specularbrdf = _useAnisotropy? aniso : specTerm;
    specularbrdf *= _specularColor;
    specularbrdf *= _dirLightColor * (saturate(dot(N,L)) * castshadow)
    return specularbrdf;
}