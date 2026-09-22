#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// One bright center line with a soft halo across the width of each 3D ribbon.
[[visible]] void oracleFieldRibbon(realitykit::surface_parameters params) {
    float edge = abs(params.geometry().uv0().y * 2.0 - 1.0);
    float core = exp(-85.0 * edge * edge);
    float halo = exp(-6.0 * edge * edge);
    float4 controls = params.uniforms().custom_parameter();
    half brightness = half(core * 1.5 + halo * 0.4);
    half opacity = half((core * 0.72 + halo * 0.17) * controls.w);
    params.surface().set_emissive_color(half3(controls.xyz) * brightness);
    params.surface().set_opacity(opacity);
}
