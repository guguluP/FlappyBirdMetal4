#include <metal_stdlib>
using namespace metal;

// Lit 3D mesh + sky shaders (Metal 4–compatible MSL).

struct VertexIn {
    float3 position;
    float3 normal;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float4 color;
};

struct FrameUniforms {
    float2 resolution;
    float time;
    float _pad0;
    float4x4 viewProj;
    float3 lightDir;
    float _pad1;
    float3 lightColor;
    float ambient;
    float3 eyePos;
    float _pad2;
};

vertex VertexOut vertex_main(
    uint vid [[vertex_id]],
    constant VertexIn *vertices [[buffer(0)]],
    constant FrameUniforms &uniforms [[buffer(1)]]
) {
    VertexIn vin = vertices[vid];
    VertexOut out;
    float4 wp = float4(vin.position, 1.0);
    out.position = uniforms.viewProj * wp;
    out.worldPos = vin.position;
    out.normal = vin.normal;
    out.color = vin.color;
    return out;
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant FrameUniforms &uniforms [[buffer(1)]]
) {
    float3 N = normalize(in.normal);
    float3 L = normalize(-uniforms.lightDir);
    float3 V = normalize(uniforms.eyePos - in.worldPos);
    float3 H = normalize(L + V);

    float ndl = saturate(dot(N, L));
    float spec = pow(saturate(dot(N, H)), 48.0) * 0.45;
    // Soft rim for 3D pop
    float rim = pow(1.0 - saturate(dot(N, V)), 2.5) * 0.22;

    float3 base = in.color.rgb;
    float3 lit = base * (uniforms.ambient + ndl * uniforms.lightColor)
               + uniforms.lightColor * spec * (0.35 + base.r * 0.4)
               + float3(0.55, 0.75, 1.0) * rim;

    // Slight depth-based fog toward far Z
    float fog = saturate((in.worldPos.z + 1.2) * 0.12);
    lit = mix(lit, float3(0.55, 0.78, 0.95), fog * 0.15);

    return float4(lit, in.color.a);
}

// Full-screen sky with volumetric-ish clouds and sun
struct SkyVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex SkyVertexOut sky_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    SkyVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    return out;
}

fragment float4 sky_fragment(
    SkyVertexOut in [[stage_in]],
    constant FrameUniforms &uniforms [[buffer(0)]]
) {
    float t = saturate(in.uv.y);
    float3 top = float3(0.22, 0.48, 0.92);
    float3 mid = float3(0.48, 0.76, 0.98);
    float3 bottom = float3(0.82, 0.90, 0.78);

    float3 col = mix(bottom, mid, smoothstep(0.0, 0.5, t));
    col = mix(col, top, smoothstep(0.4, 1.0, t));

    // Animated sun with glow layers
    float2 sunPos = float2(0.78, 0.82);
    float d = distance(in.uv, sunPos);
    col += float3(1.0, 0.95, 0.7) * exp(-d * 22.0) * 0.55;
    col += float3(1.0, 0.75, 0.35) * exp(-d * 8.0) * 0.25;

    // Multi-layer soft clouds
    float time = uniforms.time;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 p = in.uv * float2(3.5 + fi, 2.2 + fi * 0.3);
        p.x += time * (0.04 + fi * 0.015);
        float n = sin(p.x * 2.1 + p.y * 1.3) * cos(p.y * 2.4 - p.x * 0.7);
        n = n * 0.5 + 0.5;
        float band = smoothstep(0.45, 0.85, in.uv.y) * smoothstep(1.0, 0.55, in.uv.y);
        col = mix(col, float3(1.0, 1.0, 0.98), n * n * band * (0.08 + fi * 0.03));
    }

    // Horizon haze
    col = mix(col, float3(0.95, 0.88, 0.75), exp(-in.uv.y * 6.0) * 0.18);

    return float4(col, 1.0);
}
