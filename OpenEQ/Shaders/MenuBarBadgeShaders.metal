#include <metal_stdlib>
using namespace metal;

[[stitchable]] half4 audioWaveGlow(
    float2 position,
    half4 color,
    float4 boundingRect,
    float time,
    float leftLevel,
    float rightLevel,
    float isRunning
) {
    float2 uv = (position - boundingRect.xy) / boundingRect.zw;
    
    // Base glow gradient
    float dist = distance(uv, float2(0.5, 0.5));
    float pulse = 0.5 + 0.5 * sin(time * 3.0 + uv.x * 6.28);
    
    // Wave modulation using audio peak levels
    float audioAmp = max(leftLevel, rightLevel);
    if (isRunning > 0.5) {
        audioAmp = max(audioAmp, 0.15);
    }
    
    float wave = sin(uv.x * 12.0 + time * 4.0) * cos(uv.y * 12.0 - time * 2.0);
    float glow = smoothstep(0.6, 0.1, dist) * (1.0 + wave * audioAmp * 0.8);
    
    // Dynamic color shifting (Cyan / Neon Blue / Purple glow)
    half3 c1 = half3(0.1, 0.8, 1.0);  // Cyan neon
    half3 c2 = half3(0.5, 0.2, 1.0);  // Purple neon
    half3 c3 = half3(1.0, 0.3, 0.6);  // Magenta highlight
    
    half3 gradient = mix(c1, c2, half(uv.x + 0.2 * sin(time)));
    gradient = mix(gradient, c3, half(audioAmp * pulse));
    
    half alpha = half(clamp(glow * (0.4 + audioAmp * 0.6), 0.0, 1.0));
    return half4(gradient * alpha, alpha);
}
