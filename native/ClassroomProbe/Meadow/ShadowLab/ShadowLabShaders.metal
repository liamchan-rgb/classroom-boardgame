#include <metal_stdlib>
using namespace metal;

struct LabVertex { float4 position; float4 uvWind; float4 color; };
struct LabUniforms { float4x4 camera; float4x4 light; float4 sunTime; float4 options; };
struct LabRaster { float4 position [[position]]; float3 world; float2 uv; float4 color; float2 wind; };

struct MeadowBackdropRaster { float4 position [[position]]; float2 uv; };
vertex MeadowBackdropRaster meadowBackdropVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = { float2(-1, 1), float2(-1, -3), float2(3, 1) };
    MeadowBackdropRaster out;
    float2 p = positions[id];
    out.position = float4(p, 0, 1);
    out.uv = float2((p.x + 1) * 0.5, (1 - p.y) * 0.5);
    return out;
}
fragment float4 meadowBackdropFragment(MeadowBackdropRaster in [[stage_in]], texture2d<float> backdrop [[texture(0)]]) {
    constexpr sampler linearPixels(coord::normalized, address::clamp_to_edge, filter::linear);
    return float4(backdrop.sample(linearPixels, in.uv).rgb, 1);
}

float3 labDeform(LabVertex v, constant LabUniforms &u) {
    if (u.options.w > 0.5) return v.position.xyz;
    float bend = (sin(u.sunTime.w * 1.55 + v.uvWind.w) + 0.28 * sin(u.sunTime.w * 2.73 + v.uvWind.w * 1.7)) * 0.24;
    return v.position.xyz + float3(bend * v.uvWind.z * v.uvWind.z * u.options.z, 0, 0);
}

vertex LabRaster labColorVertex(uint id [[vertex_id]], device const LabVertex *v [[buffer(0)]], constant LabUniforms &u [[buffer(1)]]) {
    LabRaster o;
    o.world = labDeform(v[id], u);
    o.position = u.camera * float4(o.world, 1);
    o.uv = v[id].uvWind.xy;
    o.color = v[id].color;
    o.wind = v[id].uvWind.zw;
    return o;
}

vertex LabRaster labCutoutShadowVertex(uint id [[vertex_id]], device const LabVertex *v [[buffer(0)]], constant LabUniforms &u [[buffer(1)]]) {
    LabRaster o;
    o.world = labDeform(v[id], u);
    o.position = u.light * float4(o.world, 1);
    o.uv = v[id].uvWind.xy;
    o.color = v[id].color;
    o.wind = v[id].uvWind.zw;
    return o;
}

bool labCasterVisible(LabRaster in, float4 color, constant float4 &settings) {
    if (color.a < settings.y || in.world.z < 0.002) return false;
    // Oak's low green apron belongs to the ground, not to the trunk volume.
    if (settings.x < 0.5 && in.uv.y > 0.83 && color.g > color.r * 1.03 && color.g > color.b * 1.15) return false;
    return true;
}

