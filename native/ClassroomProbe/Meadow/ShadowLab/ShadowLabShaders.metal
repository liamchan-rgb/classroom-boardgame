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
    // Velvety 9-tap Gaussian-weighted PCF over the texel-snapped high-res shadow frustum eliminates edge shimmer!
    float2 texel = float2(u.options.y * 0.90);
    float depth = p.z - 0.00007;
    float v = shadowMap.sample_compare(comparison, uv, depth) * 4.0;
    v += shadowMap.sample_compare(comparison, uv + texel * float2(-1,  0), depth) * 2.0;
    v += shadowMap.sample_compare(comparison, uv + texel * float2( 1,  0), depth) * 2.0;
    v += shadowMap.sample_compare(comparison, uv + texel * float2( 0, -1), depth) * 2.0;
    v += shadowMap.sample_compare(comparison, uv + texel * float2( 0,  1), depth) * 2.0;
    v += shadowMap.sample_compare(comparison, uv + texel * float2(-1, -1), depth);
    v += shadowMap.sample_compare(comparison, uv + texel * float2( 1, -1), depth);
    v += shadowMap.sample_compare(comparison, uv + texel * float2(-1,  1), depth);
    v += shadowMap.sample_compare(comparison, uv + texel * float2( 1,  1), depth);
    return v * (1.0 / 16.0);
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
// Uses linear alpha filtering & damped canopy sway so tree shadows breathe smoothly without noisy texel flicker!
fragment void meadowCutoutShadowFragment(LabRaster in [[stage_in]], texture2d<float> art [[texture(0)]],
                                         constant LabUniforms &u [[buffer(1)]], constant float4 &settings [[buffer(2)]],
                                         constant float4 &atlasRect [[buffer(3)]]) {
    constexpr sampler smoothAlpha(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float height = 1 - uv.y;
    float root = smoothstep(0.08, 0.95, height);
    float gust = 0.78 + 0.22 * sin(u.sunTime.w * 0.42 + in.wind.y * 0.31);
    float sway = sin(u.sunTime.w * 1.15 + in.wind.y) + 0.20 * sin(u.sunTime.w * 2.05 + in.wind.y * 1.7);
    if (in.wind.x > 1.5) uv.y -= sin(uv.x * 10 - u.sunTime.w * 2.8 + in.wind.y) * 0.02 * uv.x;
    else uv.x += sway * 0.014 * gust * in.wind.x * root * root;
    float4 color = art.sample(smoothAlpha, atlasRect.xy + clamp(uv, 0.001, 0.999) * atlasRect.zw);
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
    float4 params;        // x = biomePhase, y = biomeBlendStrength, z = terrainFieldActive, w = unused
    float4 plunge;        // xy = waterfall plunge pool center, z = active (>0.5), w = unused
};

float3 sampleScatteredGround(texture2d<float> tex, sampler tile, float2 uv, float2 a, float2 b, float2 c, float2 d, float2 weight) {
    float3 sa = tex.sample(tile, uv + float2(meadowHash(a), meadowHash(a + 17.3))).rgb;
    float3 sb = tex.sample(tile, uv + float2(meadowHash(b), meadowHash(b + 17.3))).rgb;
    float3 sc = tex.sample(tile, uv + float2(meadowHash(c), meadowHash(c + 17.3))).rgb;
    float3 sd = tex.sample(tile, uv + float2(meadowHash(d), meadowHash(d + 17.3))).rgb;
    return mix(mix(sa, sb, weight.x), mix(sc, sd, weight.x), weight.y);
}

// Smooth organic pebble / river-stone synthesis for submerged riverbed & rocky embankments
float meadowVoronoiStone(float2 p) {
    float2 i = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0;
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            float2 g = float2(float(ox), float(oy));
            float2 o = float2(meadowHash(i + g + 1.3), meadowHash(i + g + 19.7));
            float2 r = g + o - f;
            float d = dot(r, r);
            if (d < d1) { d2 = d1; d1 = d; }
            else if (d < d2) { d2 = d; }
        }
    }
    return smoothstep(0.02, 0.24, sqrt(d2) - sqrt(d1));
}

