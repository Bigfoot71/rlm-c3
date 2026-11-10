#ifndef MATH_GLSL
#define MATH_GLSL

// ================================
// Constants
// ================================

#define M_PI            3.1415926535897931
#define M_TAU           6.2831853071795862
#define M_HALF_PI       1.5707963267948966
#define M_INV_PI        0.3183098861837907
#define M_PHI           1.6180339887498949
#define M_PHI_FRAC      0.6180339887498949
#define M_GOLDEN_ANGLE  2.3999632297286535

// ================================
// Functions
// ================================

float saturate(float x)
{
    return clamp(x, 0.0, 1.0);
}

vec2 saturate(vec2 x)
{
    return clamp(x, vec2(0.0), vec2(1.0));
}

vec3 saturate(vec3 x)
{
    return clamp(x, vec3(0.0), vec3(1.0));
}

vec4 saturate(vec4 x)
{
    return clamp(x, vec4(0.0), vec4(1.0));
}

float dot2(vec2 x)
{
    return dot(x, x);
}

float dot2(vec3 x)
{
    return dot(x, x);
}

float dot2(vec4 x)
{
    return dot(x, x);
}

mat3 basis(vec3 n)
{
    float s = (n.z >= 0.0) ? 1.0 : -1.0;
    float a = -1.0 / (s + n.z);
    float b = n.x * n.y * a;

    vec3 t  = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
    vec3 bt = vec3(b, s + n.y * n.y * a, -n.y);

    return mat3(t, bt, n);
}

vec3 offsetAlong(vec3 p, vec3 n, float bias)
{
    return p + n * bias;
}

#endif // MATH_GLSL
