// GrizzOS - Quantum Entanglement Breach (Clifford Attractor)
// Mathematical formulation of a probability density cloud collapsing into a rigid structure
// Color Palette: Deep Space Black (#000000), Interferometry Green (#50C878),
// Warning/Pheromind Red (#DC143C), Archive Silver (#C0C0C0)

float2 CliffordAttractor(float2 p, float a, float b, float c, float d) {
    float x_new = sin(a * p.y) + c * cos(a * p.x);
    float y_new = sin(b * p.x) + d * cos(b * p.y);
    return float2(x_new, y_new);
}

void EntanglementCollapse_float(float2 uv, float time, float observerProximity, out float4 OutColor) {
    // observerProximity: 0.0 (Unobserved/Superposition) -> 1.0 (Observed/Collapsed)

    // Base Colors
    float3 colBlack = float3(0.04, 0.06, 0.08);
    float3 colGreen = float3(0.31, 0.78, 0.47); // #50C878
    float3 colSilver= float3(0.75, 0.75, 0.75); // #C0C0C0
    float3 colRed   = float3(0.86, 0.08, 0.24); // #DC143C

    // Chaotic Parameters (Unobserved) vs Rigid Parameters (Observed)
    float a = lerp(1.7, 1.0, observerProximity);
    float b = lerp(1.7, 0.0, observerProximity);
    float c = lerp(0.6, 1.0, observerProximity);
    float d = lerp(1.2, 0.0, observerProximity);

    float2 p = uv * 4.0 - 2.0;
    float density = 0.0;

    // Simulate probability density accumulation
    for (int i = 0; i < 15; i++) {
        p = CliffordAttractor(p, a, b, c, d);
        float d_dist = length(uv - (p * 0.25 + 0.5));

        // As observer gets closer, the cloud snaps into sharp lines (waveform collapse)
        float blur = lerp(0.05, 0.002, observerProximity);
        density += exp(-d_dist * d_dist / blur) * (1.0 / 15.0);
    }

    // Color mapping based on density and entanglement
    float3 finalColor = colBlack;
    if (observerProximity < 0.5) {
        // Superposition State: Ghostly green probability cloud
        finalColor = lerp(colBlack, colGreen, density * 1.5);
    } else {
        // Collapsed State: Rigid, silver/red geometric structures with sharp green edges
        float structure = step(0.6, density);
        finalColor = lerp(colBlack, colSilver, structure);
        finalColor += colRed * step(0.8, density) * abs(sin(time * 5.0)); // Pulsing red nodes
        finalColor += colGreen * step(0.4, density) * (1.0 - structure); // Green aura
    }

    OutColor = float4(finalColor, min(density * 2.0, 1.0));
}
