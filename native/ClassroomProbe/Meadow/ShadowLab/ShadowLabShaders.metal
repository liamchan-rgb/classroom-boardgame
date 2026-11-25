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
struct MeadowBiomeUniforms {
    float4 bossPoints[4]; // xy = world point in map pixels, z = active (>0.5), w = unused
    float4 params;        // x = biomePhase, y = biomeBlendStrength, z = unused, w = unused
};

float3 sampleScatteredGround(texture2d<float> tex, sampler tile, float2 uv, float2 a, float2 b, float2 c, float2 d, float2 weight) {
    float3 sa = tex.sample(tile, uv + float2(meadowHash(a), meadowHash(a + 17.3))).rgb;
    float3 sb = tex.sample(tile, uv + float2(meadowHash(b), meadowHash(b + 17.3))).rgb;
    float3 sc = tex.sample(tile, uv + float2(meadowHash(c), meadowHash(c + 17.3))).rgb;
    float3 sd = tex.sample(tile, uv + float2(meadowHash(d), meadowHash(d + 17.3))).rgb;
    return mix(mix(sa, sb, weight.x), mix(sc, sd, weight.x), weight.y);
}

fragment float4 meadowGroundFragment(LabRaster in [[stage_in]], constant LabUniforms &u [[buffer(1)]],
                                    constant float4 &settings [[buffer(2)]],
                                    constant MeadowBiomeUniforms &biome [[buffer(3)]],
                                    texture2d<float> grassTexture [[texture(0)]],
                                    depth2d<float> shadowMap [[texture(1)]],
                                    texture2d<float> roadMask [[texture(2)]],
                                    texture2d<float> autumnTexture [[texture(3)]],
                                    texture2d<float> blossomTexture [[texture(4)]],
                                    texture2d<float> sanctumTexture [[texture(5)]]) {
    constexpr sampler tile(coord::normalized, address::repeat, filter::linear);
    constexpr sampler maskSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 p = float2(in.world.x * 32 + 640, 360 - in.world.y * 32 * 0.8137334712);
    float2 cell = floor(p / 190), weight = smoothstep(0.0, 1.0, fract(p / 190));
    float2 uv = p / 440;
    float2 a = cell, b = cell + float2(1, 0), c = cell + float2(0, 1), d = cell + 1;
    float3 grass = sampleScatteredGround(grassTexture, tile, uv, a, b, c, d, weight);

    // Coherent world-space biome blending matching RandomMap's biomeNoise + Boss Sanctum zones
    float biomeStrength = biome.params.y;
    if (biomeStrength > 0.01) {
        float phase = biome.params.x;
        float n1 = sin(p.x * 0.0029 + phase) * cos(p.y * 0.0031 - phase * 0.7);
        float n2 = sin((p.x * 0.0017 - p.y * 0.0021) + phase * 1.3);
        float edgeJitter = (meadowNoise(p * 0.018) - 0.5) * 0.14;
        float bVal = clamp(0.5 + 0.34 * n1 + 0.22 * n2 + edgeJitter, 0.0, 1.0);
        float autumnW = smoothstep(0.55, 0.74, bVal) * 0.78 * biomeStrength;
        float blossomW = (1.0 - smoothstep(0.24, 0.43, bVal)) * 0.68 * biomeStrength;
        float sanctumW = 0.0;
        for (int bi = 0; bi < 4; bi++) {
            if (biome.bossPoints[bi].z > 0.5) {
                float dist = length(p - biome.bossPoints[bi].xy) + edgeJitter * 140.0;
                sanctumW = max(sanctumW, (1.0 - smoothstep(100.0, 265.0, dist)) * 0.86);
            }
        }
        sanctumW *= biomeStrength;
        if (autumnW > 0.01) {
            float3 aut = sampleScatteredGround(autumnTexture, tile, uv, a, b, c, d, weight);
            grass = mix(grass, aut, autumnW);
        }
        if (blossomW > 0.01) {
            float3 bls = sampleScatteredGround(blossomTexture, tile, uv, a, b, c, d, weight);
            grass = mix(grass, bls, blossomW);
        }
        if (sanctumW > 0.01) {
            float3 snc = sampleScatteredGround(sanctumTexture, tile, uv, a, b, c, d, weight);
            grass = mix(grass, snc, sanctumW);
        }
    }

    grass = mix(grass, float3(0.25, 0.34, 0.12), 0.10 + (1 - meadowNoise(p * 0.0037)) * 0.08);
    grass = mix(float3(dot(grass, float3(0.299, 0.587, 0.114))), grass, 0.92);
    float2 maskUV = (p - float2(-160, -220)) / float2(1600, settings.z > 0 ? settings.z : 1160);
    float4 mask = roadMask.sample(maskSampler, maskUV);
    float edge = meadowNoise(p * 0.23) * 0.58 + meadowNoise(p * 0.73) * 0.28 + meadowHash(floor(p * 1.6)) * 0.14;
    float coverage = smoothstep(0.10 + edge * 0.15, 0.56 + edge * 0.12, mask.r) * settings.x;
    float patches = meadowNoise(p * 0.045), fine = meadowHash(floor(p * 1.5));

    // Rich adventure trail: warm golden-ochre packed earth + mossy kerb shoulder + stepping stones + weathered cobblestones
    float3 soil = mix(float3(0.41, 0.35, 0.21), float3(0.64, 0.55, 0.34), patches * 0.64 + fine * 0.25);
    float cobbleW = smoothstep(0.50, 0.72, mask.g);
    float ruralWear = min(mask.g / 0.45, 1.0) * (1.0 - cobbleW);
    soil *= 1.0 - ruralWear * (0.04 + meadowNoise(p * 0.11) * 0.045);

    // Darker organic road shoulder & scattered flat stepping pebbles along rural paths
    float shoulder = smoothstep(0.06, 0.30, coverage) * (1.0 - smoothstep(0.32, 0.68, coverage));
    soil = mix(soil, float3(0.28, 0.26, 0.16), shoulder * 0.36);
    float2 stoneCell = floor(p * 0.44), spot = fract(p * 0.44) - 0.5;
    float stones = step(0.92, meadowHash(stoneCell)) * (1.0 - smoothstep(0.10, 0.30, length(spot)));
    soil = mix(soil, float3(0.57, 0.54, 0.41), stones * 0.46);
    // Occasional larger mossy stepping flagstones along rural roads
    float2 stepGrid = p * 0.085;
    float2 sgCell = floor(stepGrid), sgFrac = fract(stepGrid) - 0.5;
    float2 sgJitter = float2(meadowHash(sgCell + 3.1), meadowHash(sgCell + 19.7)) - 0.5;
    float stepFlag = step(0.58, meadowHash(sgCell + 7.4)) * (1.0 - smoothstep(0.16, 0.31, length((sgFrac - sgJitter * 0.32) * float2(1.0, 1.35))));
    soil = mix(soil, float3(0.54, 0.51, 0.42), stepFlag * (1.0 - cobbleW) * coverage * 0.48);

    // Procedural soft-painterly weathered cobblestone paving near Sanctums, Fortresses, Camp & Bridges
    if (cobbleW > 0.01 && coverage > 0.05) {
        float2 cuv = p * float2(0.115, 0.145);
        float rowShift = fract(floor(cuv.y) * 0.5) * 0.5;
        float2 tileP = float2(cuv.x + rowShift, cuv.y);
        float2 cid = floor(tileP), cf = fract(tileP);
        float2 wobble = (float2(meadowNoise(p * 0.26), meadowNoise(p * 0.26 + 11.3)) - 0.5) * 0.14;
        float2 cfw = clamp(cf + wobble, 0.0, 1.0);
        float edgeDist = min(min(cfw.x, 1.0 - cfw.x), min(cfw.y, 1.0 - cfw.y));
        float mortar = 1.0 - smoothstep(0.05, 0.13, edgeDist);
        float tone = meadowHash(cid * 1.7 + 4.3);
        float3 cobbleBase = mix(float3(0.46, 0.44, 0.39), float3(0.62, 0.58, 0.48), tone);
        // Subtle upper-left sunlit bevel per stone
        float bevel = smoothstep(0.10, 0.24, cfw.x) * (1.0 - smoothstep(0.76, 0.90, cfw.x))
                    + (1.0 - smoothstep(0.08, 0.34, cfw.y)) * 0.14 - smoothstep(0.72, 0.92, cfw.y) * 0.14;
        cobbleBase *= (0.88 + bevel * 0.16);
        float3 mortarCol = mix(float3(0.24, 0.25, 0.17), float3(0.32, 0.36, 0.18), meadowNoise(p * 0.18));
        float3 paved = mix(cobbleBase, mortarCol, mortar * 0.72);
        soil = mix(soil, paved, cobbleW * smoothstep(0.18, 0.62, coverage) * 0.86);
    }

    float sparse = smoothstep(0.42, 0.72, meadowNoise(p * 0.31)) * (1 - coverage * 0.78);
    float roadAlpha = coverage * (0.82 + patches * 0.10) * (1 - sparse * 0.65);
    float3 terrain = mix(grass, soil, roadAlpha);

    // Connected Valley Water System (mountain waterfall plunge -> winding river -> woodland lake)
    // Soft low-saturation painterly tones harmonized to MeadowGround so pixel heroes always pop cleanly!
    float waterRaw = mask.b * settings.x;
    if (waterRaw > 0.02) {
        float shoreNoise = meadowNoise(p * 0.18) * 0.6 + meadowNoise(p * 0.52) * 0.4;
        float sandMask = smoothstep(0.04 + shoreNoise * 0.10, 0.24 + shoreNoise * 0.08, waterRaw);
        float wetRimMask = smoothstep(0.20 + shoreNoise * 0.08, 0.34 + shoreNoise * 0.06, waterRaw);
        float waterMask = smoothstep(0.30 + shoreNoise * 0.08, 0.48 + shoreNoise * 0.05, waterRaw);

        // Warm sandy-pebble beach transitioning to wet mossy shore stones
        float3 sandCol = mix(float3(0.54, 0.49, 0.34), float3(0.65, 0.59, 0.42), meadowNoise(p * 0.12));
        float3 wetBank = mix(float3(0.27, 0.31, 0.20), float3(0.44, 0.43, 0.34), smoothstep(0.35, 0.78, meadowNoise(p * 0.34)));
        terrain = mix(terrain, sandCol, sandMask * (1.0 - waterMask * 0.8) * (1.0 - roadAlpha * 0.65) * 0.78);
        terrain = mix(terrain, wetBank, wetRimMask * (1.0 - waterMask * 0.75) * 0.68);

        // Calm painterly seafoam-turquoise shallows deepening to serene woodland teal lake heart
        float flow = u.sunTime.w * 7.5;
        float ripple1 = meadowNoise(float2(p.x * 0.13 + sin(p.y * 0.06 + u.sunTime.w * 0.6) * 1.3, p.y * 0.08 - flow * 0.22));
        float ripple2 = meadowNoise(float2(p.x * 0.24 - flow * 0.08, p.y * 0.15 - flow * 0.34 + 7.1));
        float depth = smoothstep(0.36, 0.90, waterRaw);
        float3 shallowCol = float3(0.24, 0.52, 0.51);
        float3 midCol = float3(0.16, 0.41, 0.45);
        float3 deepCol = float3(0.10, 0.29, 0.36);
        float3 water = mix(mix(shallowCol, midCol, smoothstep(0.0, 0.55, depth)), deepCol, smoothstep(0.45, 1.0, depth));

        // Gentle sunlit water ripples & subtle shallow shore foam glint
        float caustic = smoothstep(0.64, 0.88, ripple1 * 0.58 + ripple2 * 0.42);
        water = mix(water, float3(0.72, 0.87, 0.84), caustic * (0.28 + (1.0 - depth) * 0.16));
        float shoreFoam = smoothstep(0.30, 0.42, waterRaw) * (1.0 - smoothstep(0.42, 0.55, waterRaw)) * smoothstep(0.42, 0.75, ripple2);
        water = mix(water, float3(0.80, 0.90, 0.87), shoreFoam * 0.38);

        terrain = mix(terrain, water, waterMask * 0.94);
    }

    float cloud = smoothstep(0.25, 0.76, meadowNoise((p - float2(u.sunTime.w * 14, u.sunTime.w * 5)) * 0.0065));
    float light = 0.65 + cloud * 0.36 + exp(-length(p - float2(-100, -170)) * 0.0012) * 0.07;
    float3 base = terrain * light;
    float visibility = labVisibility(in.world, u, shadowMap);
    float marker = min(distance(p, float2(540, 300)), min(distance(p, float2(740, 300)), distance(p, float2(640, 440))));
    if (settings.y > 0.5 && marker < 8) return float4(0, 1, 1, 1);
    return float4(base * mix(float3(0.38, 0.44, 0.43), float3(1), visibility), 1);
}
