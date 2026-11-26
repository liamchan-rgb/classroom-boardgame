import SpriteKit

/// One directional sun drives surface light and every ground projection.
enum MeadowSun {
    static let cast = CGVector(dx: 0.86, dy: 0.62)

    /// Keep ground shadow direction rock-steady so static shadows never swim or flicker across shadow-map texels.
    static func cast(at time: TimeInterval) -> CGVector {
        _ = time
        return cast
    }
}

final class EnvironmentShaders {
    let ground: SKShader
    let vegetation: SKShader
    let meadowPlants: SKShader
    let shadow: SKShader
    let contact: SKShader
    let soil: SKShader
    let backMist: SKShader
    let frontMist: SKShader
    let sunlight: SKShader
    let waterfall: SKShader
    let waterfallMist: SKShader
    private(set) var currentCast = MeadowSun.cast

    private static let noise = """
    float hash21(vec2 p) {
        vec3 q = fract(vec3(p.xyx) * 0.1031);
        q += dot(q, q.yzx + 33.33);
        return fract((q.x + q.y) * q.z);
    }
    float noise21(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
                   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
    }
    float meadowCloud(vec2 p, float t) {
        return noise21((p - vec2(t * 6.0, t * 2.2)) * 0.0055);
    }
    float sunStrength(vec2 p, float t) {
        float cloud = smoothstep(0.22, 0.80, meadowCloud(p, t));
        float warmth = exp(-length(p - vec2(-100.0, -170.0)) * 0.0012);
        return 0.78 + cloud * 0.24 + warmth * 0.06;
    }
    float canopyBend(float height, float t, float phase, float wind) {
        float root = smoothstep(0.06, 0.95, height);
        float gust = 0.74 + 0.26 * sin(t * 0.47 + phase * 0.31);
        float sway = sin(t * 1.55 + phase) + 0.28 * sin(t * 2.73 + phase * 1.7);
        return sway * 0.052 * gust * wind * root * root;
    }
    """

