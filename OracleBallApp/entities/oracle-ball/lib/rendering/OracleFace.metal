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
    // A broad planar gradient, never an edge highlight: the face stays visually flat.
    // World-space normal and view direction respond to both plate float and phone tilt.
    float3 normal = normalize((params.uniforms().model_to_world() * float4(0, 0, 1, 0)).xyz);
    float3 view = normalize(params.geometry().view_direction());
    float slope = clamp(0.10 + 0.65 * normal.y + 0.45 * (view.y - normal.y), -0.18, 0.18);
    float lateral = clamp(0.35 * (view.x - normal.x), -0.08, 0.08);
    float shading = 1.0 + (0.5 - uv.y) * 2.0 * slope + (uv.x - 0.5) * lateral;
    surface *= half(shading);
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
