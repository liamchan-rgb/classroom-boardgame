import SpriteKit

final class EnvironmentShaders {
    let time = SKUniform(name: "u_sceneTime", float: 0)
    let ground: SKShader
    let vegetation: SKShader
    let shadow: SKShader
    let soil: SKShader
    let backMist: SKShader
    let frontMist: SKShader
    let sunlight: SKShader

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
        return noise21(p * 0.004 + vec2(t * 0.016, t * 0.005));
    }
    """

    init() {
        let clock = time
        let commonAttributes = [SKAttribute(name: "a_origin", type: .vectorFloat2),
                                SKAttribute(name: "a_extent", type: .vectorFloat2),
                                SKAttribute(name: "a_wind", type: .float),
                                SKAttribute(name: "a_phase", type: .float)]
        let surface = Self.noise + """
        void main() {
            vec2 uv = v_tex_coord;
            float bend = sin(u_sceneTime * 1.45 + a_phase + uv.y * 3.0);
            if (a_wind > 1.5) {
                uv.y += sin(uv.x * 10.0 - u_sceneTime * 4.2 + a_phase) * 0.045 * uv.x;
            } else {
                uv.x += bend * 0.014 * a_wind * uv.y * uv.y;
            }
            vec4 color = texture2D(u_texture, clamp(uv, 0.001, 0.999));
            vec2 p = a_origin + vec2((v_tex_coord.x - 0.5) * a_extent.x,
                                     (0.5 - v_tex_coord.y) * a_extent.y);
            float cloud = meadowCloud(p, u_sceneTime);
            float light = 0.91 + cloud * 0.13 + sin(u_sceneTime * 0.12) * 0.015;
            color.rgb *= vec3(1.035, 1.0, 0.94) * light;
            gl_FragColor = color;
        }
        """
        ground = SKShader(source: Self.noise + """
        vec3 grassSample(vec2 uv, vec2 cell) {
            vec2 offset = vec2(hash21(cell), hash21(cell + 17.3));
            return texture2D(u_texture, fract(uv + offset)).rgb;
        }
        void main() {
            vec2 p = a_origin + vec2((v_tex_coord.x - 0.5) * a_extent.x,
                                     (0.5 - v_tex_coord.y) * a_extent.y);
            vec2 grid = p / 150.0;
            vec2 cell = floor(grid);
            vec2 weight = smoothstep(vec2(0.0), vec2(1.0), fract(grid));
            vec2 uv = p / 330.0;
            vec3 first = mix(grassSample(uv, cell), grassSample(uv, cell + vec2(1.0, 0.0)), weight.x);
            vec3 second = mix(grassSample(uv, cell + vec2(0.0, 1.0)), grassSample(uv, cell + vec2(1.0)), weight.x);
            vec3 grass = mix(first, second, weight.y);
            float meadow = noise21(p * 0.006);
            grass = mix(grass, vec3(0.30, 0.38, 0.14), 0.12 + (1.0 - meadow) * 0.08);
            grass *= vec3(1.01, 1.0, 0.95) * (0.92 + meadowCloud(p, u_sceneTime) * 0.13);
            gl_FragColor = vec4(grass, 1.0);
        }
        """, uniforms: [clock])
        vegetation = SKShader(source: surface, uniforms: [clock])
        ground.attributes = commonAttributes
        vegetation.attributes = commonAttributes
        shadow = SKShader(source: """
        void main() {
            float a = texture2D(u_texture, v_tex_coord).a * 0.24;
            a *= 1.0 - v_tex_coord.y * 0.38;
            gl_FragColor = vec4(vec3(0.075, 0.09, 0.045) * a, a);
        }
        """)
        soil = SKShader(source: Self.noise + """
        void main() {
            vec2 p = v_tex_coord * vec2(960.0, 560.0);
            float fine = hash21(floor(p * 2.0));
            float patches = noise21(p * 0.09);
            vec3 sand = mix(vec3(0.55, 0.38, 0.20), vec3(0.91, 0.75, 0.45), 0.45 + fine * 0.4);
            sand *= 0.89 + patches * 0.20;
            vec2 pebbleCell = floor(p * 0.25);
            vec2 pebbleUV = fract(p * 0.25) - vec2(0.5);
            float stones = step(0.88, hash21(pebbleCell)) * (1.0 - smoothstep(0.12, 0.34, length(pebbleUV)));
            vec3 stone = mix(vec3(0.44, 0.36, 0.27), vec3(0.89, 0.83, 0.68), hash21(pebbleCell + 9.0));
            sand = mix(sand, stone, stones * 0.85);
            sand *= 0.94 + noise21(p * 0.024) * 0.13;
            gl_FragColor = vec4(sand, 1.0);
        }
        """)
        func mist(layer: Float) -> SKShader {
            SKShader(source: Self.noise + """
            void main() {
                vec2 p = vec2(-160.0, 940.0) + v_tex_coord * vec2(1600.0, -1160.0);
                vec2 drift = vec2(u_sceneTime * 0.025, u_sceneTime * 0.007);
                vec2 q = p * vec2(0.006, 0.008) + drift + vec2(u_layer * 8.3);
                float n = noise21(q) * 0.65 + noise21(q * 2.05) * 0.25 + noise21(q * 4.1) * 0.10;
                float edge = max(1.0 - smoothstep(0.0, 310.0, p.x), smoothstep(1040.0, 1420.0, p.x));
                float lower = smoothstep(580.0, 880.0, p.y);
                float upper = 1.0 - smoothstep(-190.0, 100.0, p.y);
                float corners = max(edge * lower, edge * upper * 0.35);
                float band = exp(-pow((p.y - 620.0 - sin(p.x * 0.003 + u_sceneTime * 0.05) * 75.0) / 100.0, 2.0));
                float a = smoothstep(0.35, 0.80, n) * (corners * 0.62 + band * 0.085);
                a *= u_layer > 0.5 ? 1.0 : 0.65;
                vec3 tint = mix(vec3(0.85, 0.88, 0.72), vec3(1.0, 0.94, 0.78), u_layer);
                gl_FragColor = vec4(tint * a, a);
            }
            """, uniforms: [clock, SKUniform(name: "u_layer", float: layer)])
        }
        backMist = mist(layer: 0)
        frontMist = mist(layer: 1)
        sunlight = SKShader(source: """
        void main() {
            vec2 p = vec2(-160.0, 940.0) + v_tex_coord * vec2(1600.0, -1160.0);
            float axis = p.x - p.y * 0.67 + sin(u_sceneTime * 0.065) * 28.0;
            float rays = pow(max(0.0, sin(axis * 0.026)), 24.0);
            rays += pow(max(0.0, sin(axis * 0.017 + 1.3)), 32.0) * 0.5;
            float falloff = exp(-length(p - vec2(5.0, -90.0)) * 0.0015);
            float glow = exp(-length(p - vec2(-30.0, -140.0)) * 0.003) * 0.10;
            float a = (rays * 0.18 + glow) * falloff * (0.9 + 0.1 * sin(u_sceneTime * 0.28));
            gl_FragColor = vec4(vec3(1.0, 0.86, 0.52) * a, a);
        }
        """, uniforms: [clock])
    }

    func apply(_ shader: SKShader, to node: SKSpriteNode, origin: CGPoint,
               extent: CGSize, wind: Float = 0, phase: Float = 0) {
        node.shader = shader
        node.attributeValues = [
            "a_origin": SKAttributeValue(vectorFloat2: SIMD2(Float(origin.x), Float(origin.y))),
            "a_extent": SKAttributeValue(vectorFloat2: SIMD2(Float(extent.width), Float(extent.height))),
            "a_wind": SKAttributeValue(float: wind), "a_phase": SKAttributeValue(float: phase)
        ]
    }
}