    init(worldHeight: CGFloat = 1160) {
        func clock() -> SKUniform { SKUniform(name: "u_sceneTime", float: 0) }
        let attributes = [SKAttribute(name: "a_origin", type: .vectorFloat2),
                          SKAttribute(name: "a_extent", type: .vectorFloat2),
                          SKAttribute(name: "a_wind", type: .float),
                          SKAttribute(name: "a_phase", type: .float)]
        let vegetationSource = Self.noise + """
        void main() {
            vec2 uv = v_tex_coord;
            if (a_wind > 1.5) {
                uv.y += sin(uv.x * 10.0 - u_sceneTime * 3.8 + a_phase) * 0.04 * uv.x;
            } else {
                uv.x += canopyBend(uv.y, u_sceneTime, a_phase, a_wind);
            }
            uv = clamp(uv, 0.001, 0.999);
            vec4 color = texture2D(u_texture, uv);
            vec2 p = a_origin + vec2((v_tex_coord.x - 0.5) * a_extent.x, (0.5 - v_tex_coord.y) * a_extent.y);
            if (GROUND_BLEND_ENABLED) {
                float breakup = noise21(p * 0.62 + vec2(a_phase, a_phase * 0.37));
                float fadeStart = 0.018 + breakup * 0.055;
                float groundFade = smoothstep(fadeStart, fadeStart + 0.11, v_tex_coord.y);
                color.rgb *= groundFade;
                color.a *= groundFade;
            }
            float light = sunStrength(p, u_sceneTime);
            float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
            color.rgb = mix(vec3(gray), color.rgb, 0.94) * mix(vec3(0.91, 0.97, 1.03), vec3(1.08, 1.025, 0.92), smoothstep(0.78, 1.08, light)) * light;
            gl_FragColor = color;
        }
        """
        let baseVegetationSource = vegetationSource.replacingOccurrences(of: "GROUND_BLEND_ENABLED", with: "false")
        let meadowPlantSource = vegetationSource.replacingOccurrences(of: "GROUND_BLEND_ENABLED", with: "true")
        vegetation = SKShader(source: baseVegetationSource, uniforms: [clock()])
        meadowPlants = SKShader(source: meadowPlantSource, uniforms: [clock()])
        vegetation.attributes = attributes
        meadowPlants.attributes = attributes

        ground = SKShader(source: Self.noise + """
        void main() {
            vec2 p = vec2(-160.0, \(worldHeight-220)) + v_tex_coord * vec2(1600.0, -\(worldHeight));
            vec2 grid = p / 190.0, cell = floor(grid);
            vec2 weight = smoothstep(vec2(0.0), vec2(1.0), fract(grid));
            vec2 uv = p / 440.0;
            vec2 a = cell, b = cell + vec2(1.0, 0.0), c = cell + vec2(0.0, 1.0), d = cell + vec2(1.0);
            vec3 sa = texture2D(u_texture, fract(uv + vec2(hash21(a), hash21(a + 17.3)))).rgb;
            vec3 sb = texture2D(u_texture, fract(uv + vec2(hash21(b), hash21(b + 17.3)))).rgb;
            vec3 sc = texture2D(u_texture, fract(uv + vec2(hash21(c), hash21(c + 17.3)))).rgb;
            vec3 sd = texture2D(u_texture, fract(uv + vec2(hash21(d), hash21(d + 17.3)))).rgb;
            vec3 grass = mix(mix(sa, sb, weight.x), mix(sc, sd, weight.x), weight.y);
            float meadow = noise21(p * 0.0037);
            grass = mix(grass, vec3(0.25, 0.34, 0.12), 0.15 + (1.0 - meadow) * 0.10);
            float gray = dot(grass, vec3(0.299, 0.587, 0.114));
            grass = mix(vec3(gray), grass, 0.88) * sunStrength(p, u_sceneTime);
            gl_FragColor = vec4(grass, 1.0);
        }
        """, uniforms: [clock()])

        shadow = SKShader(source: Self.noise + """
        void main() {
            float projectedHeight = a_body.y * (1.0 - a_body.z);
            vec2 local = (v_tex_coord - vec2(0.5)) * a_extent
                       + vec2(projectedHeight * a_cast.x * 0.5,
                              -projectedHeight * a_cast.y * 0.5);
            float height = -local.y / max(a_cast.y, 0.05);
            vec2 uv = vec2(0.5 + (local.x - height * a_cast.x) / (a_body.x * a_body.w), a_body.z + height / a_body.y);
            if (a_foliage > 0.5) {
                uv.x += canopyBend(uv.y, u_sceneTime, a_phase, a_wind);
            }
            float elevation = clamp(uv.y - a_body.z, 0.0, 1.0);
            float radius = mix(0.35, a_cast.z, elevation);
            vec2 blur = vec2(radius / a_body.x, radius / (a_body.y * max(a_cast.y, 0.05)));
            // Keep every texture lookup inside main: SpriteKit translates these
            // to Metal texture objects and cannot translate sampler parameters.
            float mask = 0.0;
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    vec2 tap = uv + blur * vec2(float(x), float(y));
                    float inside = step(0.0, tap.x) * step(tap.x, 1.0) * step(0.0, tap.y) * step(tap.y, 1.0);
                    vec2 sampleUV = clamp(tap, 0.001, 0.999);
                    float alpha = texture2D(u_texture, sampleUV).a;
                    float weight = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0);
                    mask += alpha * inside * weight;
                }
            }
            mask /= 16.0;
            if (a_foliage > 0.5) {
                float leaf = noise21(uv * vec2(52.0, 47.0) + vec2(sin(u_sceneTime * 1.4 + a_phase) * 0.65, 0.0));
                mask *= mix(1.0, 0.40 + smoothstep(0.20, 0.62, leaf) * 0.60, smoothstep(0.25, 0.50, elevation));
            }
            vec2 p = a_origin + vec2((v_tex_coord.x - 0.5) * a_extent.x, (0.5 - v_tex_coord.y) * a_extent.y);
            float direct = smoothstep(0.20, 0.78, meadowCloud(p, u_sceneTime));
            float alpha = mask * a_cast.w * mix(0.72, 1.0, direct) * mix(1.0, 0.83, elevation);
            gl_FragColor = vec4(vec3(0.075, 0.105, 0.080) * alpha, alpha);
        }
        """, uniforms: [clock()])
        shadow.attributes = [SKAttribute(name: "a_origin", type: .vectorFloat2), SKAttribute(name: "a_extent", type: .vectorFloat2),
                             SKAttribute(name: "a_body", type: .vectorFloat4), SKAttribute(name: "a_cast", type: .vectorFloat4),
                             SKAttribute(name: "a_foliage", type: .float), SKAttribute(name: "a_phase", type: .float),
                             SKAttribute(name: "a_wind", type: .float)]
        contact = SKShader(source: """
        void main() {
            float radius = length((v_tex_coord - vec2(0.5)) * 2.0);
            float alpha = (1.0 - smoothstep(0.08, 1.0, radius)) * 0.46;
            gl_FragColor = vec4(vec3(0.065, 0.085, 0.055) * alpha, alpha);
        }
        """)

        soil = SKShader(source: Self.noise + """
        void main() {
            vec2 p = vec2(-160.0, \(worldHeight-220)) + v_tex_coord * vec2(1600.0, -\(worldHeight));
            vec4 mask = texture2D(u_texture, v_tex_coord);
            float edgeNoise = noise21(p * 0.23) * 0.58 + noise21(p * 0.73) * 0.28 + hash21(floor(p * 1.6)) * 0.14;
            float coverage = smoothstep(0.10 + edgeNoise * 0.15, 0.58 + edgeNoise * 0.12, mask.r);
            float patches = noise21(p * 0.045);
            float fine = hash21(floor(p * 1.5));
            vec3 soil = mix(vec3(0.37, 0.32, 0.19), vec3(0.59, 0.51, 0.32), patches * 0.64 + fine * 0.25);
            // Faint wheel wear breaks up the center without a pair of rigid lines.
            soil *= 1.0 - mask.g * (0.035 + noise21(p * 0.11) * 0.045);
            vec2 cell = floor(p * 0.48), spot = fract(p * 0.48) - vec2(0.5);
            float stones = step(0.95, hash21(cell)) * (1.0 - smoothstep(0.08, 0.25, length(spot)));
            soil = mix(soil, vec3(0.53, 0.50, 0.37), stones * 0.40);
            float sparseGrass = smoothstep(0.42, 0.72, noise21(p * 0.31)) * (1.0 - coverage * 0.78);
            float alpha = coverage * (0.78 + patches * 0.10) * (1.0 - sparseGrass * 0.70);
            soil *= sunStrength(p, u_sceneTime);
            gl_FragColor = vec4(soil * alpha, alpha);
        }
        """, uniforms: [clock()])

        func mist(layer: Float) -> SKShader {
            SKShader(source: Self.noise + """
            void main() {
                vec2 p = vec2(-160.0, \(worldHeight-220)) + v_tex_coord * vec2(1600.0, -\(worldHeight));
                float speed = mix(8.0, 15.0, u_layer);
                vec2 advected = p - vec2(u_sceneTime * speed, sin(u_sceneTime * 0.30 + u_layer) * 24.0);
                vec2 q = advected * vec2(0.010, 0.013) + vec2(u_layer * 9.7);
                float n = noise21(q) * 0.58 + noise21(q * 2.1 + u_sceneTime * 0.035) * 0.29 + noise21(q * 4.2) * 0.13;
                float edge = max(1.0 - smoothstep(30.0, 320.0, p.x), smoothstep(1100.0, 1410.0, p.x));
                float lower = smoothstep(560.0, 850.0, p.y);
                float band = exp(-pow((p.y - 645.0 - sin(advected.x * 0.004) * 60.0) / 115.0, 2.0));
                float movingX = mod(-200.0 + u_sceneTime * speed + u_layer * 270.0, 1980.0) - 160.0;
                vec2 delta = (p - vec2(movingX, 580.0 + sin(u_sceneTime * 0.16) * 45.0)) / vec2(170.0, 90.0);
                float plume = exp(-dot(delta, delta));
                float alpha = smoothstep(0.28, 0.73, n) * (edge * lower * 0.38 + band * 0.09 + plume * 0.19);
                alpha *= mix(0.65, 1.0, u_layer);
                vec3 tint = mix(vec3(0.78, 0.84, 0.78), vec3(0.97, 0.93, 0.80), u_layer);
                gl_FragColor = vec4(tint * alpha, alpha);
            }
            """, uniforms: [clock(), SKUniform(name: "u_layer", float: layer)])
        }
        backMist = mist(layer: 0)
        frontMist = mist(layer: 1)
        sunlight = SKShader(source: Self.noise + """
        void main() {
            // This sprite fills the scene directly, outside the scaled world.
            // Neither the ray coordinates nor cloud modulation use the map camera.
            vec2 viewPoint = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y) * u_viewSize;
            float referenceSize = max(min(u_viewSize.x, u_viewSize.y), 1.0);
            vec2 p = viewPoint * (1024.0 / referenceSize);
            // The shared source sits just outside the viewport's upper left.
            // Constant angular coordinates define widening rays, not parallel bands.
            vec2 delta = viewPoint + u_viewSize * vec2(0.035, 0.055);
            float angular = delta.y / max(delta.x + delta.y, 0.001);
            float radialDistance = length(delta) / referenceSize;
            float sway = sin(u_sceneTime * 0.18 + angular * 9.0) * 0.25;
            float axis = angular * 64.0 - u_sceneTime * 0.18 + sway;
            float rays = pow(0.5 + 0.5 * sin(axis), 4.0);
            rays += pow(0.5 + 0.5 * sin(angular * 108.0 - u_sceneTime * 0.14 + sway * 0.6 + 1.3), 6.0) * 0.18;
            float castAngle = u_sunCast.y / max(u_sunCast.x + u_sunCast.y, 0.001);
            float fan = 1.0 - smoothstep(0.36, 0.72, abs(angular - castAngle));
            float falloff = exp(-radialDistance * 0.85) * smoothstep(0.025, 0.14, radialDistance);
            float travel = 0.84 + 0.16 * sin(radialDistance * 10.0 - u_sceneTime * 0.32 + angular * 12.0);
            float glow = exp(-radialDistance * 3.5) * 0.045;
            float cloud = smoothstep(0.22, 0.80, meadowCloud(p, u_sceneTime));
            float alpha = (rays * 0.17 * fan * travel + glow) * falloff * mix(0.70, 1.0, cloud);
            gl_FragColor = vec4(vec3(1.0, 0.84, 0.48) * alpha, alpha);
        }
        """, uniforms: [clock(), SKUniform(name: "u_sunCast",
                                            vectorFloat2: SIMD2(Float(MeadowSun.cast.dx), Float(MeadowSun.cast.dy))),
                        SKUniform(name: "u_viewSize", vectorFloat2: SIMD2(1280, 720))])

        // Real-time animated flowing waterfall cascade (pure SKUniforms, strictly downward gravity acceleration!):
        // Uses nonlinear vertical mapping `yCurve` with CONSTANT time multipliers so dPhi/dy > 0 ALWAYS
        // (guaranteed downward flow at every t >= 0, never reversing!). Harmonized with crystal-clear alpine river!
        waterfall = SKShader(source: Self.noise + """
        void main() {
            vec2 uv = v_tex_coord; // uv.y = 1.0 top crest, uv.y = 0.0 bottom plunge impact
            float t = u_sceneTime;
            float drop = 1.0 - uv.y; // 0 at top lip -> 1 at plunge pool base
            // Organic tapered chute widening gently as the cascade tumbles into the plunge pool
            float halfW = mix(0.23, 0.41, pow(max(drop, 0.001), 0.82));
            float xDist = abs(uv.x - 0.5);
            // Strictly downward-scrolling edge turbulence (constant +t speed so flow is ALWAYS top -> bottom!)
            float yCurve = 1.0 - pow(max(drop, 0.0005), 0.76);
            float edgeWarp = (noise21(vec2(uv.x * 5.5, yCurve * 6.5 + t * 3.0)) - 0.5) * 0.085;
            float bodyMask = 1.0 - smoothstep(halfW - 0.10, halfW + 0.03, xDist + edgeWarp);
            float topMask = 1.0 - smoothstep(0.86, 0.99, uv.y);
            float botMask = smoothstep(0.01, 0.14, uv.y);
            float mask = bodyMask * topMask * botMask;

            // Multi-octave high-definition water filaments accelerating smoothly DOWNWARD (never multiplying t by y!)
            float s1 = noise21(vec2(uv.x * 16.0, yCurve * 4.4 + t * 2.9));
            float s2 = noise21(vec2(uv.x * 29.0 + 4.3, yCurve * 7.8 + t * 4.4));
            float s3 = noise21(vec2(uv.x * 52.0 - 2.1, yCurve * 12.6 + t * 6.2));
            float braid = 0.68 + 0.32 * cos((uv.x - 0.5) * 20.0 + sin(yCurve * 6.0 + t * 3.4) * 0.65);
            float streams = (s1 * 0.44 + s2 * 0.36 + s3 * 0.20) * braid;

            // Crystal-clear sunlit alpine turquoise-aqua palette harmonized with HD meadowGroundFragment river!
            vec3 deepStream = vec3(0.08, 0.30, 0.37);
            vec3 midStream  = vec3(0.22, 0.58, 0.65);
            vec3 litRibbon  = vec3(0.84, 0.96, 0.97);
            vec3 foamSpray  = vec3(0.98, 0.99, 0.96);

            // Upper-left warm sunlight illuminating the falling crystal water sheet
            float sideSun = 1.0 - smoothstep(0.18, 0.80, uv.x);
            vec3 col = mix(deepStream, midStream, smoothstep(0.22, 0.70, streams) * (0.64 + 0.36 * sideSun));

            // Multi-tier aerated splash bursts: crest lip + mid-cliff rock ledge + roaring plunge foot
            float topLipFoam = exp(-pow((uv.y - 0.86) / 0.075, 2.0)) * smoothstep(0.26, 0.68, s1);
            float ledgeBurst = exp(-pow((uv.y - 0.47) / 0.095, 2.0)) * smoothstep(0.28, 0.70, s2);
            float plungeChurn = (1.0 - smoothstep(0.02, 0.30, uv.y)) * smoothstep(0.18, 0.64, s2 * 0.55 + s3 * 0.45);
            float ribbonHighlight = smoothstep(0.50, 0.78, streams) * (0.58 + 0.42 * sideSun);
            // Sparkling sunlit water glints pouring down the illuminated filaments
            float glint = pow(smoothstep(0.68, 0.92, s2 * 0.5 + s3 * 0.5), 3.0) * (0.5 + 0.5 * sideSun);

            col = mix(col, litRibbon, clamp(ribbonHighlight * 0.78 + topLipFoam * 0.52, 0.0, 0.88));
            col = mix(col, foamSpray, clamp(ledgeBurst * 0.72 + plungeChurn * 0.92 + smoothstep(0.72, 0.90, streams) * 0.56, 0.0, 0.95));
            col += vec3(1.0, 0.97, 0.84) * glint * 0.48;

            vec2 wp = u_wfOrigin + vec2((uv.x - 0.5) * u_wfExtent.x, (0.5 - uv.y) * u_wfExtent.y);
            float light = sunStrength(wp, t);
            col *= light;

            float alpha = mask * clamp(0.52 + streams * 0.46 + plungeChurn * 0.46 + ledgeBurst * 0.32, 0.0, 0.95);
            gl_FragColor = vec4(col * alpha, alpha);
        }
        """, uniforms: [
            clock(),
            SKUniform(name: "u_wfOrigin", vectorFloat2: SIMD2(640, 20)),
            SKUniform(name: "u_wfExtent", vectorFloat2: SIMD2(74, 118))
        ])

        // Waterfall-river junction VFX: billowing Cartesian white foam splash plumes + rising sunlit mist + dreamy arched rainbow!
        waterfallMist = SKShader(source: Self.noise + """
        vec3 spectralRainbow(float u) {
            // Vivid yet airy translucent sunlit prism arc: red (outer) -> orange -> yellow -> green -> cyan -> blue -> violet (inner)
            vec3 c0 = vec3(1.00, 0.34, 0.28);
            vec3 c1 = vec3(1.00, 0.68, 0.20);
            vec3 c2 = vec3(0.98, 0.96, 0.30);
            vec3 c3 = vec3(0.34, 0.92, 0.52);
            vec3 c4 = vec3(0.24, 0.84, 1.00);
            vec3 c5 = vec3(0.44, 0.52, 1.00);
            vec3 c6 = vec3(0.78, 0.42, 0.98);
            float s = clamp(u, 0.0, 1.0) * 6.0;
            if (s < 1.0) return mix(c0, c1, s);
            if (s < 2.0) return mix(c1, c2, s - 1.0);
            if (s < 3.0) return mix(c2, c3, s - 2.0);
            if (s < 4.0) return mix(c3, c4, s - 3.0);
            if (s < 5.0) return mix(c4, c5, s - 4.0);
            return mix(c5, c6, s - 5.0);
        }
        void main() {
            vec2 uv = v_tex_coord; // uv.y = 0 bottom -> 1 top
            float t = u_sceneTime;
            vec2 wp = u_mistOrigin + vec2((uv.x - 0.5) * u_mistExtent.x, (0.5 - uv.y) * u_mistExtent.y);
            float light = sunStrength(wp, t);

            // 1. Billowing organic Cartesian impact splash foam (ZERO polar atan spokes!)
            vec2 spD = (uv - vec2(0.43, 0.38)) * vec2(2.7, 3.6);
            float spR = length(spD);
            float f1 = noise21(vec2(uv.x * 9.5 + sin(t * 0.9) * 0.35, uv.y * 8.5 - t * 2.8));
            float f2 = noise21(vec2(uv.x * 18.0 - t * 0.5, uv.y * 15.0 - t * 4.4) + 5.3);
            float f3 = noise21(vec2(uv.x * 30.0 + t * 0.7, uv.y * 24.0 - t * 6.0) + 12.1);
            float foamCloud = f1 * 0.46 + f2 * 0.36 + f3 * 0.18;
            float splashBody = (1.0 - smoothstep(0.10, 0.96, spR)) * smoothstep(0.24, 0.72, foamCloud);
            float splashHeart = (1.0 - smoothstep(0.0, 0.52, spR)) * (0.45 + 0.55 * smoothstep(0.28, 0.74, f2));
            float splashAlpha = clamp(splashBody * 0.72 + splashHeart * 0.56, 0.0, 0.88);

            // 2. Soft billowing pearlescent mist clouds rising upward & drifting gently downwind
            vec2 md = (uv - vec2(0.48, 0.50)) * vec2(1.90, 2.05);
            float mr = length(md);
            float mRadial = 1.0 - smoothstep(0.10, 0.95, mr);
            float mn1 = noise21(vec2(uv.x * 4.6 - t * 0.20, uv.y * 4.8 - t * 0.65));
            float mn2 = noise21(vec2(uv.x * 9.2 - t * 0.32 + sin(t * 0.45) * 0.35, uv.y * 8.6 - t * 1.15) + 7.2);
            float puff = smoothstep(0.26, 0.78, mn1 * 0.58 + mn2 * 0.42);
            float mistAlpha = clamp(mRadial * puff * 0.56, 0.0, 0.54);

            // 3. Dreamy sunlit refracted rainbow arc curving gracefully over the waterfall-river mist plume!
            vec2 rbD = (uv - vec2(0.55, 0.24)) * vec2(1.02, 1.24);
            float rbR = length(rbD);
            float bandPos = (0.46 - rbR) / 0.145; // 0 = outer red, 1 = inner violet
            float bandShape = smoothstep(0.0, 0.18, bandPos) * (1.0 - smoothstep(0.82, 1.0, bandPos));
            float archFade = smoothstep(0.03, 0.24, rbD.y) * smoothstep(-0.42, -0.08, rbD.x) * (1.0 - smoothstep(0.22, 0.46, rbD.x));
            float shimmer = 0.84 + 0.16 * sin(t * 1.1 + rbD.x * 7.0);
            float rbAlpha = clamp(bandShape * archFade * shimmer * 0.62, 0.0, 0.62);
            vec3 rbCol = spectralRainbow(bandPos) * 1.08;

            // Composite splash foam + mist + luminous sunlit rainbow cleanly in premultiplied RGBA
            vec3 splashCol = vec3(0.96, 0.99, 0.99) * light;
            vec3 mistCol   = vec3(0.90, 0.96, 0.97) * light;
            float baseAlpha = clamp(splashAlpha + mistAlpha * (1.0 - splashAlpha * 0.58), 0.0, 0.88);
            vec3 baseCol = mix(mistCol, splashCol, clamp(splashAlpha / max(baseAlpha, 0.001), 0.0, 1.0));
            // Keep rainbow crisp and glowing clearly over the mist without washing out
            vec3 outCol = mix(baseCol, rbCol, rbAlpha * 0.82);
            float outAlpha = clamp(max(baseAlpha, rbAlpha * 0.88) + rbAlpha * 0.18, 0.0, 0.94);
            vec3 premul = baseCol * baseAlpha * (1.0 - rbAlpha * 0.55) + rbCol * rbAlpha * 0.88;
            gl_FragColor = vec4(premul, outAlpha);
        }
        """, uniforms: [
            clock(),
            SKUniform(name: "u_mistOrigin", vectorFloat2: SIMD2(640, 56)),
            SKUniform(name: "u_mistExtent", vectorFloat2: SIMD2(208, 138))
        ])
    }

