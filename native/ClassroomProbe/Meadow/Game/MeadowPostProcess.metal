#include <metal_stdlib>
using namespace metal;

// World-layer HD-2D post-processing. Every pass draws one full-screen triangle.
// Inputs are gamma-encoded bgra8 targets; grading works in that space, like the
// approved offline reference. UI is composited afterwards and never enters here.

struct MeadowPostRaster {
    float4 position [[position]];
    float2 uv;
};

struct MeadowPostBlur {
    float4 axis;          // xy: one destination texel along the blur axis (uv), z: centre weight, w: tap count
    float4 taps[12];      // xy: (offset in texels, weight) pair, zw unused
};

struct MeadowPostUniforms {
    float4 view;          // xy: point size, zw: unused
    float4 tilt;          // x: focus (uv y), y: clear half-band, z: small blur reached, w: large blur reached
    float4 bloom;         // x: small strength, y: large strength
    float4 grade;         // x: S-curve mix, y: saturation, z: warm highlights, w: cool shadows
    float4 vignette;      // x: strength, y: inner radius, z: outer radius
    float4 haze;          // rgb: far haze colour, a: amount at the top edge
    float4 shafts;        // x: intensity, y: time, z: band period (world points), w: drift speed
    float4 shaftColor;    // rgb: shaft colour
    float4 worldInverse;  // view point -> world point 2x2 matrix (column major: a, b, c, d)
    float4 worldOrigin;   // xy: view-space origin of world (0, 0)
};

constexpr sampler meadowPostLinear(coord::normalized, address::clamp_to_edge, filter::linear);

vertex MeadowPostRaster meadowPostVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = { float2(-1, 1), float2(-1, -3), float2(3, 1) };
    MeadowPostRaster out;
    float2 p = positions[id];
    out.position = float4(p, 0, 1);
    out.uv = float2((p.x + 1) * 0.5, (1 - p.y) * 0.5);
    return out;
}

// Four bilinear taps one source texel from the centre average a 4x4 block.
fragment float4 meadowPostDownsample(MeadowPostRaster in [[stage_in]], texture2d<float> source [[texture(0)]]) {
    float2 o = 1.0 / float2(source.get_width(), source.get_height());
    float3 c = source.sample(meadowPostLinear, in.uv + float2(-o.x, -o.y)).rgb
             + source.sample(meadowPostLinear, in.uv + float2( o.x, -o.y)).rgb
             + source.sample(meadowPostLinear, in.uv + float2(-o.x,  o.y)).rgb
             + source.sample(meadowPostLinear, in.uv + float2( o.x,  o.y)).rgb;
    return float4(c * 0.25, 1);
}

// Soft-knee luminance threshold: only bright foliage highlights, sky gaps,
// lamps and magic feed the glow, not the whole mid-tone meadow.
fragment float4 meadowPostBright(MeadowPostRaster in [[stage_in]], texture2d<float> source [[texture(0)]],
                                 constant float2 &threshold [[buffer(0)]]) {
    float3 c = source.sample(meadowPostLinear, in.uv).rgb;
    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    float w = smoothstep(threshold.x, threshold.x + threshold.y, l);
    return float4(c * w, 1);
}

// Separable Gaussian using paired bilinear taps (weights prepared on the CPU).
fragment float4 meadowPostBlur(MeadowPostRaster in [[stage_in]], texture2d<float> source [[texture(0)]],
                               constant MeadowPostBlur &blur [[buffer(0)]]) {
    float3 c = source.sample(meadowPostLinear, in.uv).rgb * blur.axis.z;
    int count = int(blur.axis.w);
    for (int i = 0; i < count; i++) {
        float2 step = blur.axis.xy * blur.taps[i].x;
        c += (source.sample(meadowPostLinear, in.uv + step).rgb
            + source.sample(meadowPostLinear, in.uv - step).rgb) * blur.taps[i].y;
    }
    return float4(c, 1);
}

static float meadowPostLuma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

fragment float4 meadowPostComposite(MeadowPostRaster in [[stage_in]],
                                    texture2d<float> scene [[texture(0)]],
                                    texture2d<float> tiltSmall [[texture(1)]],
                                    texture2d<float> tiltLarge [[texture(2)]],
                                    texture2d<float> bloomSmall [[texture(3)]],
                                    texture2d<float> bloomLarge [[texture(4)]],
                                    constant MeadowPostUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float3 c = scene.sample(meadowPostLinear, uv).rgb;

    // Tilt-shift: a clear horizontal band around the focus, then two blur levels.
    float d = abs(uv.y - u.tilt.x);
    float small = smoothstep(u.tilt.y, u.tilt.z, d);
    float large = smoothstep(u.tilt.z, u.tilt.w, d);
    c = mix(c, tiltSmall.sample(meadowPostLinear, uv).rgb, small);
    c = mix(c, tiltLarge.sample(meadowPostLinear, uv).rgb, large);

    // Bloom as a screen blend, so highlights glow without clipping to white.
    float3 glow = bloomSmall.sample(meadowPostLinear, uv).rgb * u.bloom.x
                + bloomLarge.sample(meadowPostLinear, uv).rgb * u.bloom.y;
    c = 1.0 - (1.0 - c) * (1.0 - saturate(glow));

    // Warm aerial haze toward the far (upper) edge of the view.
    float far = 1.0 - smoothstep(0.0, 0.48, uv.y);
    c = mix(c, u.haze.rgb, u.haze.a * far * far);

    // Slow, low-intensity diagonal shafts anchored to the world, not the screen.
    if (u.shafts.x > 0.0) {
        float2 p = uv * u.view.xy - u.worldOrigin.xy;
        float2 w = float2(u.worldInverse.x * p.x + u.worldInverse.z * p.y,
                          u.worldInverse.y * p.x + u.worldInverse.w * p.y);
        float s = dot(w, normalize(float2(1.0, 0.62))) / u.shafts.z;
        float t = u.shafts.y * u.shafts.w;
        float band = pow(0.5 + 0.5 * sin(6.2831853 * s + t), 7.0);
        band += 0.55 * pow(0.5 + 0.5 * sin(6.2831853 * s * 0.43 - t * 0.6 + 1.7), 9.0);
        band *= 0.65 + 0.35 * sin(s * 1.9 + t * 0.37 + w.y * 0.004);
        float topWeight = mix(1.0, 0.45, uv.y);
        float lift = 0.45 + 0.55 * meadowPostLuma(c);
        c += u.shaftColor.rgb * (u.shafts.x * band * topWeight * lift);
    }

    // Gentle S-curve, saturation, warm highlights and cool shadows.
    float3 curve = c * c * (3.0 - 2.0 * c);
    c = mix(c, curve, u.grade.x);
    float l = meadowPostLuma(c);
    c = mix(float3(l), c, u.grade.y);
    float highlights = smoothstep(0.45, 1.0, l), shadows = 1.0 - smoothstep(0.0, 0.5, l);
    c += highlights * u.grade.z * float3(1.0, 0.35, -0.8);
    c += shadows * u.grade.w * float3(-0.6, -0.05, 1.0);

    // Vignette: darken the outer edge, aspect-corrected so it stays round.
    float2 q = (uv - 0.5) * float2(u.view.x / max(u.view.y, 1.0), 1.0);
    float r = length(q) / length(float2(0.5 * u.view.x / max(u.view.y, 1.0), 0.5));
    c *= 1.0 - u.vignette.x * smoothstep(u.vignette.y, u.vignette.z, r);

    return float4(saturate(c), 1);
}
