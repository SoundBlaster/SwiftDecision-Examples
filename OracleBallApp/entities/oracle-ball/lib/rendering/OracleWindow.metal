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

// Analytic reflection of the two horizontal field ribbons, not a scene capture.
[[visible]] void oracleRingReflection(realitykit::surface_parameters params) {
    float3 position = params.geometry().world_position();
    float3 view = normalize(params.geometry().view_direction());
    float4x4 transform = params.uniforms().model_to_world();
    float3 localNormal = params.geometry().normal();
    // Inverse-transpose normal transform for the nonuniformly flattened glass sphere.
    float3 normal = normalize(
        transform[0].xyz * localNormal.x / dot(transform[0].xyz, transform[0].xyz)
        + transform[1].xyz * localNormal.y / dot(transform[1].xyz, transform[1].xyz)
        + transform[2].xyz * localNormal.z / dot(transform[2].xyz, transform[2].xyz));
    // A flatter optical surface broadens the reflected arcs without changing the glass mesh.
    float3 windowNormal = normalize(transform[2].xyz);
    normal = normalize(mix(windowNormal, normal, 0.55));
    float3 ray = reflect(-view, normal);
    float4 rings = params.uniforms().custom_parameter();
    float glow = 0;
    // Keep derivatives outside divergent branches so the thin lines remain antialiased.
    float denominator = min(ray.y, -0.001);
    for (uint index = 0; index < 2; ++index) {
        float radius = rings[index * 2];
        float opacity = rings[index * 2 + 1];
        // Lift the faint tail while retaining the ring's peak and exact zero endpoints.
        // The subtle reflection otherwise becomes invisible before the source ring does.
        float reflectedOpacity = 0.56 * sqrt(saturate(opacity / 0.56));
        // Same world-space height as OracleField.place; field stays at the scene origin.
        float height = -1.08 + (radius - 0.54) * 0.72;
        float distance = (height - position.y) / denominator;
        float3 hit = position + distance * ray;
        float radialDistance = abs(length(hit.xz) - radius);
        float width = max(0.008, fwidth(radialDistance));
        float core = exp(-pow(radialDistance / width, 2.0));
        float halo = exp(-pow(radialDistance / 0.035, 2.0));
        if (ray.y < -0.001 && distance > 0) {
            glow += (core * 0.7 + halo * 0.3) * reflectedOpacity;
        }
    }
    float fresnel = 0.18 + 0.82 * pow(1.0 - saturate(dot(normal, view)), 5.0);
    params.surface().set_emissive_color(half3(0.72, 0.38, 1.0));
    params.surface().set_opacity(half(min(0.28, glow * fresnel * 0.55)));
}
