#include <metal_stdlib>
using namespace metal;

struct Instance {
    float2 center;
    float radius;
    float dim;
    float hue;
    float saturation;
    float frost;
    float inclusionDensity;
    float luminosity;
    float secondaryHue;
    float family;
    float time;
    float4 noiseOffset;
    float advection;
    float pulse;
    float freeze;
    float hold;
    float errorHue;
    float bloom;
    float attention;
    float rimBoost;
};

struct FrameConstants {
    float2 viewport;
    float pointsPerPixel;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    uint iid [[flat]];
};

constant float2 kCorners[6] = {
    float2(-1, -1), float2(1, -1), float2(-1, 1),
    float2(-1, 1), float2(1, -1), float2(1, 1)
};

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float3 hash33(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash21(i.xy + i.z * 17.0);
    float n100 = hash21(i.xy + float2(1, 0) + i.z * 17.0);
    float n010 = hash21(i.xy + float2(0, 1) + i.z * 17.0);
    float n110 = hash21(i.xy + float2(1, 1) + i.z * 17.0);
    float n001 = hash21(i.xy + (i.z + 1.0) * 17.0);
    float n101 = hash21(i.xy + float2(1, 0) + (i.z + 1.0) * 17.0);
    float n011 = hash21(i.xy + float2(0, 1) + (i.z + 1.0) * 17.0);
    float n111 = hash21(i.xy + float2(1, 1) + (i.z + 1.0) * 17.0);
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm(float3 p) {
    float a = 0.5;
    float s = 0.0;
    for (int i = 0; i < 5; i++) {
        s += a * noise3(p);
        p = p * 2.02 + 13.1;
        a *= 0.5;
    }
    return s;
}

float3 hsv(float h, float s, float v) {
    float3 k = float3(1.0, 2.0 / 3.0, 1.0 / 3.0);
    float3 p = abs(fract(float3(h) + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

float voronoi(float2 p) {
    float2 g = floor(p);
    float2 f = fract(p);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 o = float2(i, j);
            float2 h = hash33(float3(g + o, 2.7)).xy;
            md = min(md, length(f - o - h));
        }
    }
    return md;
}

float4 voronoiCell(float2 p) {
    float2 g = floor(p);
    float2 f = fract(p);
    float md = 8.0;
    float2 mg = float2(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 o = float2(i, j);
            float3 hh = hash33(float3(g + o, 2.7));
            float d = length(f - o - hh.xy);
            if (d < md) {
                md = d;
                mg = g + o;
            }
        }
    }
    return float4(md, hash21(mg), hash21(mg + 9.1), hash21(mg - 4.3));
}

float3 contrast(float3 color, float amount) {
    return saturate(0.5 + (color - 0.5) * amount);
}

float accentHue(Instance m) {
    return m.noiseOffset.w;
}

struct Globe {
    float lon;
    float lat;
    float r;
    float3 wrap;
};

Globe sphereOf(float3 p) {
    Globe g;
    g.r = max(length(p), 1e-4);
    float3 n = p / g.r;
    g.lon = atan2(n.x, n.z);
    g.lat = n.y;
    g.wrap = n * (1.65 + g.r * 0.85);
    return g;
}

float terrain(float x, float phase, float freq, float amp) {
    float warp = 0.18 * sin(x * freq * 0.55 + phase * 0.71);
    float u = x + warp;
    return amp * (
        sin(u * freq + phase)
        + 0.52 * sin(u * freq * 2.17 + phase * 1.31)
        + 0.26 * sin(u * freq * 4.05 + phase * 0.67)
        + 0.12 * sin(u * freq * 7.3 + phase * 2.2)
    );
}

float3 shadeSlope(float3 lit, float3 shade, float x, float y, float crest, float phase, float freq, float amp) {
    float h = terrain(x, phase, freq, amp);
    float hx = terrain(x + 0.022, phase, freq, amp);
    float slope = (hx - h) / 0.022;
    float ndl = saturate(0.16 + 0.84 * saturate(-slope * 3.4 + 0.32));
    float ao = saturate(0.42 + (crest - y) * 1.8);
    float grit = noise3(float3(x * 14.0, y * 18.0, phase));
    float3 color = mix(shade, lit, ndl);
    color *= 0.68 + 0.32 * ao;
    color += lit * pow(ndl, 11.0) * 0.18;
    float ridge = smoothstep(crest - 0.018, crest, y) * ndl;
    color += mix(lit, float3(1.0, 0.96, 0.88), 0.35) * ridge * 0.22;
    color *= 0.88 + 0.16 * grit;
    return color;
}

float3 silk(float3 p, Instance m) {
    Globe g = sphereOf(p);
    float t = m.time * (0.18 + 0.55 * m.advection);
    float3 q = g.wrap * (1.6 + m.inclusionDensity) + m.noiseOffset.xyz;
    q += float3(t * 0.18, sin(t * 0.4 + g.lon * 2.0) * 0.12, t * 0.07);
    float n1 = fbm(q);
    float n2 = fbm(q.zyx * 1.3 + 4.0);
    float n3 = fbm(q * 1.7 + float3(2.2, -1.4, t * 0.2));
    float mid = smoothstep(0.28, 0.72, n1);
    float ribbon = saturate(smoothstep(0.34, 0.7, n1) - smoothstep(0.55, 0.94, n2));
    float spark = smoothstep(0.62, 0.88, n3);
    float3 dark = hsv(m.hue, m.saturation, 0.16 + 0.18 * m.luminosity);
    float3 body = hsv(m.secondaryHue, min(1.0, m.saturation * 1.02), 0.62);
    float3 accent = hsv(accentHue(m), min(1.0, m.saturation * 0.88), 0.98);
    float3 color = mix(dark, body, mid);
    color = mix(color, accent, ribbon * 0.95);
    color = mix(color, accent, spark * 0.5);
    return contrast(color, 1.22);
}

float3 crystal(float3 p, Instance m) {
    Globe g = sphereOf(p);
    float2 field = float2(g.lon, g.lat) * (2.2 + m.inclusionDensity * 2.8) + m.noiseOffset.xy;
    float4 cellA = voronoiCell(field);
    float4 cellB = voronoiCell(field * 1.85 + 4.2);
    float4 cellC = voronoiCell(field * 3.1 - 2.6);
    float wash = fbm(g.wrap * 1.35 + m.noiseOffset.xyz);
    float wash2 = fbm(g.wrap.zyx * 2.3 + 1.4);
    float wash3 = fbm(g.wrap.xzy * 1.8 - m.noiseOffset.xyz);
    float3 deep = hsv(m.hue, m.saturation * 0.9, 0.12);
    float3 low = hsv(fract(m.hue + 0.05), m.saturation * 0.72, 0.28);
    float3 mid = hsv(m.secondaryHue, m.saturation * 0.58, 0.5);
    float3 lift = hsv(fract(m.secondaryHue + 0.07), m.saturation * 0.42, 0.78);
    float3 bg = mix(deep, low, saturate(g.lat * 0.42 + 0.38 + wash * 0.32));
    bg = mix(bg, mid, saturate(wash2 * 0.5 + g.r * 0.22));
    bg = mix(bg, lift, saturate(0.45 + 0.55 * sin(g.lon * 2.0 + wash3 * 5.0)) * wash * 0.42);

    float sizeA = 0.03 + cellA.y * 0.22;
    float sizeB = 0.02 + cellB.z * 0.14;
    float sizeC = 0.015 + cellC.w * 0.09;
    float flakeA = smoothstep(sizeA, sizeA * 0.22, cellA.x) * (0.18 + cellA.z * 0.82);
    float flakeB = smoothstep(sizeB, sizeB * 0.18, cellB.x) * (0.12 + cellB.w * 0.7);
    float flakeC = smoothstep(sizeC, sizeC * 0.2, cellC.x) * (0.08 + cellC.y * 0.55);
    float3 flakeDeep = hsv(m.secondaryHue, m.saturation, 0.28);
    float3 flakeMid = hsv(fract(m.secondaryHue + 0.04), m.saturation * 0.75, 0.62);
    float3 flakeLit = hsv(m.secondaryHue, m.saturation * 0.45, 0.98);
    float3 flake = mix(flakeDeep, flakeMid, cellA.w);
    flake = mix(flake, flakeLit, cellA.z * cellA.z);
    float3 color = mix(bg, flake, flakeA);
    color = mix(color, mix(flake, lift, 0.4), flakeB);
    color = mix(color, flakeLit, flakeC * 0.65);
    return contrast(color, 1.16);
}

float3 prism(float3 p, Instance m) {
    Globe g = sphereOf(p);
    float t = m.time * (0.12 + 0.4 * m.advection);
    int count = 2 + int(clamp(m.inclusionDensity * 2.99, 0.0, 2.99));
    float3 hues[4];
    hues[0] = hsv(m.hue, m.saturation, 0.82);
    hues[1] = hsv(m.secondaryHue, m.saturation * 0.95, 0.52);
    hues[2] = hsv(accentHue(m), m.saturation * 0.88, 0.9);
    hues[3] = hsv(m.hue, m.saturation * 0.7, 0.28);
    float wobble = 0.04 * sin(g.lat * 5.0 + t);
    float gores = 2.4 + m.inclusionDensity * 2.2;
    float u = g.lon * 0.318309886 * gores + 0.5 + wobble + t * 0.08;
    float scaled = fract(u) * float(count);
    int slot = int(floor(scaled));
    float f = fract(scaled);
    float3 color = hues[slot];
    int neighbor = f < 0.5 ? (slot + count - 1) % count : (slot + 1) % count;
    float seam = min(f, 1.0 - f);
    color = mix(hues[neighbor], color, smoothstep(0.0, 0.03, seam));
    return color;
}

float3 nebula(float3 p, Instance m) {
    Globe g = sphereOf(p);
    float t = m.time * (0.08 + 0.28 * m.advection);
    float3 q = g.wrap * 1.55 + m.noiseOffset.xyz + float3(t * 0.12, t * 0.05, -t * 0.08);
    float n = fbm(q);
    float m2 = fbm(g.wrap * 3.1 - m.noiseOffset.xyz);
    float m3 = fbm(g.wrap.zxy * 2.2 + 3.0);
    float cloud = smoothstep(0.3, 0.72, n);
    float vein = smoothstep(0.56, 0.84, m2);
    float ember = smoothstep(0.66, 0.9, m3);
    float3 dark = hsv(m.hue, m.saturation, 0.07 + 0.08 * m.luminosity);
    float3 gas = hsv(m.secondaryHue, m.saturation * 0.95, 0.72);
    float3 accent = hsv(accentHue(m), min(1.0, m.saturation * 0.86), 0.98);
    float3 color = mix(dark, gas, cloud);
    color = mix(color, accent, vein * 0.78);
    color = mix(color, accent, ember * 0.48);
    return color;
}

float3 coreFamily(float3 p, Instance m) {
    Globe g = sphereOf(p);
    float d = g.r + 0.024 * sin(g.lon * 5.0 + m.noiseOffset.x);
    float3 rim = hsv(m.hue, m.saturation * 0.22, 0.94);
    float3 body = hsv(m.hue, m.saturation * 0.62, 0.58);
    float3 ring = hsv(m.secondaryHue, m.saturation * 0.8, 0.78);
    float3 heart = hsv(accentHue(m), m.saturation * 0.72, 0.28);
    float3 color = rim;
    color = mix(color, body, smoothstep(0.88, 0.48, d));
    color = mix(color, ring, smoothstep(0.5, 0.22, d));
    color = mix(color, heart, smoothstep(0.24, 0.06, d));
    float4 fleck = voronoiCell(float2(g.lon, g.lat) * (5.5 + m.inclusionDensity * 4.0) + m.noiseOffset.xy);
    float fleckMask = smoothstep(0.06 + fleck.y * 0.1, 0.012, fleck.x) * (0.18 + fleck.z * 0.82);
    color = mix(color, mix(ring, heart, fleck.w), fleckMask * 0.55);
    return color;
}

float3 landscape(float3 p, Instance m, float radiusPoints) {
    Globe g = sphereOf(p);
    float x = g.lon;
    float y = g.lat;
    float fine = radiusPoints >= 60.0 ? 1.0 : 0.72;
    float3 zenith = hsv(m.hue, m.saturation * 0.68, 0.1 + 0.1 * m.luminosity);
    float3 midSky = hsv(fract(m.hue + 0.04), m.saturation * 0.48, 0.3);
    float3 horizonSky = hsv(fract(m.hue + 0.08), m.saturation * 0.32, 0.62);
    float3 glow = hsv(accentHue(m), m.saturation * 0.55, 0.88);
    float skyT = saturate(y * 0.82 + 0.28);
    float3 color = mix(horizonSky, midSky, smoothstep(0.0, 0.55, skyT));
    color = mix(color, zenith, pow(saturate(skyT), 1.45));
    float cloudsA = fbm(float3(x * 2.1 + m.noiseOffset.x, y * 2.8, m.noiseOffset.z));
    float cloudsB = fbm(float3(x * 3.6 - m.noiseOffset.y, y * 4.4, 2.2));
    color = mix(color, mix(color, float3(0.9, 0.88, 0.84), 0.62), smoothstep(0.5, 0.78, cloudsA) * saturate(y + 0.02));
    color = mix(color, mix(color, float3(0.78, 0.8, 0.86), 0.4), smoothstep(0.6, 0.86, cloudsB) * saturate(y - 0.08) * fine);

    if (radiusPoints >= 60.0) {
        float2 moon = float2(x, y) - float2(-0.55 + m.noiseOffset.x * 0.02, 0.42);
        float moonA = smoothstep(0.14, 0.06, length(moon));
        float moonB = smoothstep(0.09, 0.04, length(float2(x, y) - float2(0.5, 0.5)));
        color = mix(color, float3(0.96, 0.91, 0.74), moonA * 0.88);
        color = mix(color, float3(0.76, 0.82, 0.95), moonB * 0.68);
    }

    float3 hazeLit = hsv(fract(m.hue + 0.06), m.saturation * 0.28, 0.34);
    float3 hazeShade = hsv(m.hue, m.saturation * 0.3, 0.16);
    float3 farLit = hsv(fract(m.secondaryHue + 0.03), m.saturation * 0.42, 0.4);
    float3 farShade = hsv(m.hue, m.saturation * 0.4, 0.13);
    float3 midLit = hsv(m.secondaryHue, m.saturation * 0.72, 0.5);
    float3 midShade = hsv(fract(m.secondaryHue + 0.05), m.saturation * 0.68, 0.16);
    float3 nearLit = hsv(fract(m.secondaryHue + 0.08), m.saturation * 0.78, 0.44);
    float3 nearShade = hsv(m.secondaryHue, m.saturation * 0.82, 0.1);
    float3 fgLit = hsv(accentHue(m), m.saturation * 0.7, 0.4);
    float3 fgShade = hsv(fract(accentHue(m) + 0.04), m.saturation * 0.75, 0.07);

    float hazeH = 0.08 + terrain(x, m.noiseOffset.x - 2.4, 2.6 * fine, 0.07);
    float farH = -0.02 + terrain(x, m.noiseOffset.x, 3.8 * fine, 0.11);
    float midH = -0.16 + terrain(x, m.noiseOffset.y + 1.7, 5.8 * fine, 0.14);
    float nearH = -0.3 + terrain(x, m.noiseOffset.z + 3.1, 8.2 * fine, 0.16);
    float fgH = -0.44 + terrain(x, m.noiseOffset.x + 5.2, 10.4 * fine, 0.14);

    float glowBand = smoothstep(farH + 0.16, farH + 0.02, y) * smoothstep(farH - 0.03, farH + 0.01, y);
    color = mix(color, glow, glowBand * 0.72);

    if (y < hazeH) {
        color = mix(shadeSlope(hazeLit, hazeShade, x, y, hazeH, m.noiseOffset.x - 2.4, 2.6 * fine, 0.07), color, 0.42);
    }
    if (y < farH) {
        color = mix(shadeSlope(farLit, farShade, x, y, farH, m.noiseOffset.x, 3.8 * fine, 0.11), color, 0.12);
    }
    if (y < midH) {
        color = shadeSlope(midLit, midShade, x, y, midH, m.noiseOffset.y + 1.7, 5.8 * fine, 0.14);
    }
    if (y < nearH) {
        color = shadeSlope(nearLit, nearShade, x, y, nearH, m.noiseOffset.z + 3.1, 8.2 * fine, 0.16);
    }
    if (y < fgH) {
        color = shadeSlope(fgLit, fgShade, x, y, fgH, m.noiseOffset.x + 5.2, 10.4 * fine, 0.14);
    }
    return color;
}

float3 interior(float3 p, Instance m, float radiusPoints) {
    int family = int(m.family + 0.5);
    if (family == 1) return crystal(p, m);
    if (family == 2) return prism(p, m);
    if (family == 3) return nebula(p, m);
    if (family == 4) return landscape(p, m, radiusPoints);
    if (family == 5) return coreFamily(p, m);
    return silk(p, m);
}

float3 applyErrorHue(float3 color, float amount) {
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 red = float3(min(1.0, luma * 1.25 + 0.22), luma * 0.28, luma * 0.24);
    return mix(color, red, saturate(amount));
}

float wrapAngle(float a) {
    return atan2(sin(a), cos(a));
}

float2 intersectSphere(float3 ro, float3 rd) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - 1.0;
    float h = b * b - c;
    if (h < 0.0) return float2(-1.0);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

float3 envMap(float3 direction, float3 light) {
    float3 d = normalize(direction);
    float sky = pow(saturate(d.y * 0.5 + 0.5), 0.65);
    float3 col = mix(float3(0.20, 0.21, 0.24), float3(0.88, 0.93, 1.0), sky);
    col += pow(saturate(dot(d, light)), 10.0) * 0.55;
    col += pow(saturate(dot(d, light)), 220.0) * 3.4;
    return col;
}

float3 sampleVolume(float3 p, Instance m, float radiusPoints, float advect) {
    if (advect > 0.0) {
        float a = m.time * 0.11 * advect;
        float c = cos(a);
        float s = sin(a);
        p = float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
    }
    if (m.pulse > 0.5) {
        p *= 1.0 + 0.04 * sin(m.time * 2.2);
    }
    p += m.noiseOffset.xyz * 0.04;
    return interior(p, m, radiusPoints);
}

vertex VertexOut marble_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant Instance *instances [[buffer(0)]],
    constant FrameConstants &frame [[buffer(1)]]
) {
    Instance m = instances[iid];
    float2 corner = kCorners[vid];
    float pad = 1.03;
    float2 pixel = m.center + corner * m.radius * pad;
    float2 ndc = pixel / frame.viewport * 2.0 - 1.0;
    VertexOut out;
    out.position = float4(ndc, 0, 1);
    out.uv = corner * pad;
    out.iid = iid;
    return out;
}

