// ================================
// Precision
// ================================

#ifdef GL_ES
#   ifdef GL_FRAGMENT_PRECISION_HIGH
        precision highp float;
#   else
        precision mediump float;
#   endif
#endif

// ================================
// In - Varyings
// ================================

VARY vec2 UV;

// ================================
// Built-In Uniforms
// ================================

uniform int       CURRENT_PASS;   // 0 = beam, 1 = shading

uniform vec2      RES;            // render size in pixels
uniform vec2      BEAM_RES;       // beam viewport size in tiles
uniform vec2      BEAM_TEX_SIZE;  // beam texture size in texels
uniform float     BEAM_TILE;      // tile size in pixels

uniform vec3      CAM_POS;
uniform vec3      CAM_FWD;
uniform vec3      CAM_RIGHT;      // pre-scaled by aspect * tan(fov/2)
uniform vec3      CAM_UP;         // pre-scaled by tan(fov/2)
uniform float     CAM_FAR;

uniform float     CONE;           // pixel footprint per unit of distance
uniform float     BEAM_CONE;      // tile footprint per unit of distance

uniform sampler2D BEAM_TEX;       // packed safe start distance per tile

// ================================
// Types
// ================================

struct Ray
{
    vec3 origin;
    vec3 dir;
};

struct Hit
{
    bool  hit;    // true if a surface was reached
    float dist;   // distance along the ray (CAM_FAR on miss)
    float d;      // SDF value at the hit
    int   mat;    // material id at the hit
    int   steps;  // iterations used (debug)
    vec3  pos;    // ray.origin + ray.dir * dist
    float cov;    // weight of this shading in the final pixel
};

struct Graze   // near miss (SDF value r at distance t)
{
    float r;
    float t;
    int   m;
};

struct Sd
{
    float d;
    int   mat;
};

// ================================
// User Code
// ================================

//@USER_CODE

// ================================
// Parameters
// ================================

#ifndef MAX_STEPS
#   define MAX_STEPS 128
#endif

#ifndef BEAM_STEPS
#   define BEAM_STEPS (MAX_STEPS / 2)
#endif

#ifndef EPS
#   define EPS 0.0005
#endif

#ifndef OMEGA0
#   define OMEGA0 1.6
#endif

#ifndef BEAM_SAFETY
#   define BEAM_SAFETY 0.98
#endif

#ifndef SRGB_OUTPUT
#   define SRGB_OUTPUT 1
#endif

#ifndef EDGE_AA
#   define EDGE_AA 1
#endif

#if EDGE_AA
#   ifndef EDGE_AA_MIN_COV
#      define EDGE_AA_MIN_COV 0.02  // below this the edge is not worth a second shading
#   endif
#   ifndef EDGE_AA_HIT
#       define EDGE_AA_HIT 0.25     // hit within this fraction of the pixel footprint
#   endif
#   ifndef EDGE_AA_RAMP
#       define EDGE_AA_RAMP 1.5     // coverage reaches 0 at this many footprints
#   endif
#else
#   define EDGE_AA_HIT  1.0
#   define EDGE_AA_RAMP 0.0
#endif

// ================================
// Beam texture packing
// ================================

const float PACK_SCALE = 0.99999;

vec4 packFloat(float v)
{
    vec4 e = fract(v * vec4(1.0, 255.0, 65025.0, 16581375.0));
    e -= e.yzww * vec4(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 0.0);
    return e;
}

float unpackFloat(vec4 c)
{
    return dot(c, vec4(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 16581375.0));
}

// ================================
// Rays
// ================================

Ray makeRay(vec2 pix)
{
    vec2 ndc = pix * (2.0 / RES) - 1.0;
    return Ray(CAM_POS, normalize(CAM_FWD + CAM_RIGHT * ndc.x + CAM_UP * ndc.y));
}

// ================================
// Beam
// ================================

float marchBeam(Ray ray)
{
    // safe start distance for a whole tile

    float cone = BEAM_CONE + EDGE_AA_RAMP * CONE;
    float inv  = 1.0 / (1.0 + cone);
    float t    = 0.0;

    for (int i = 0; i < BEAM_STEPS; i++)
    {
        float margin = t * cone + EPS;
        float r      = scene(ray.origin + ray.dir * t).d;

        if (r <= margin) break;

        t += (r - margin) * inv;

        if (t >= CAM_FAR) return CAM_FAR;
    }

    return t * BEAM_SAFETY;
}

