#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Artistic absorption, not a volumetric fluid simulation. Geometry stays opaque.
[[visible]] void oracleFace(realitykit::surface_parameters params) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = params.geometry().uv0();
    float4 controls = params.uniforms().custom_parameter();
    half3 sharp = params.textures().base_color().sample(s, uv).rgb;
    half3 blurred = params.textures().custom().sample(s, uv).rgb;
    half3 surface = mix(blurred, sharp, half(saturate(controls.w)));
    // A restrained grazing highlight reveals the upper bevel without a bloom pass.
    float topGlow = exp(-pow((uv.y - 0.035) / 0.025, 2.0));
    surface += half3(0.12, 0.065, 0.35) * half(topGlow);
    half transmission = half(exp(-max(controls.x, 0.0) * max(controls.y, 0.0)));
    half3 fluid = half3(0.001, 0.0015, 0.007);
    params.surface().set_emissive_color(mix(fluid, surface * half(controls.z), transmission));
}

[[visible]] void oracleEdge(realitykit::surface_parameters params) {
    float4 controls = params.uniforms().custom_parameter();
    half transmission = half(exp(-max(controls.x, 0.0) * max(controls.y, 0.0)));
    half3 fluid = half3(0.001, 0.0015, 0.007);
    params.surface().set_emissive_color(mix(fluid, half3(0.09, 0.035, 0.55), transmission));
}
