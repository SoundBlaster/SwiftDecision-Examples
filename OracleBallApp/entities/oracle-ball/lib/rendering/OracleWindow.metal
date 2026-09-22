#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Soft aperture shadow anchored to the window, independent of the floating plate.
[[visible]] void oracleWindowShadow(realitykit::surface_parameters params) {
    float radius = length((params.geometry().uv0() - 0.5) * 2.0);
    float4 controls = params.uniforms().custom_parameter();
    float edge = smoothstep(controls.x, controls.y, radius);
    // A smooth fade leaves the answer clear and deepens toward the circular rim.
    half opacity = half(edge * edge * controls.z);
    params.surface().set_emissive_color(half3(0.001, 0.0015, 0.007));
    params.surface().set_opacity(opacity);
}
