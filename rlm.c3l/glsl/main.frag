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
uniform vec3      CAM_RIGHT;      // already scaled by aspect * tan(fov/2)
uniform vec3      CAM_UP;         // already scaled by tan(fov/2)
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
    vec3 dir = CAM_FWD + CAM_RIGHT * ndc.x + CAM_UP * ndc.y;
    return Ray(CAM_POS, normalize(dir));
}

// ================================
// Beam
// ================================

float marchBeam(Ray ray)
{
    // safe start distance for a whole tile

    float t      = 0.0;
    float result = CAM_FAR;
    bool  alive  = true;
    float inv    = 1.0 / (1.0 + BEAM_CONE);

    for (int i = 0; i < BEAM_STEPS; i++)
    {
        if (!alive) break;

        float r      = scene(ray.origin + ray.dir * t).d;
        float margin = t * BEAM_CONE + EPS;

        if (r <= margin)
        {
            result = t * BEAM_SAFETY;
            alive  = false;
            break;
        }

        t += (r - margin) * inv;

        if (t >= CAM_FAR) alive = false;
    }

    return alive ? t * BEAM_SAFETY : result;
}

// ================================
// March
// ================================

Hit march(Ray ray, float t0)
{
    // sphere tracing with over relaxation

    Hit h;
    h.hit   = false;
    h.dist  = CAM_FAR;
    h.d     = 0.0;
    h.mat   = 0;
    h.steps = 0;

    float t     = min(t0, CAM_FAR);
    float stp   = 0.0;   // last step actually taken
    float prevR = 0.0;   // last SDF value kept as reference
    float omega = OMEGA0;

    for (int i = 0; i < MAX_STEPS; i++)
    {
        if (t >= CAM_FAR) break;

        Sd    s    = scene(ray.origin + ray.dir * t);
        float r    = s.d;
        float foot = t * CONE;

        bool back = omega > 1.0 && (r + prevR) < stp;

        h.steps = i + 1;

        if (!back && r < max(EPS, foot))
        {
            h.hit  = true;
            h.dist = t;
            h.d    = r;
            h.mat  = s.mat;
            break;
        }

        if (back)
        {
            t     += prevR - stp;
            stp    = prevR;
            omega  = 1.0;
        }
        else
        {
            float ns = r * omega;
            t     += ns;
            stp    = ns;
            prevR  = r;
        }
    }

    h.pos = ray.origin + ray.dir * h.dist;
    return h;
}

// ================================
// Main Function
// ================================

void main()
{
    if (CURRENT_PASS == 0) // BEAM PASS
    {
        vec2 tile = floor(UV * BEAM_RES);
        vec2 pix  = (tile + 0.5) * BEAM_TILE;

        float t0 = marchBeam(makeRay(pix));

        FRAG_COLOR = packFloat(clamp(t0 / CAM_FAR, 0.0, 1.0) * PACK_SCALE);
    }
    else
    if (CURRENT_PASS == 1) // SHADING PASS
    {
        vec2 pix  = UV * RES;
        vec2 tile = min(floor(pix / BEAM_TILE), BEAM_RES - 1.0);
        vec2 buv  = (tile + 0.5) / BEAM_TEX_SIZE;

        float t0 = unpackFloat(TEXTURE_2D(BEAM_TEX, buv)) / PACK_SCALE * CAM_FAR;

        Ray ray = makeRay(pix);
        Hit hit = march(ray, t0);

        FRAG_COLOR = shade(ray, hit, CONE);

        #if SRGB_OUTPUT == 1
            FRAG_COLOR.rgb = sqrt(max(FRAG_COLOR.rgb, 0.0));
        #endif
    }
}
