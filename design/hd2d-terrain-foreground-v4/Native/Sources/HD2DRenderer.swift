import SpriteKit
import simd

// Programs are shared by surface kind; per-node attributes allow SpriteKit batching.
// No luminance-derived normal map, whole-scene blur or per-frame texture generation.
final class HD2DRenderer {
    private var surfaces: [SurfaceKind: SKShader] = [:]
    private let ground: SKShader
    init(field: SKTexture, terrainField: SKTexture) {
        ground = SKShader(source: Self.groundSource)
        ground.attributes = [SKAttribute(name: "a_origin", type: .vectorFloat2)]
        ground.uniforms = [SKUniform(name: "u_field", texture: field), SKUniform(name: "u_terrainField", texture: terrainField), SKUniform(name: "u_terrain", float: 1),
                           SKUniform(name: "u_light", float: 1), SKUniform(name: "u_grade", float: 1),
                           SKUniform(name: "u_growth", float: 1), SKUniform(name: "u_contrast", float: 0.46),
                           SKUniform(name: "u_air", float: 0), SKUniform(name: "u_motion", float: 0)]
        for kind in [SurfaceKind.foliage, .rock, .building, .actor, .road, .lowPlant, .terrain] {
            let shader = SKShader(source: Self.surfaceSource)
            shader.attributes = [SKAttribute(name: "a_depth", type: .float)]
            shader.uniforms = [SKUniform(name: "u_kind", float: kind.rawValue),
                               SKUniform(name: "u_light", float: 1), SKUniform(name: "u_grade", float: 1),
                               SKUniform(name: "u_relief", float: 1), SKUniform(name: "u_air", float: 0), SKUniform(name: "u_motion", float: 0)]
            surfaces[kind] = shader
        }
    }
    func apply(to sprite: SKSpriteNode, id: String) {
        let kind = SurfaceKind.asset(id)
        sprite.lightingBitMask = 0; sprite.shadowCastBitMask = 0; sprite.shadowedBitMask = 0; sprite.normalTexture = nil
        if kind == .ground {
            sprite.shader = ground
            sprite.setValue(SKAttributeValue(vectorFloat2: SIMD2(Float(sprite.position.x), Float(sprite.position.y))), forAttribute: "a_origin")
        } else {
            sprite.shader = surfaces[kind]
            sprite.setValue(SKAttributeValue(float: Float(sprite.position.y)), forAttribute: "a_depth")
        }
    }
    func update(settings: HD2DSettings, mode: LightingMode, strength: CGFloat, reducedMotion: Bool) {
        let s = settings.bounded(), enabled: Float = mode == .flat ? 0 : Float(strength)
        // The second enhanced comparison has stronger relief; both share one sun direction.
        let relief: Float = mode == .normal ? 1.0 : 0.82
        ground.uniformNamed("u_terrain")?.floatValue = s.terrain && s.relief && mode != .flat ? enabled : 0
        ground.uniformNamed("u_light")?.floatValue = s.directionalLight ? enabled : 0
        ground.uniformNamed("u_grade")?.floatValue = s.colorGrade ? enabled : 0
        ground.uniformNamed("u_growth")?.floatValue = mode != .flat && s.vegetation ? 1 : 0
        ground.uniformNamed("u_contrast")?.floatValue = Float(s.vegetationContrast)
        ground.uniformNamed("u_air")?.floatValue = s.atmosphere ? enabled*Float(s.atmosphereStrength) : 0
        let motion: Float = mode != .flat && s.environmentalMotion && !reducedMotion ? Float(s.motionStrength) : 0
        ground.uniformNamed("u_motion")?.floatValue = motion
        for (kind, shader) in surfaces {
            shader.uniformNamed("u_motion")?.floatValue = kind == .building ? motion : 0
            shader.uniformNamed("u_light")?.floatValue = s.directionalLight ? enabled : 0
            shader.uniformNamed("u_grade")?.floatValue = s.colorGrade ? enabled : 0
            shader.uniformNamed("u_relief")?.floatValue = s.relief ? enabled*relief : 0
            shader.uniformNamed("u_air")?.floatValue = s.atmosphere && kind != .actor && kind != .road ? enabled*Float(s.atmosphereStrength) : 0
        }
    }
    // Texture RGB is premultiplied; process straight color and restore original alpha.
    // All sampling stays nearest. Warm/cool light is local and material-dependent.
    static let surfaceSource = """
    void main() {
        vec2 sampleUV = v_tex_coord;
        vec4 tex = texture2D(u_texture, sampleUV);
        // The source flag's blue pixels sway by at most a source pixel. Wood is stationary.
        float flag = step(tex.r*1.25,tex.b)*step(tex.g*1.12,tex.b)*smoothstep(0.64,0.88,sampleUV.y);
        sampleUV.x += sin(u_time*1.8+sampleUV.y*12.0)*0.0018*u_motion*flag;
        tex = texture2D(u_texture,sampleUV);
        float alpha = tex.a;
        vec3 base = tex.rgb / max(alpha, 0.001);
        vec2 uv = v_tex_coord;
        float actor = 1.0 - step(0.1, abs(u_kind - 4.0));
        float rock = 1.0 - step(0.1, abs(u_kind - 2.0));
        float tree = 1.0 - step(0.1, abs(u_kind - 1.0));
        float road = 1.0 - step(0.1, abs(u_kind - 5.0));
        float terrain = 1.0 - step(0.1, abs(u_kind - 7.0));
        float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
        vec3 color = mix(base, vec3(lum), u_grade * (0.13 - 0.10*actor));
        float top = smoothstep(0.30, 0.82, uv.y);
        float left = 1.0 - smoothstep(0.18, 0.85, uv.x);
        float lit = clamp(top*0.65 + left*0.35, 0.0, 1.0);
        float dark = (1.0-lit) * (0.25 + 0.16*rock + 0.17*tree);
        float contact = (1.0-smoothstep(0.08, 0.34, uv.y))*(0.10+0.13*tree);
        // Atlas art already models faces; avoid doubling its baked illumination.
        float power = u_light*(1.0-0.62*actor)*(1.0-0.70*road)*0.58;
        color *= mix(vec3(1.0), vec3(0.62, 0.73, 0.79), dark*power*1.6);
        color += vec3(0.115, 0.068, 0.017)*lit*power*mix(0.55, 1.0, lum);
        color *= 1.0 - contact*u_relief*(1.0-0.65*actor)*0.75;
        // Cooler lower stone faces and dark-green trunk/canopy undersides.
        color = mix(color, color*vec3(0.87,0.94,1.06), rock*(1.0-top)*u_relief*0.45);
        color = mix(color, color*vec3(0.78,0.86,0.78), tree*(1.0-top)*u_relief*0.35);
        color *= 1.0 - terrain*(1.0-top)*u_relief*0.13;
        float distance = smoothstep(850.0, 1750.0, a_depth);
        color = mix(color, vec3(0.55,0.62,0.59), distance*u_air*0.16);
        gl_FragColor = vec4(clamp(color,0.0,0.98)*alpha,alpha)*v_color_mix;
    }
    """
    static let groundSource = """
    void main() {
        vec4 tex = texture2D(u_texture, v_tex_coord);
        float alpha = tex.a;
        vec3 base = tex.rgb / max(alpha, 0.001);
        vec2 world = a_origin + v_tex_coord*256.0;
        vec3 field = texture2D(u_field, (world+vec2(768.0))/3072.0).rgb;
        float lum = dot(base,vec3(0.2126,0.7152,0.0722));
        vec3 quiet = mix(vec3(0.40,0.48,0.235),vec3(0.57,0.60,0.31),field.b);
        quiet = mix(quiet,vec3(0.30,0.37,0.22),field.g*0.45);
        // Sparse colonies retain source pixel grain; clearings suppress high-contrast flowers.
        float retained = mix(0.16,0.34+0.48*u_contrast,field.r);
        vec3 natural = mix(quiet,base,retained);
        vec3 color = mix(base,natural,u_growth);
        float luminance = dot(color,vec3(0.2126,0.7152,0.0722));
        color = mix(color,vec3(luminance),u_grade*0.11);
        color *= 1.0 + sin(u_time*0.55+world.x*0.012+world.y*0.004)*0.012*u_motion*field.r;
        vec3 hill = texture2D(u_terrainField,(world+vec2(768.0))/3072.0).rgb;
        vec2 nxy = hill.rg*2.0-1.0;
        vec3 normal = vec3(nxy,sqrt(max(0.04,1.0-dot(nxy,nxy))));
        float diffuse = dot(normalize(normal),normalize(vec3(-0.60,0.70,0.75)));
        float slope = clamp((diffuse-0.55)*0.38,-0.16,0.16)*u_terrain;
        color *= 1.0+slope;
        color += vec3(0.040,0.023,0.004)*max(slope,0.0)*2.0;
        float shade = field.g*0.22*u_light;
        color *= mix(vec3(1.0),vec3(0.65,0.75,0.78),shade);
        color += vec3(0.06,0.032,0.005)*field.b*u_light;
        float far = smoothstep(1000.0,1950.0,world.y);
        color = mix(color,vec3(0.55,0.62,0.59),far*u_air*0.10);
        gl_FragColor = vec4(clamp(color,0.0,0.95)*alpha,alpha)*v_color_mix;
    }
    """
}