// High-definition multi-octave curvilinear river wave height (continuous in streamS, ZERO segment breaks!)
float meadowStreamWave(float2 sn, float t) {
    // Primary smooth rolling downstream swell + diagonal V-chevron wakes + fine crisp HD capillary ripples
    float s = sn.y;
    float n = sn.x;
    float w1 = meadowNoise(float2(n * 0.088 + sin(s * 0.025 - t * 1.1) * 0.25, s * 0.048 - t * 1.85));
    float w2 = meadowNoise(float2(n * 0.165 - s * 0.018 + 6.4, s * 0.095 - t * 2.75) + 3.1);
    float w3 = meadowNoise(float2(n * 0.295 + s * 0.022 - 4.7, s * 0.185 - t * 3.95) + 11.7);
    float w4 = meadowNoise(float2(n * 0.540, s * 0.360 - t * 5.20) + 19.3);
    return w1 * 0.40 + w2 * 0.30 + w3 * 0.20 + w4 * 0.10;
}

// High-definition calm sunlit lake breeze ripples (omnidirectional continuous wave interference)
float meadowLakeWave(float2 p, float t) {
    float l1 = meadowNoise(p * float2(0.072, 0.105) + float2(-t * 0.42, -t * 0.28));
    float l2 = meadowNoise(p * float2(0.145, 0.195) + float2( t * 0.36, -t * 0.52) + 8.3);
    float l3 = meadowNoise(p * float2(0.280, 0.360) + float2(-t * 0.64,  t * 0.38) + 17.6);
    float l4 = meadowNoise(p * float2(0.520, 0.640) + float2( t * 0.85, -t * 0.72) + 29.1);
    return l1 * 0.38 + l2 * 0.30 + l3 * 0.21 + l4 * 0.11;
}