fragment void labCutoutShadowFragment(LabRaster in [[stage_in]], texture2d<float> art [[texture(0)]], constant float4 &settings [[buffer(2)]]) {
    constexpr sampler pixels(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 color = art.sample(pixels, in.uv);
    if (!labCasterVisible(in, color, settings)) discard_fragment();
}

fragment float4 labCutoutModelFragment(LabRaster in [[stage_in]], texture2d<float> art [[texture(0)]], constant float4 &settings [[buffer(2)]]) {
    constexpr sampler pixels(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 color = art.sample(pixels, in.uv);
    if (!labCasterVisible(in, color, settings)) discard_fragment();
    float2 cell = fract(in.uv * float2(16, 32));
    float grid = max(step(0.94, cell.x), step(0.94, cell.y));
    float alpha = (0.18 + grid * 0.40) * color.a;
    return float4(in.color.rgb * alpha, alpha);
}

float labVisibility(float3 world, constant LabUniforms &u, depth2d<float> shadowMap) {
    if (u.options.x < 0.5) return 1;
    float4 clip = u.light * float4(world, 1);
    float3 p = clip.xyz / clip.w;
    float2 uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (any(uv < 0) || any(uv > 1) || p.z < 0 || p.z > 1) return 1;
    constexpr sampler comparison(coord::normalized, address::clamp_to_edge, filter::linear, compare_func::less_equal);
    // Four bilinear comparison taps preserve soft PCF while cutting the
    // full-screen shadow lookup count from nine to four on iPad GPUs.
    float2 texel = float2(u.options.y * 0.7);
    float depth = p.z - 0.00003;
    float visibility = shadowMap.sample_compare(comparison, uv + texel * float2(-1, -1), depth);
    visibility += shadowMap.sample_compare(comparison, uv + texel * float2( 1, -1), depth);
    visibility += shadowMap.sample_compare(comparison, uv + texel * float2(-1,  1), depth);
    visibility += shadowMap.sample_compare(comparison, uv + texel * float2( 1,  1), depth);
    return visibility * 0.25;
}

fragment float4 labGroundFragment(LabRaster in [[stage_in]], constant LabUniforms &u [[buffer(1)]],
                                 texture2d<float> grass [[texture(0)]], depth2d<float> shadowMap [[texture(1)]]) {
    constexpr sampler tile(coord::normalized, address::repeat, filter::linear);
    float3 base = grass.sample(tile, in.world.xy / 8).rgb;
    float patch = sin(in.world.x * 0.35) * cos(in.world.y * 0.28);
    base *= 0.89 + patch * 0.04;
    float visibility = labVisibility(in.world, u, shadowMap);
    float3 shade = float3(0.38, 0.44, 0.43);
    return float4(base * mix(shade, float3(1), visibility), 1);
}

fragment float4 labArtworkFragment(LabRaster in [[stage_in]], texture2d<float> art [[texture(0)]]) {
    constexpr sampler pixels(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 color = art.sample(pixels, in.uv);
    if (color.a < 0.008) discard_fragment();
    // Uploaded CG contexts are explicitly premultiplied; blend is one / one-minus-alpha.
    return color;
}

// Main map shares SpriteKit's UV wind and ground fade with its depth silhouettes.
fragment void meadowCutoutShadowFragment(LabRaster in [[stage_in]], texture2d<float> art [[texture(0)]],
                                         constant LabUniforms &u [[buffer(1)]], constant float4 &settings [[buffer(2)]],
                                         constant float4 &atlasRect [[buffer(3)]]) {
    constexpr sampler pixels(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 uv = in.uv;
    float height = 1 - uv.y;
    float root = smoothstep(0.06, 0.95, height);
    float gust = 0.74 + 0.26 * sin(u.sunTime.w * 0.47 + in.wind.y * 0.31);
    float sway = sin(u.sunTime.w * 1.55 + in.wind.y) + 0.28 * sin(u.sunTime.w * 2.73 + in.wind.y * 1.7);
    if (in.wind.x > 1.5) uv.y -= sin(uv.x * 10 - u.sunTime.w * 3.8 + in.wind.y) * 0.04 * uv.x;
    else uv.x += sway * 0.052 * gust * in.wind.x * root * root;
    float4 color = art.sample(pixels, atlasRect.xy + clamp(uv, 0.001, 0.999) * atlasRect.zw);
    if (settings.x >= 5.5 && settings.x < 7.5) color.a *= smoothstep(0.035, 0.16, height);
    if (!labCasterVisible(in, color, settings)) discard_fragment();
}

fragment float4 meadowShadowReceiverFragment(LabRaster in [[stage_in]], constant LabUniforms &u [[buffer(1)]],
                                              depth2d<float> shadowMap [[texture(1)]]) {
    float alpha = (1 - labVisibility(in.world, u, shadowMap)) * 0.61;
    return float4(float3(0.075, 0.105, 0.080) * alpha, alpha);
}

// Native opaque terrain: grass, road coverage and PCF reception are written in
// one pass. There is no dependency on a separately scheduled SKRenderer pass.
float meadowHash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float meadowNoise(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3 - 2 * f);
    return mix(mix(meadowHash(i), meadowHash(i + float2(1, 0)), f.x),
               mix(meadowHash(i + float2(0, 1)), meadowHash(i + 1), f.x), f.y);
}
fragment float4 meadowGroundFragment(LabRaster in [[stage_in]], constant LabUniforms &u [[buffer(1)]],
                                    constant float4 &settings [[buffer(2)]], texture2d<float> grassTexture [[texture(0)]],
                                    depth2d<float> shadowMap [[texture(1)]], texture2d<float> roadMask [[texture(2)]]) {
    constexpr sampler tile(coord::normalized, address::repeat, filter::linear);
    constexpr sampler maskSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 p = float2(in.world.x * 32 + 640, 360 - in.world.y * 32 * 0.8137334712);
    float2 cell = floor(p / 190), weight = smoothstep(0.0, 1.0, fract(p / 190));
    float2 uv = p / 440;
    float2 a = cell, b = cell + float2(1, 0), c = cell + float2(0, 1), d = cell + 1;
    float3 sa = grassTexture.sample(tile, uv + float2(meadowHash(a), meadowHash(a + 17.3))).rgb;
    float3 sb = grassTexture.sample(tile, uv + float2(meadowHash(b), meadowHash(b + 17.3))).rgb;
    float3 sc = grassTexture.sample(tile, uv + float2(meadowHash(c), meadowHash(c + 17.3))).rgb;
    float3 sd = grassTexture.sample(tile, uv + float2(meadowHash(d), meadowHash(d + 17.3))).rgb;
    float3 grass = mix(mix(sa, sb, weight.x), mix(sc, sd, weight.x), weight.y);
    grass = mix(grass, float3(0.25, 0.34, 0.12), 0.15 + (1 - meadowNoise(p * 0.0037)) * 0.10);
    grass = mix(float3(dot(grass, float3(0.299, 0.587, 0.114))), grass, 0.88);
    float2 maskUV = (p - float2(-160, -220)) / float2(1600, settings.z > 0 ? settings.z : 1160);
    float4 mask = roadMask.sample(maskSampler, maskUV);
    float edge = meadowNoise(p * 0.23) * 0.58 + meadowNoise(p * 0.73) * 0.28 + meadowHash(floor(p * 1.6)) * 0.14;
    float coverage = smoothstep(0.10 + edge * 0.15, 0.58 + edge * 0.12, mask.r) * settings.x;
    float patches = meadowNoise(p * 0.045), fine = meadowHash(floor(p * 1.5));
    float3 soil = mix(float3(0.37, 0.32, 0.19), float3(0.59, 0.51, 0.32), patches * 0.64 + fine * 0.25);
    soil *= 1 - mask.g * (0.035 + meadowNoise(p * 0.11) * 0.045);
    float2 stoneCell = floor(p * 0.48), spot = fract(p * 0.48) - 0.5;
    float stones = step(0.95, meadowHash(stoneCell)) * (1 - smoothstep(0.08, 0.25, length(spot)));
    soil = mix(soil, float3(0.53, 0.50, 0.37), stones * 0.40);
    float sparse = smoothstep(0.42, 0.72, meadowNoise(p * 0.31)) * (1 - coverage * 0.78);
    float roadAlpha = coverage * (0.78 + patches * 0.10) * (1 - sparse * 0.70);
    float cloud = smoothstep(0.25, 0.76, meadowNoise((p - float2(u.sunTime.w * 14, u.sunTime.w * 5)) * 0.0065));
    float light = 0.65 + cloud * 0.36 + exp(-length(p - float2(-100, -170)) * 0.0012) * 0.07;
    float3 base = mix(grass, soil, roadAlpha) * light;
    float visibility = labVisibility(in.world, u, shadowMap);
    float marker = min(distance(p, float2(540, 300)), min(distance(p, float2(740, 300)), distance(p, float2(640, 440))));
    if (settings.y > 0.5 && marker < 8) return float4(0, 1, 1, 1);
    return float4(base * mix(float3(0.38, 0.44, 0.43), float3(1), visibility), 1);
}