// ================================
// Edge Anti-Aliasing
// ================================

const Graze NO_GRAZE = Graze(1.0e9, 1.0, 0);

#if EDGE_AA

bool closer(Graze a, Graze b)
{
    return a.r * b.t < b.r * a.t;
}

void trackGraze(inout Graze prev, inout Graze best, Graze s)
{
    if (!closer(s, prev) && closer(prev, best)) best = prev;
    prev = s;
}

float grazeCoverage(Graze g)
{
    float q = g.r / max(g.t * CONE, 1.0e-6); // in pixel footprints
    return clamp((EDGE_AA_RAMP - q) / (EDGE_AA_RAMP - EDGE_AA_HIT), 0.0, 1.0);
}

Hit grazeHit(Ray ray, Hit base, Graze g, float cov)
{
    Hit h = base;
    h.hit  = true;
    h.dist = g.t;
    h.d    = g.r;
    h.mat  = g.m;
    h.pos  = ray.origin + ray.dir * g.t;
    h.cov  = cov;
    return h;
}

#endif // EDGE_AA

// ================================
// March
// ================================

Hit march(Ray ray, float t0, out Graze gz)
{
    // sphere tracing with over relaxation

    Hit h = Hit(false, CAM_FAR, 0.0, 0, 0, vec3(0.0), 1.0);

    float t     = min(t0, CAM_FAR);
    float stp   = 0.0;
    float prevR = 0.0;
    float omega = OMEGA0;

    gz = NO_GRAZE;

#if EDGE_AA
    Graze prev = NO_GRAZE;
#endif

    for (int i = 0; i < MAX_STEPS; i++)
    {
        if (t >= CAM_FAR) break;

        Sd    s = scene(ray.origin + ray.dir * t);
        float r = s.d;

        bool back = omega > 1.0 && (r + prevR) < stp;

        h.steps = i + 1;

        if (!back && r < max(EPS, t * CONE * EDGE_AA_HIT))
        {
            h.hit  = true;
            h.dist = t;
            h.d    = r;
            h.mat  = s.mat;
            break;
        }

        if (back)
        {
            t    += prevR - stp;
            stp   = prevR;
            omega = 1.0;
        }
        else
        {
        #if EDGE_AA
            trackGraze(prev, gz, Graze(r, t, s.mat));
        #endif
            stp   = r * omega;
            t    += stp;
            prevR = r;
        }
    }

#if EDGE_AA
    if (!h.hit) trackGraze(prev, gz, NO_GRAZE);
#endif

    h.pos = ray.origin + ray.dir * h.dist;
    return h;
}

// ================================
// Main Function
// ================================

void main()
{
    if (CURRENT_PASS == 0)
    {
        vec2 tile = floor(UV * BEAM_RES);
        float t0  = marchBeam(makeRay((tile + 0.5) * BEAM_TILE));

        FRAG_COLOR = packFloat(t0 / CAM_FAR * PACK_SCALE);
    }
    else
    {
        vec2 pix  = UV * RES;
        vec2 tile = min(floor(pix / BEAM_TILE), BEAM_RES - 1.0);
        float t0  = unpackFloat(TEXTURE_2D(BEAM_TEX, (tile + 0.5) / BEAM_TEX_SIZE)) / PACK_SCALE * CAM_FAR;

        Ray   ray = makeRay(pix);
        Graze gz;
        Hit   hit = march(ray, t0, gz);

    #if EDGE_AA
        float gcov = grazeCoverage(gz);
        hit.cov = 1.0 - gcov;

        Hit  cur = hit;
        vec4 col = vec4(0.0);

        for (int k = 0; k < 2; k++)
        {
            vec4 c = shade(ray, cur, CONE);

            col = (k == 0) ? c : mix(col, c, gcov);

            if (gcov <= EDGE_AA_MIN_COV) break;

            cur = grazeHit(ray, hit, gz, gcov);
        }
    #else
        vec4 col = shade(ray, hit, CONE);
    #endif

    #if SRGB_OUTPUT
        col.rgb = sqrt(max(col.rgb, 0.0));
    #endif

        FRAG_COLOR = col;
    }
}
