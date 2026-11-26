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

// Multi-octave flow-advected water wave height (used for analytical refraction normal & sun glints)
float meadowWaveHeight(float2 q, float t) {
    float n1 = meadowNoise(q * 1.15 + float2(0.0, -t * 0.22));
    float n2 = meadowNoise(q * 2.45 + float2(t * 0.14, -t * 0.35) + 7.4);
    float n3 = meadowNoise(q * 5.20 - float2(t * 0.26, t * 0.18) + 19.1);
    return n1 * 0.54 + n2 * 0.31 + n3 * 0.15;
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
                                    texture2d<float> cliffWallTexture [[texture(7)]]) {
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

    // Subtle organic meadow variation (clover patches, wild moss, dry sunlit grass tufts)
    float meadowVar = meadowNoise(pg * 0.0037) * 0.65 + meadowNoise(pg * 0.014) * 0.35;
    grass = mix(grass, float3(0.24, 0.33, 0.13), 0.10 + (1.0 - meadowVar) * 0.09);
    grass = mix(float3(dot(grass, float3(0.299, 0.587, 0.114))), grass, 0.93);

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
    // 3. REALISTIC PHYSICALLY-INSPIRED FLOWING WATER (ZERO CARTOON CYAN!)
    //    - Wet darkened mossy/pebble riverbank + recessed NW bank cast shadow
    //    - Dual-phase directional flow-map advection along exact river curve
    //    - Underwater refracted river pebbles + drifting sunlight caustics
    //    - Beer-Lambert exponential depth absorption into moody mountain slate-teal
    //    - Fresnel sky/canopy reflection + crisp golden sun specular wave glints
    //    - Churning concentric waterfall plunge-pool foam rings & rapid whitewater
    // -------------------------------------------------------------------------
    float waterRaw = mask.b * settings.x;
    float cloud = smoothstep(0.25, 0.76, meadowNoise((p - float2(u.sunTime.w * 14, u.sunTime.w * 5)) * 0.0065));
    if (waterRaw > 0.015) {
        float t = u.sunTime.w;
        float turb = tField.a;
        float2 flowDir = (tField.gb * 2.0 - 1.0);
        float flowMag = length(flowDir);
        float2 flowUnit = flowMag > 0.05 ? (flowDir / flowMag) : float2(0.0, 1.0);
        float flowSpeed = mix(0.22, 1.15, clamp(flowMag * 0.85 + turb * 0.55, 0.0, 1.0));

        float shoreBreak = (meadowNoise(p * 0.16) * 0.62 + meadowNoise(p * 0.48) * 0.38 - 0.5) * 0.11;
        float wEff = clamp(waterRaw + shoreBreak, 0.0, 1.0);

        // 3a. Natural wet darkened ground & river-worn pebble shore (no cartoonish bright cream stripe!)
        float wetShore = smoothstep(0.02, 0.24, wEff);
        float waterSurface = smoothstep(0.21, 0.34, wEff);
        float pebblePat = meadowVoronoiStone(p * 0.19);
        float3 wetStones = mix(float3(0.20, 0.21, 0.17), float3(0.36, 0.35, 0.28), pebblePat * 0.7 + meadowNoise(p * 0.35) * 0.3);
        // Darken real terrain where water soaks the bank + blend natural wet riverbank stones
        float3 soakedGround = mix(terrain * 0.62, wetStones, smoothstep(0.10, 0.25, wEff) * 0.65);
        // Recessed riverbank shadow cast along NW/N edge by top-left sun
        float bankShadow = 1.0 - smoothstep(0.16, 0.30, wEff) * (1.0 - smoothstep(0.32, 0.52, wEff)) * clamp(-terrainNormal.x * 1.4 - terrainNormal.y * 1.4, 0.0, 1.0) * 0.48;
        terrain = mix(terrain, soakedGround * bankShadow, wetShore * (1.0 - waterSurface * 0.85));

        if (waterSurface > 0.005) {
            // 3b. Dual-phase flow-map UV advection (seamless infinite downstream motion!)
            float cycleRate = 0.38;
            float ph0 = fract(t * cycleRate);
            float ph1 = fract(t * cycleRate + 0.5);
            float blend = abs(2.0 * ph0 - 1.0);
            float2 flowStep = flowUnit * (flowSpeed * 42.0);
            float2 q0 = (p - flowStep * ph0) * 0.082;
            float2 q1 = (p - flowStep * ph1) * 0.082 + float2(11.3, 5.7);

            // Analytical water surface normal from dual-phase wave heightfield
            float hC = mix(meadowWaveHeight(q0, t), meadowWaveHeight(q1, t), blend);
            float hX = mix(meadowWaveHeight(q0 + float2(0.18, 0.0), t), meadowWaveHeight(q1 + float2(0.18, 0.0), t), blend);
            float hY = mix(meadowWaveHeight(q0 + float2(0.0, 0.18), t), meadowWaveHeight(q1 + float2(0.0, 0.18), t), blend);
            float waveAmp = mix(1.35, 2.55, turb);
            float3 waterNormal = normalize(float3((hC - hX) * waveAmp, (hC - hY) * waveAmp, 1.0));

            // 3c. Underwater refracted riverbed (submerged pebbles, silt & moss visible through clear shallows!)
            float depth = smoothstep(0.22, 0.94, wEff);
            float2 refractP = p + waterNormal.xy * (10.0 + depth * 12.0);
            float bedPebble = meadowVoronoiStone(refractP * 0.15) * 0.65 + meadowVoronoiStone(refractP * 0.36) * 0.35;
            float bedTone = meadowNoise(refractP * 0.065);
            float3 riverBed = mix(float3(0.16, 0.18, 0.13), float3(0.39, 0.37, 0.27), bedPebble * 0.68 + bedTone * 0.32);

            // Shimmering animated sunlight caustics dancing over the shallow/mid riverbed
            float c0 = meadowNoise(q0 * 2.1 + waterNormal.xy * 1.4);
            float c1 = meadowNoise(q1 * 2.1 + waterNormal.xy * 1.4 + 4.2);
            float caustRaw = mix(c0, c1, blend);
            float caustics = pow(smoothstep(0.46, 0.88, caustRaw), 2.4) * (1.0 - depth * 0.72) * (0.45 + cloud * 0.55);
            riverBed += float3(0.22, 0.25, 0.18) * caustics * 0.85;

            // 3d. Physically-inspired Beer-Lambert depth absorption (crystal olive-clear -> rich alpine slate-emerald!)
            float opticalDepth = depth * 1.85;
            float3 transmittance = exp(-opticalDepth * float3(2.85, 1.38, 1.18));
            float3 deepScatter = mix(float3(0.065, 0.175, 0.185), float3(0.032, 0.095, 0.125), smoothstep(0.35, 1.0, depth));
            float3 waterBody = riverBed * transmittance + deepScatter * (1.0 - transmittance);

            // 3e. Fresnel sky, cloud & dark overhanging forest-canopy reflection
            float3 viewDir = normalize(float3(0.0, 0.44, 0.90));
            float fresnel = pow(1.0 - clamp(dot(waterNormal, viewDir), 0.0, 1.0), 2.6);
            float skyPatch = smoothstep(0.28, 0.80, meadowNoise((p * 0.008) + waterNormal.xy * 0.65 - float2(t * 0.06, t * 0.02)));
            float3 skyRefl = mix(float3(0.14, 0.22, 0.19), float3(0.56, 0.65, 0.64), skyPatch * (0.45 + cloud * 0.55));
            // Darken reflection right under north/west shoreline banks (trees & cliffs reflecting in edge water!)
            float bankEdge = 1.0 - smoothstep(0.22, 0.44, wEff);
            skyRefl = mix(skyRefl, float3(0.07, 0.12, 0.09), bankEdge * 0.55);
            float3 waterCol = mix(waterBody, skyRefl, clamp(0.14 + fresnel * 0.56, 0.0, 0.64));

            // 3f. Crisp golden sunlight specular wave glints twinkling downstream
            float3 sunDirW = normalize(float3(-0.62, -0.52, 0.58));
            float3 halfVec = normalize(sunDirW + viewDir);
            float spec = pow(max(dot(waterNormal, halfVec), 0.0), 42.0) * (0.35 + cloud * 0.75);
            float microSpec = pow(smoothstep(0.68, 0.94, hC), 4.0) * (0.18 + turb * 0.35) * (0.4 + cloud * 0.6);
            waterCol += float3(0.95, 0.91, 0.76) * (spec * 0.72 + microSpec * 0.28);

            // 3g. Animated waterfall plunge-pool concentric churn rings & narrow rapid white-water streaks!
            float foam = 0.0;
            // Subtle aerated current ribbons in fast river rapids
            if (turb > 0.18) {
                float streak0 = meadowNoise(float2(dot(p, float2(-flowUnit.y, flowUnit.x)) * 0.18,
                                                 dot(p, flowUnit) * 0.055 - t * 2.2));
                float streak1 = meadowNoise(float2(dot(p, float2(-flowUnit.y, flowUnit.x)) * 0.30 + 5.1,
                                                 dot(p, flowUnit) * 0.09 - t * 3.1));
                float rapidFoam = smoothstep(0.62, 0.86, streak0 * 0.58 + streak1 * 0.42) * smoothstep(0.18, 0.62, turb) * smoothstep(0.28, 0.55, wEff);
                foam = max(foam, rapidFoam * 0.42);
            }
            // Churning concentric splash rings expanding outward from the exact waterfall impact point!
            if (biome.plunge.z > 0.5) {
                float2 dp = (p - biome.plunge.xy) * float2(0.88, 1.18);
                float pd = length(dp);
                if (pd < 68.0) {
                    float falloff = (1.0 - smoothstep(6.0, 62.0, pd));
                    float ringWave = 0.5 + 0.5 * sin(pd * 0.36 - t * 6.8 + hC * 4.2);
                    float splashNoise = meadowNoise(dp * 0.14 - float2(0.0, t * 2.6));
                    float coreChurn = (1.0 - smoothstep(4.0, 26.0, pd)) * smoothstep(0.32, 0.76, splashNoise);
                    float outerRings = pow(ringWave, 3.2) * falloff * smoothstep(0.36, 0.78, splashNoise);
                    foam = max(foam, clamp(coreChurn * 0.88 + outerRings * 0.62, 0.0, 0.92));
                }
            }
            // Delicate broken water-lip froth right along shallow rocky edges
            float edgeFroth = smoothstep(0.22, 0.30, wEff) * (1.0 - smoothstep(0.30, 0.40, wEff)) * smoothstep(0.56, 0.84, hC) * (0.20 + turb * 0.45);
            foam = max(foam, edgeFroth * 0.45);

            float3 foamCol = mix(float3(0.76, 0.83, 0.81), float3(0.94, 0.95, 0.90), 0.35 + cloud * 0.65);
            waterCol = mix(waterCol, foamCol, clamp(foam, 0.0, 0.88));

            terrain = mix(terrain, waterCol, waterSurface);
        }
    }

    float light = 0.65 + cloud * 0.36 + exp(-length(p - float2(-100, -170)) * 0.0012) * 0.07;
    float3 base = terrain * light;
    float visibility = labVisibility(in.world, u, shadowMap);
    float marker = min(distance(p, float2(540, 300)), min(distance(p, float2(740, 300)), distance(p, float2(640, 440))));
    if (settings.y > 0.5 && marker < 8) return float4(0, 1, 1, 1);
    return float4(base * mix(float3(0.38, 0.44, 0.43), float3(1), visibility), 1);
}
