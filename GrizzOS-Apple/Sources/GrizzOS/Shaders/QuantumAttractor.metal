#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// GrizzOS - Metal Shader for Clifford Attractor
[[visible]]
void quantum_attractor_surface(realitykit::surface_parameters params) {
    float time = params.uniforms().time();
    float entanglement = abs(sin(time * 0.5));

    float3 colorUnobserved = float3(0.31, 0.78, 0.47); // #50C878
    float3 colorObserved = float3(0.75, 0.75, 0.75);   // #C0C0C0
    float3 colorWarning = float3(0.86, 0.08, 0.24);    // #DC143C

    float2 uv = params.geometry().uv0();
    float3 pos = params.geometry().model_position();

    float t = time * 0.002;
    float scanline = sin(uv.y * 100.0 + t * 10.0) * 0.04;

    float3 baseColor = mix(colorUnobserved, colorObserved, entanglement);
    float pulse = step(0.9, sin(pos.y * 10.0 - t * 5.0));
    float3 finalColor = mix(baseColor, colorWarning, pulse * entanglement);

    float3 viewDir = normalize(params.geometry().view_direction());
    float3 normal = params.geometry().normal();
    float edge = 1.0 - max(0.0, dot(normal, viewDir));
    finalColor += colorUnobserved * edge * (1.0 - entanglement) * 2.0;

    float alpha = mix(0.3 + scanline, 0.8 + scanline, entanglement);

    params.surface().set_base_color(half3(finalColor));
    params.surface().set_opacity(half(alpha));
    params.surface().set_metallic(half(entanglement));
    params.surface().set_roughness(half(0.8 - entanglement * 0.4));
}