    func makeSunlightOverlay(size: CGSize) -> SKSpriteNode {
        let node = SKSpriteNode(color: .white, size: size)
        node.name = "viewportSunlight"
        node.shader = sunlight
        node.blendMode = .add
        node.zPosition = 20000
        layoutSunlight(node, size: size)
        return node
    }

    func layoutSunlight(_ node: SKSpriteNode, size: CGSize) {
        node.size = size
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sunlight.uniformNamed("u_viewSize")?.vectorFloat2Value = SIMD2(Float(size.width), Float(size.height))
    }

    func update(time: TimeInterval) {
        currentCast = MeadowSun.cast(at: time)
        for shader in [ground, vegetation, meadowPlants, shadow, soil, backMist, frontMist, sunlight, waterfall, waterfallMist] {
            shader.uniformNamed("u_sceneTime")?.floatValue = Float(time)
        }
        sunlight.uniformNamed("u_sunCast")?.vectorFloat2Value = SIMD2(Float(currentCast.dx), Float(currentCast.dy))
    }

    func apply(_ shader: SKShader, to node: SKSpriteNode, origin: CGPoint,
               extent: CGSize, wind: Float = 0, phase: Float = 0,
               gait: SIMD2<Float> = SIMD2(-1, 0)) {
        // Kept for call-site compatibility. Whole authored gait frames are
        // already applied to the sprite and shadow textures by the scene.
        _ = gait
        node.shader = shader
        node.attributeValues = [
            "a_origin": SKAttributeValue(vectorFloat2: SIMD2(Float(origin.x), Float(origin.y))),
            "a_extent": SKAttributeValue(vectorFloat2: SIMD2(Float(extent.width), Float(extent.height))),
            "a_wind": SKAttributeValue(float: wind), "a_phase": SKAttributeValue(float: phase)
        ]
    }
}
