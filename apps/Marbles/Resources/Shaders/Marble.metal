#include <metal_stdlib>
using namespace metal;

constant float PI = 3.141592653589793;

struct Instance {
    float2 center;
    float radius;
    float time;
    float colorCount;
    float innerDistortion;
    float size;
    float angle;
    float4 colorBack;
    float4 colorInner;
    float4 colors[5];
};

struct FrameConstants {
    float2 viewport;
    float pointsPerPixel;
    float2 pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 objectUV;
    uint iid [[flat]];
};

constant float2 kCorners[6] = {
    float2(-1, -1), float2(1, -1), float2(-1, 1),
    float2(-1, 1), float2(1, -1), float2(1, 1)
};

float2 rotate2(float2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sst(float a, float b, float x) {
    return smoothstep(a, b, x);
}

vertex VertexOut marble_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant Instance *instances [[buffer(0)]],
    constant FrameConstants &frame [[buffer(1)]]
) {
    Instance m = instances[iid];
    float2 corner = kCorners[vid];
    float pad = 1.02;
    float2 pixel = m.center + corner * m.radius * pad;
    float2 ndc = pixel / frame.viewport * 2.0 - 1.0;
    VertexOut out;
    out.position = float4(ndc, 0, 1);
    // gem-smoke v_objectUV is about -0.5...0.5 when the circle fills the box.
    out.objectUV = corner * pad * 0.5;
    out.iid = iid;
    return out;
}

fragment float4 marble_fragment(
    VertexOut in [[stage_in]],
    constant Instance *instances [[buffer(0)]]
) {
    Instance m = instances[in.iid];
    float time = m.time;
    float2 objectUV = in.objectUV;

    float2 uv = objectUV + 0.5;
    uv.y = 1.0 - uv.y;
    float2 shapeUV = (uv - 0.5) * 0.67;
    float edge = pow(clamp(3.0 * length(shapeUV), 0.0, 1.0), 18.0);
    float imgAlpha = 1.0 - smoothstep(0.9 - 2.0 * fwidth(edge), 0.9, edge);
    float roundness = 1.0 - edge;

    float2 smokeUV = rotate2(objectUV, m.angle * PI / 180.0);
    smokeUV *= mix(4.0, 1.0, m.size);

    float2 innerUV = smokeUV;
    innerUV.y += m.innerDistortion * (1.0 - sst(0.0, 1.0, length(0.4 * innerUV)));
    innerUV.y -= 0.4 * m.innerDistortion;

    float innerSwirl = m.innerDistortion * roundness;
    for (int i = 1; i < 5; i++) {
        float fi = float(i);
        float stretchIn = max(length(dfdx(innerUV)), length(dfdy(innerUV)));
        float dampenIn = 1.0 / (1.0 + stretchIn * 8.0);
        float sIn = innerSwirl * dampenIn;
        innerUV.x += sIn / fi * cos(time + fi * 2.9 * innerUV.y);
        innerUV.y += sIn / fi * cos(time + fi * 1.5 * innerUV.x);
    }

    float innerShape = exp(-1.5 * dot(innerUV, innerUV));
    innerShape *= imgAlpha;

    float mixer = innerShape * m.colorCount;
    float4 gradient = m.colors[0];
    gradient.rgb *= gradient.a;

    float smokeMask = 0.0;
    int count = int(m.colorCount + 0.5);
    for (int i = 1; i < 6; i++) {
        if (i > count) break;
        float mixAmount = sst(0.0, 1.0, clamp(mixer - float(i - 1), 0.0, 1.0));
        if (i == 1) smokeMask = mixAmount;
        float4 c = m.colors[i - 1];
        c.rgb *= c.a;
        gradient = mix(gradient, c, mixAmount);
    }

    float3 color = gradient.rgb * smokeMask;
    float opacity = gradient.a * smokeMask;

    float innerOpacity = m.colorInner.a * imgAlpha;
    float3 innerColor = m.colorInner.rgb * innerOpacity;
    color += innerColor * (1.0 - opacity);
    opacity += innerOpacity * (1.0 - opacity);

    float3 backColor = m.colorBack.rgb * m.colorBack.a;
    color += backColor * (1.0 - opacity);
    opacity += m.colorBack.a * (1.0 - opacity);

    color *= imgAlpha;
    opacity *= imgAlpha;
    return float4(color, opacity);
}