fragment float4 marble_fragment(
    VertexOut in [[stage_in]],
    constant Instance *instances [[buffer(0)]],
    constant FrameConstants &frame [[buffer(1)]]
) {
    Instance m = instances[in.iid];
    float2 uv = in.uv;
    float3 light = normalize(float3(-0.48, 0.78, 0.42));
    float3 ro = float3(0.0, 0.0, 2.45);
    float3 rd = normalize(float3(uv, -1.75));
    float2 hit = intersectSphere(ro, rd);

    if (hit.x < 0.0) {
        return float4(0);
    }

    float3 pos0 = ro + rd * hit.x;
    float3 nor0 = pos0;
    float eta = mix(1.0 / 1.52, 1.0 / 1.38, m.frost);
    float3 rfr0 = refract(rd, nor0, eta);
    if (dot(rfr0, rfr0) < 1e-6) {
        rfr0 = reflect(rd, nor0);
    }

    float2 exitHit = intersectSphere(pos0 + rfr0 * 0.003, rfr0);
    float path = max(exitHit.y, 0.08);
    float3 mid = pos0 + rfr0 * (path * 0.42);

    float advect = m.freeze > 0.5 ? 0.0 : m.advection;
    Instance moving = m;
    moving.advection = advect;
    float radiusPoints = m.radius * frame.pointsPerPixel;

    float3 rfrR = refract(rd, nor0, eta * 0.985);
    float3 rfrB = refract(rd, nor0, eta * 1.018);
    if (dot(rfrR, rfrR) < 1e-6) rfrR = rfr0;
    if (dot(rfrB, rfrB) < 1e-6) rfrB = rfr0;
    float3 midR = pos0 + rfrR * (path * 0.42);
    float3 midB = pos0 + rfrB * (path * 0.42);

    float3 volume;
    volume.r = sampleVolume(midR, moving, radiusPoints, advect).r;
    volume.g = sampleVolume(mid, moving, radiusPoints, advect).g;
    volume.b = sampleVolume(midB, moving, radiusPoints, advect).b;
    float3 volumeDeep = sampleVolume(pos0 + rfr0 * (path * 0.72), moving, radiusPoints, advect);
    volume = mix(volume, volumeDeep, 0.35);

    float3 beer = exp(-(1.15 - volume) * path * (0.42 + m.frost * 0.35));
    float pulseGlow = m.pulse * (0.08 + 0.07 * sin(m.time * 2.4));
    volume = contrast(volume * beer, 1.18);
    volume *= 0.86 + 0.28 * m.luminosity + pulseGlow;

    float2 p = pos0.xy;
    float rad = length(p);
    float ang = atan2(p.y, p.x);

    float inset = clamp(2.8 / max(radiusPoints, 10.0), 0.07, 0.16);
    float outer = 1.0 - inset;
    float tightRing = smoothstep(outer - 0.24, outer - 0.10, rad) * smoothstep(outer + 0.004, outer - 0.05, rad);
    float coreRing = smoothstep(outer - 0.16, outer - 0.06, rad) * smoothstep(outer, outer - 0.035, rad);
    float softRing = smoothstep(outer - 0.40, outer - 0.20, rad) * smoothstep(outer - 0.02, outer - 0.12, rad);

    float dUL = wrapAngle(ang - 2.28);
    float dBR = wrapAngle(ang + 0.72);
    float sharp = (tightRing * exp(-dUL * dUL * 3.1) + coreRing * exp(-dUL * dUL * 4.4) * 0.65)
        * mix(1.0, 0.55, m.frost);
    float bounce = softRing * exp(-dBR * dBR * 2.1) * mix(0.38, 0.22, m.frost);

    float fre0 = 0.05 + 0.55 * pow(saturate(1.0 + dot(nor0, rd)), 5.0);
    float3 color = volume * (1.0 - fre0 * 0.35);
    color += float3(1.0, 0.99, 0.96) * sharp * (1.15 + m.rimBoost * 1.2);
    color += volume * bounce;
    color += float3(0.82, 0.88, 1.0) * bounce * 0.55;
    color += envMap(reflect(rd, nor0), light) * fre0 * 0.12;
    color += sharp * m.attention * 0.25;

    if (m.bloom > 0.0) {
        float bloomAng = atan2(uv.y, uv.x);
        float sweep = pow(saturate(sin(bloomAng * 2.0 + m.bloom * 9.0 + uv.x * 4.0)), 3.0);
        color += float3(1.0, 0.96, 0.88) * sweep * m.bloom * 0.45;
    }

    color = applyErrorHue(color, m.errorHue);
    color *= 1.0 - m.dim * 0.45;

    float shell = smoothstep(0.58, 0.97, rad);
    float bodyAlpha = mix(0.96, 0.32, shell);
    float alpha = max(bodyAlpha, sharp * 0.9 + bounce * 0.25);
    alpha *= 1.0 - m.dim * 0.2;
    color = saturate(color);
    return float4(color * alpha, alpha);
}