fragment float4 meadowGroundFragment(LabRaster in [[stage_in]], constant LabUniforms &u [[buffer(1)]],
                                    constant float4 &settings [[buffer(2)]],
                                    constant MeadowBiomeUniforms &biome [[buffer(3)]],
                                    texture2d<float> grassTexture [[texture(0)]],
                                    depth2d<float> shadowMap [[texture(1)]],
                                    texture2d<float> roadMask [[texture(2)]],
                                    texture2d<float> autumnTexture [[texture(3)]],
                                    texture2d<float> blossomTexture [[texture(4)]],
                                    texture2d<float> sanctumTexture [[texture(5)]],
                                    texture2d<float> terrainField [[texture(6)]],
                                    texture2d<float> cliffWallTexture [[texture(7)]],
                                    texture2d<float> waterFlow [[texture(8)]]) {
    constexpr sampler tile(coord::normalized, address::repeat, filter::linear);
    constexpr sampler maskSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler cliffSampler(coord::normalized, s_address::repeat, t_address::clamp_to_edge, filter::linear);
    float2 p = float2(in.world.x * 32 + 640, 360 - in.world.y * 32 * 0.8137334712);
    float worldH = settings.z > 0 ? settings.z : 1160.0;
    float2 maskUV = (p - float2(-160, -220)) / float2(1600.0, worldH);
    float4 mask = roadMask.sample(maskSampler, maskUV);

    // Pre-sample terrainField so upper mesa plateaus shift grass UV vertically for genuine 3/4 elevation parallax!
    float4 tField = float4(0.36, 0.5, 0.75, 0.0);
    float upperPlateauW = 0.0;
    if (biome.params.z > 0.5 && settings.x > 0.5) {
        tField = terrainField.sample(maskSampler, maskUV);
        if (mask.b < 0.05) {
            upperPlateauW = smoothstep(0.48, 0.78, tField.a);
        }
    }
    float2 pg = p - float2(0.0, upperPlateauW * 24.0);
    float2 cell = floor(pg / 190), weight = smoothstep(0.0, 1.0, fract(pg / 190));
    float2 uv = pg / 440;
    float2 a = cell, b = cell + float2(1, 0), c = cell + float2(0, 1), d = cell + 1;
    float3 grass = sampleScatteredGround(grassTexture, tile, uv, a, b, c, d, weight);

    // Coherent world-space biome blending matching RandomMap's biomeNoise + Boss Sanctum zones
    float biomeStrength = biome.params.y;
    if (biomeStrength > 0.01) {
        float phase = biome.params.x;
        float n1 = sin(pg.x * 0.0029 + phase) * cos(pg.y * 0.0031 - phase * 0.7);
        float n2 = sin((pg.x * 0.0017 - pg.y * 0.0021) + phase * 1.3);
        float edgeJitter = (meadowNoise(pg * 0.018) - 0.5) * 0.14;
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

    // Rich multi-scale living meadow undergrowth (clover cushions, moss beds, crisp micro-blades & wildflower flecks
    // so even small slivers of meadow between dense plant sprites read as lush living turf rather than bare lawn!)
    float meadowVar = meadowNoise(pg * 0.0037) * 0.58 + meadowNoise(pg * 0.015) * 0.42;
    float cloverPatch = smoothstep(0.46, 0.78, meadowNoise(pg * 0.048 + 4.1));
    float microBlade = meadowNoise(pg * float2(0.55, 0.28));
    grass = mix(grass, float3(0.22, 0.34, 0.13), 0.11 + (1.0 - meadowVar) * 0.10 + cloverPatch * 0.12);
    grass *= (0.93 + microBlade * 0.14);
    // Tiny sunlit clover-blossom & meadow-daisy pixel flecks woven organically into clover pockets
    float2 flCell = floor(pg * 0.34), flFrac = fract(pg * 0.34) - 0.5;
    float flPick = meadowHash(flCell + 13.7);
    float flDot = step(0.945, flPick) * (1.0 - smoothstep(0.10, 0.28, length(flFrac))) * cloverPatch;
    float3 flHue = flPick > 0.982 ? float3(0.96, 0.88, 0.48) : (flPick > 0.965 ? float3(0.94, 0.95, 0.88) : float3(0.76, 0.84, 0.96));
    grass = mix(grass, flHue, flDot * 0.58);
    grass = mix(float3(dot(grass, float3(0.299, 0.587, 0.114))), grass, 0.95);

    // -------------------------------------------------------------------------
    // 1. SILKY ROLLING HILLSHADING + HAND-PAINTED 32-BIT HD-2D 36px CLIFF TERRACES
    //    - Samples real seamless MapCliffWallTile (matching RockLow & MeadowGround pixel clusters!)
    //    - Closed raised-mesa visual cues: sunlit upper plateau parallax + subtle north back-rim bevel
    //      + 36px textured pixel-art south cliff wall + broad 26px directional SE cast shadow!
    // -------------------------------------------------------------------------
    float elevation = tField.r;
    float3 terrainNormal = float3(0.0, 0.0, 1.0);
    float hillShade = 1.0;
    float3 hillTint = float3(1.0);
    float cliffWallMask = 0.0;
    float3 cliffWallColor = float3(0.0);
    float terraceCastShadow = 1.0;
    float3 plateauLiftCol = float3(1.0);

    if (biome.params.z > 0.5 && settings.x > 0.5) {
        // Wide smooth finite-difference step (11px) eliminates every thin dark line artifact!
        float2 eps = float2(11.0 / 1600.0, 11.0 / worldH);
        float hL = terrainField.sample(maskSampler, maskUV - float2(eps.x, 0.0)).r;
        float hR = terrainField.sample(maskSampler, maskUV + float2(eps.x, 0.0)).r;
        float hU = terrainField.sample(maskSampler, maskUV - float2(0.0, eps.y)).r;
        float hD = terrainField.sample(maskSampler, maskUV + float2(0.0, eps.y)).r;
        float2 grad = float2(hR - hL, hD - hU);
        terrainNormal = normalize(float3(-grad.x * 10.5, -grad.y * 10.5, 1.0));
        float3 sunDir = normalize(float3(-0.68, -0.56, 0.74));
        float ndotl = dot(terrainNormal, sunDir);

        hillShade = clamp(0.85 + (ndotl - 0.58) * 0.38, 0.78, 1.14);
        float warmSide = smoothstep(0.58, 0.92, ndotl);
        float coolSide = 1.0 - smoothstep(0.28, 0.62, ndotl);
        hillTint = mix(float3(1.0), float3(1.06, 1.02, 0.92), warmSide * 0.62)
                 * mix(float3(1.0), float3(0.89, 0.94, 0.96), coolSide * 0.52);

        float alpineW = smoothstep(0.58, 0.90, elevation);
        grass = mix(grass, grass * float3(0.86, 0.93, 0.89), alpineW * 0.48);
        float valleyW = 1.0 - smoothstep(0.24, 0.42, elevation);
        grass = mix(grass, grass * float3(0.88, 0.95, 0.86), valleyW * 0.22);

        // TRUE 3/4-PERSPECTIVE TEXTURED MESA TERRACE (dry land only: mask.b < 0.05)
        if (mask.b < 0.05) {
            float wallH = 36.0; // Unmistakable 36px 1-tier JRPG vertical elevation step!
            float pHere = tField.a;
            // 6 vertical samples from pixel up to wallH north to recover exact smooth wall height V in [0=foot .. 1=lip]
            float s1 = terrainField.sample(maskSampler, maskUV - float2(0.0,  6.0 / worldH)).a;
            float s2 = terrainField.sample(maskSampler, maskUV - float2(0.0, 12.0 / worldH)).a;
            float s3 = terrainField.sample(maskSampler, maskUV - float2(0.0, 18.0 / worldH)).a;
            float s4 = terrainField.sample(maskSampler, maskUV - float2(0.0, 24.0 / worldH)).a;
            float s5 = terrainField.sample(maskSampler, maskUV - float2(0.0, 30.0 / worldH)).a;
            float pTop = terrainField.sample(maskSampler, maskUV - float2(0.0, wallH / worldH)).a;

            // Sun-kissed clarity on the elevated upper mesa so higher ground visibly rises toward the sky!
            plateauLiftCol = mix(float3(1.0), float3(1.10, 1.09, 1.02), upperPlateauW);

            // Closed back-rim bevel on NORTH edge of the mesa (prevents Escher sunken-trench illusion!)
            float pSouth9 = terrainField.sample(maskSampler, maskUV + float2(0.0, 9.0 / worldH)).a;
            float pSouth18 = terrainField.sample(maskSampler, maskUV + float2(0.0, 18.0 / worldH)).a;
            float northBackShadow = smoothstep(0.48, 0.82, max(pSouth9, pSouth18)) * (1.0 - smoothstep(0.32, 0.64, pHere));
            float northRimLit = smoothstep(0.55, 0.88, pHere) * (1.0 - smoothstep(0.25, 0.60, s1));
            grass = mix(grass, grass * float3(1.12, 1.14, 0.98), northRimLit * 0.45);

            // Exposed south-facing 36px hand-painted pixel-art granite cliff face!
            // Near tapered road hillside passages, `dropHeight = pTop - pHere` drops smoothly so the cliff face
            // PHYSICALLY SHRINKS IN VERTICAL HEIGHT into a crisp mossy granite wedge whose sunlit turf lip curves
            // naturally down into the grassy embankment BEFORE reaching the cobblestone road (ZERO scissor-cut!).
            float pTopL = terrainField.sample(maskSampler, maskUV + float2(-14.0 / 1600.0, -wallH / worldH)).a;
            float pTopR = terrainField.sample(maskSampler, maskUV + float2( 14.0 / 1600.0, -wallH / worldH)).a;
            float sideSlope = pTopL - pTopR; // >0 = cliff faces SE (shaded), <0 = cliff faces SW (sunlit!)
            float dropHeight = pTop - pHere;
            float cheekTaper = smoothstep(0.36, 0.84, dropHeight);
            float southFacing = 1.0 - smoothstep(0.62, 0.96, abs(sideSlope));
            float rawWall = smoothstep(0.42, 0.72, pTop) * (1.0 - smoothstep(0.36, 0.66, pHere)) * southFacing;
            if (rawWall > 0.01 && cheekTaper > 0.03) {
                // Smooth normalized height from cliff foot (0) to upper grass overhang lip (1)
                float wallV = clamp((pHere + s1 + s2 + s3 + s4 + s5) / 6.0, 0.0, 1.0);
                // Physically shrink the cliff's vertical band [vBot, vTop] as cheekTaper drops toward a road pass:
                // upper sunlit grass lip curves gracefully downward (65%) while rock foot lifts slightly onto the slope (35%)!
                float vBot = mix(0.34, 0.02, cheekTaper);
                float vTop = mix(0.38, 0.98, cheekTaper);
                float localV = clamp((wallV - vBot) / max(0.06, vTop - vBot), 0.0, 1.0);
                float wedgeMask = smoothstep(vBot - 0.03, vBot + 0.11, wallV)
                                * (1.0 - smoothstep(vTop - 0.12, vTop + 0.03, wallV))
                                * smoothstep(0.04, 0.24, cheekTaper);

                // Sample real seamless 32-bit HD-2D MapCliffWallTile (2:1 aspect -> 76px wide x 36px tall = 1:1 crisp pixels!)
                // Mapping localV keeps the sunlit green turf lip AND dark mossy talus intact all along the curving cheek!
                float cliffU = p.x / 76.0;
                float cliffV = clamp(1.0 - localV, 0.01, 0.99);
                float3 cliffTex = cliffWallTexture.sample(cliffSampler, float2(cliffU, cliffV)).rgb;

                // Subtle directional 3D curvature lighting: SW cliff bends catch warm sun, SE bends cool slate!
                float faceLight = clamp(1.0 - sideSlope * 0.36, 0.76, 1.18);
                float3 faceTint = sideSlope < 0.0
                    ? mix(float3(1.0), float3(1.08, 1.03, 0.94), clamp(-sideSlope, 0.0, 1.0) * 0.65)
                    : mix(float3(1.0), float3(0.86, 0.90, 0.96), clamp(sideSlope, 0.0, 1.0) * 0.65);
                cliffTex *= faceLight * faceTint;

                cliffWallMask = rawWall * wedgeMask;
                cliffWallColor = cliffTex;
            }

            // Lush mossy-grass hillside slope shading across tapered road-opening embankments
            // (bridges upper sunlit plateau smoothly down to the lower meadow between the two receding granite cheeks!)
            float gentleRamp = smoothstep(0.10, 0.36, dropHeight) * (1.0 - cheekTaper);
            grass = mix(grass, grass * float3(0.95, 1.01, 0.90), gentleRamp * 0.48);

            // Broad, soft directional SE cast shadow falling onto the lower meadow below the 36px raised mesa!
            // Tapers cleanly in lockstep with shrinking cliff cheeks so NO dark shadow tail sticks across road passes!
            float inLowerValley = 1.0 - smoothstep(0.32, 0.62, max(pHere, pTop));
            float sh1 = terrainField.sample(maskSampler, maskUV - float2( 7.0 / 1600.0, (wallH +  6.0) / worldH)).a;
            float sh2 = terrainField.sample(maskSampler, maskUV - float2(16.0 / 1600.0, (wallH + 15.0) / worldH)).a;
            float sh3 = terrainField.sample(maskSampler, maskUV - float2(25.0 / 1600.0, (wallH + 24.0) / worldH)).a;
            float sharpCliffHere = smoothstep(0.38, 0.78, sh1 - pHere);
            float castAmt = (smoothstep(0.45, 0.80, sh1) * 0.55 + smoothstep(0.45, 0.80, sh2) * 0.30 + smoothstep(0.45, 0.80, sh3) * 0.15) * inLowerValley * sharpCliffHere;
            terraceCastShadow = mix(1.0, 0.66, clamp(castAmt, 0.0, 1.0)) * mix(1.0, 0.86, northBackShadow * 0.72);
        }
    }

    // -------------------------------------------------------------------------
    // 2. ADVENTURE TRAILS (RURAL PACKED EARTH + STEPPING STONES + COBBLESTONES)
    // -------------------------------------------------------------------------
    float edge = meadowNoise(p * 0.23) * 0.58 + meadowNoise(p * 0.73) * 0.28 + meadowHash(floor(p * 1.6)) * 0.14;
    float coverage = smoothstep(0.10 + edge * 0.15, 0.56 + edge * 0.12, mask.r) * settings.x;
    float patches = meadowNoise(p * 0.045), fine = meadowHash(floor(p * 1.5));

    float3 soil = mix(float3(0.41, 0.35, 0.22), float3(0.62, 0.53, 0.34), patches * 0.64 + fine * 0.25);
    float cobbleRaw = smoothstep(0.51, 0.84, mask.g);
    float cobbleW = clamp(cobbleRaw * 1.16 - meadowNoise(p * 0.15) * 0.24 * (1.0 - cobbleRaw), 0.0, 1.0) * smoothstep(0.02, 0.14, cobbleRaw);
    float ruralWear = min(mask.g / 0.45, 1.0) * (1.0 - cobbleW);
    soil *= 1.0 - ruralWear * (0.04 + meadowNoise(p * 0.11) * 0.045);

    float shoulder = smoothstep(0.06, 0.30, coverage) * (1.0 - smoothstep(0.32, 0.68, coverage));
    soil = mix(soil, float3(0.27, 0.25, 0.16), shoulder * 0.38);
    float2 stoneCell = floor(p * 0.44), spot = fract(p * 0.44) - 0.5;
    float stones = step(0.92, meadowHash(stoneCell)) * (1.0 - smoothstep(0.10, 0.30, length(spot)));
    soil = mix(soil, float3(0.56, 0.53, 0.41), stones * 0.46);
    float2 stepGrid = p * 0.085;
    float2 sgCell = floor(stepGrid), sgFrac = fract(stepGrid) - 0.5;
    float2 sgJitter = float2(meadowHash(sgCell + 3.1), meadowHash(sgCell + 19.7)) - 0.5;
    float stepFlag = step(0.58, meadowHash(sgCell + 7.4)) * (1.0 - smoothstep(0.16, 0.31, length((sgFrac - sgJitter * 0.32) * float2(1.0, 1.35))));
    soil = mix(soil, float3(0.53, 0.50, 0.41), stepFlag * (1.0 - cobbleW) * coverage * 0.46);

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
        float3 cobbleBase = mix(float3(0.45, 0.43, 0.38), float3(0.60, 0.56, 0.47), tone);
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

    // Apply silky rolling hillshading, elevated sunlit mesa lift, and directional terrace cast shadow
    terrain *= hillShade * hillTint * plateauLiftCol * terraceCastShadow;
    // Composite the hand-painted 32-bit pixel-art 36px cliff face, smoothly feathering off right along road edges
    // with a subtle mossy-earth kerb transition where rocky cheeks meet the sloped cobblestone ramp!
    if (cliffWallMask > 0.01) {
        float roadFeather = smoothstep(0.04, 0.42, coverage);
        float wallMix = cliffWallMask * (1.0 - roadFeather);
        // Subtle natural dark-moss kerb seam right where tapered rocky cliff cheeks hug the sloped road edge
        float cheekMoss = cliffWallMask * smoothstep(0.02, 0.24, coverage) * (1.0 - smoothstep(0.24, 0.55, coverage));
        terrain = mix(terrain, float3(0.23, 0.28, 0.14) * hillShade, cheekMoss * 0.45);
        terrain = mix(terrain, cliffWallColor, wallMix);
    }

    // -------------------------------------------------------------------------
    // 3. SEAMLESS HD CRYSTAL-CLEAR SHIMMERING WATER
    //    - 16-bit smooth-union water depth & continuous curvilinear river (S, N) from texture(8):
    //      ZERO segment splicing seams, ZERO hard bank border line, waves flow continuously around every bend!
    //    - Crystal-clear luminous alpine jade-turquoise water with crisp refracted pebbles & sunlit caustics
    //    - Dramatic, dazzling sunlit wave specular reflections & sparkling diamond water facets
    //    - Energetic waterfall plunge-pool churn rings seamlessly feeding into splash, mist & rainbow VFX!
    // -------------------------------------------------------------------------
    float4 wfData = biome.params.w > 0.5 ? waterFlow.sample(maskSampler, maskUV) : float4(mask.b, 0.5, 0.5, 0.5);
    float waterRaw = (biome.params.w > 0.5 ? wfData.r : mask.b) * settings.x;
    float cloud = smoothstep(0.22, 0.80, meadowNoise((p - float2(u.sunTime.w * 6.0, u.sunTime.w * 2.2)) * 0.0055));
    if (waterRaw > 0.012) {
        float t = u.sunTime.w;
        float streamS = wfData.g * 4096.0 - 128.0;
        float streamN = wfData.b * 512.0 - 256.0;
        float flowStr = biome.params.w > 0.5 ? clamp(wfData.a, 0.0, 1.0) : 0.6;
        float turb = clamp(flowStr * 0.72 + (biome.params.w > 0.5 ? 0.0 : tField.a * 0.35), 0.0, 1.0);

        // Soft organic shoreline breakup (NO heavy dark border line!)
        float shoreBreak = (meadowNoise(p * 0.15) * 0.62 + meadowNoise(p * 0.44) * 0.38 - 0.5) * 0.070;
        float wEff = clamp(waterRaw + shoreBreak, 0.0, 1.0);

        // 3a. Delicate damp earth/pebble edge blending seamlessly into crystal-clear shallow water (ZERO hard border!)
        float wetShore = smoothstep(0.01, 0.16, wEff);
        float waterSurface = smoothstep(0.07, 0.25, wEff);
        float openWater = smoothstep(0.16, 0.36, wEff);
        float pebblePat = meadowVoronoiStone(p * 0.24);
        float3 wetStones = mix(float3(0.28, 0.29, 0.22), float3(0.48, 0.46, 0.36), pebblePat * 0.7 + meadowNoise(p * 0.42) * 0.3);
        float3 dampBank = mix(terrain * 0.80, wetStones, smoothstep(0.05, 0.18, wEff) * 0.42);
        terrain = mix(terrain, dampBank, wetShore * (1.0 - waterSurface * 0.85));

        if (waterSurface > 0.005) {
            // 3b. Continuous curvilinear river wavefield seamlessly crossfading into sunlit lake ripples!
            //     Evaluates exact analytical gradient in world/stream space -> ZERO segment phase discontinuities!
            float2 sn = float2(streamN, streamS);
            float eS = 1.45; // Crisp high-definition finite difference step for razor-sharp HD ripples
            float hRiverC = meadowStreamWave(sn, t);
            float hRiverN = meadowStreamWave(sn + float2(eS, 0.0), t);
            float hRiverS = meadowStreamWave(sn + float2(0.0, eS), t);

            float hLakeC = meadowLakeWave(p, t);
            float hLakeX = meadowLakeWave(p + float2(eS, 0.0), t);
            float hLakeY = meadowLakeWave(p + float2(0.0, eS), t);

            float hC = mix(hLakeC, hRiverC, flowStr);
            float dWaveX = mix(hLakeC - hLakeX, hRiverC - hRiverN, flowStr);
            float dWaveY = mix(hLakeC - hLakeY, hRiverC - hRiverS, flowStr);
            float waveAmp = mix(2.55, 3.85, flowStr);
            float3 waterNormal = normalize(float3(dWaveX * waveAmp, dWaveY * waveAmp, 1.0));

            // 3c. Crystal-clear refracted riverbed (crisp sunlit pebbles, warm golden silt & dancing caustics!)
            float depth = smoothstep(0.08, 0.92, wEff);
            float2 refractP = p + waterNormal.xy * (7.0 + depth * 10.0);
            float bedPebble = meadowVoronoiStone(refractP * 0.24) * 0.62 + meadowVoronoiStone(refractP * 0.54) * 0.38;
            float bedTone = meadowNoise(refractP * 0.075);
            float3 riverBed = mix(float3(0.24, 0.29, 0.21), float3(0.54, 0.51, 0.38), bedPebble * 0.66 + bedTone * 0.34);

            // Vivid animated sunlit caustic web flowing seamlessly downstream along streamS!
            float cRiver = meadowNoise(float2(streamN * 0.24, streamS * 0.15 - t * 2.45) + waterNormal.xy * 1.6)
                         * 0.55 + meadowNoise(float2(streamN * 0.38 + 5.1, streamS * 0.25 - t * 3.55) - waterNormal.xy * 1.3) * 0.45;
            float cLake  = meadowNoise(p * 0.20 + waterNormal.xy * 1.6 - float2(t * 0.55, t * 0.35))
                         * 0.55 + meadowNoise(p * 0.34 - waterNormal.xy * 1.4 + float2(t * 0.42, -t * 0.48) + 4.3) * 0.45;
            float caustRaw = mix(cLake, cRiver, flowStr);
            float caustics = pow(smoothstep(0.46, 0.84, caustRaw), 2.3) * (1.0 - depth * 0.48) * (0.68 + cloud * 0.32);
            riverBed += float3(0.28, 0.44, 0.38) * caustics * 0.95;

            // 3d. Crystal-clear jewel Beer-Lambert absorption (clear translucent turquoise-emerald -> deep sapphire-teal, NEVER milky!)
            float opticalDepth = depth * 1.55;
            float3 transmittance = exp(-opticalDepth * float3(2.40, 0.86, 0.64));
            float3 shallowJewel = float3(0.085, 0.42, 0.46);
            float3 deepJewel    = float3(0.028, 0.18, 0.28);
            float3 scatterCol   = mix(shallowJewel, deepJewel, smoothstep(0.24, 0.96, depth));
            float3 waterBody = riverBed * transmittance + scatterCol * (1.0 - transmittance);
            // Subtle sunlit emerald-cyan subsurface glow strictly on illuminated wave crests
            float crestSSS = pow(smoothstep(0.56, 0.92, hC), 2.2) * (0.55 + cloud * 0.45);
            waterBody += float3(0.06, 0.24, 0.26) * crestSSS * 0.45 * openWater;

            // 3e. Clean sky & sunlit cloud Fresnel reflection (keeps jewel water rich & transparent, never white-washed!)
            float3 viewDir = normalize(float3(0.0, 0.44, 0.90));
            float fresnel = pow(1.0 - clamp(dot(waterNormal, viewDir), 0.0, 1.0), 2.6);
            float skyPatch = smoothstep(0.30, 0.82, meadowNoise((p * 0.009) + waterNormal.xy * 0.85 - float2(t * 0.04, t * 0.015)));
            float3 skyRefl = mix(float3(0.14, 0.34, 0.40), float3(0.56, 0.78, 0.86), skyPatch * (0.55 + cloud * 0.45));
            float3 waterCol = mix(waterBody, skyRefl, clamp(0.08 + fresnel * 0.36, 0.0, 0.42) * openWater);

            // 3f. HIGH-CONTRAST EXAGGERATED SUNLIT WAVE REFLECTIONS & DAZZLING DIAMOND SPARKLES!
            //     Grazing golden-hour sun angle ensures flat troughs stay deep crystal turquoise while ONLY
            //     sunlit wave slopes & crests ignite into brilliant golden-white reflections (zero white-out!)
            float3 sunDirW = normalize(float3(-0.76, -0.52, 0.38));
            float3 halfVec = normalize(sunDirW + viewDir);
            float ndoth = max(dot(waterNormal, halfVec), 0.0);
            float sunBoost = 0.78 + cloud * 0.35;
            // Tight glossy golden-white highlight ribbons rolling down sunlit wave crests
            float crestSheen = pow(ndoth, 24.0) * 0.72 * sunBoost * openWater;
            // Razor-sharp mirror-like sun glints right on sunlit ripple peaks
            float crispSpec = pow(ndoth, 96.0) * 2.40 * sunBoost * openWater;
            // Exaggerated crisp high-definition diamond sun sparkles twinkling continuously along the flowing waves!
            float microFacet = mix(
                meadowNoise(p * 0.72 + waterNormal.xy * 3.5 - float2(t * 1.4, t * 0.9)),
                meadowNoise(float2(streamN * 0.62, streamS * 0.48 - t * 5.6) + waterNormal.xy * 3.0),
                flowStr
            );
            float diamondGlint = pow(smoothstep(0.66, 0.92, microFacet * 0.58 + hC * 0.42), 4.6)
                               * (0.85 + flowStr * 0.45) * sunBoost * openWater;
            waterCol += float3(0.98, 0.94, 0.76) * crestSheen;
            waterCol += float3(1.00, 0.99, 0.88) * (crispSpec + diamondGlint * 1.45);

            // 3g. Delicate continuous rapid aerated ribbons & roaring waterfall plunge-pool churn rings!
            float foam = 0.0;
            if (flowStr > 0.30) {
                float rRibbon1 = meadowNoise(float2(streamN * 0.21, streamS * 0.058 - t * 2.45));
                float rRibbon2 = meadowNoise(float2(streamN * 0.36 + 4.3, streamS * 0.10 - t * 3.65));
                float rapidFoam = smoothstep(0.68, 0.89, rRibbon1 * 0.58 + rRibbon2 * 0.42)
                                * smoothstep(0.30, 0.78, flowStr) * smoothstep(0.28, 0.58, wEff);
                foam = max(foam, rapidFoam * 0.36);
            }
            // Churning concentric splash rings radiating energetically out from the waterfall plunge junction!
            if (biome.plunge.z > 0.5) {
                float2 dp = (p - biome.plunge.xy) * float2(0.86, 1.15);
                float pd = length(dp);
                if (pd < 74.0) {
                    float falloff = 1.0 - smoothstep(6.0, 68.0, pd);
                    float ringWave = 0.5 + 0.5 * sin(pd * 0.38 - t * 7.2 + hC * 3.6);
                    float splashNoise = meadowNoise(dp * 0.16 - float2(0.0, t * 2.8));
                    float coreChurn = (1.0 - smoothstep(4.0, 28.0, pd)) * smoothstep(0.26, 0.72, splashNoise);
                    float outerRings = pow(ringWave, 3.0) * falloff * smoothstep(0.34, 0.76, splashNoise);
                    foam = max(foam, clamp(coreChurn * 0.90 + outerRings * 0.65, 0.0, 0.94));
                }
            }
            // Delicate broken shoreline sparkle-froth (never a solid contour line!)
            float edgeFroth = smoothstep(0.14, 0.22, wEff) * (1.0 - smoothstep(0.24, 0.34, wEff))
                            * smoothstep(0.62, 0.88, hC) * (0.18 + flowStr * 0.30);
            foam = max(foam, edgeFroth * 0.36);

            float3 foamCol = mix(float3(0.84, 0.95, 0.95), float3(1.00, 0.99, 0.95), 0.45 + cloud * 0.55);
            waterCol = mix(waterCol, foamCol, clamp(foam, 0.0, 0.88));

            terrain = mix(terrain, waterCol, waterSurface);
        }
    }

    float light = 0.78 + cloud * 0.24 + exp(-length(p - float2(-100, -170)) * 0.0012) * 0.06;
    float3 base = terrain * light;
    float visibility = labVisibility(in.world, u, shadowMap);
    float marker = min(distance(p, float2(540, 300)), min(distance(p, float2(740, 300)), distance(p, float2(640, 440))));
    if (settings.y > 0.5 && marker < 8) return float4(0, 1, 1, 1);
    return float4(base * mix(float3(0.42, 0.48, 0.47), float3(1), visibility), 1);
}
