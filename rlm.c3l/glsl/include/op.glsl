#ifndef OP_GLSL
#define OP_GLSL

// Functions adapted from the work of Inigo Quilez:
//  => https://iquilezles.org/articles/distfunctions/

// ================================
// Functions: Math Helpers
// ================================

float _op_smin(float a, float b, float k)
{
    k *= 4.0;
    float h = max(k - abs(a - b), 0.0);
    return min(a, b) - h * h * 0.25 / k;
}

// ================================
// Functions: Boolean Operators
// ================================

Sd opUnion(Sd a, Sd b)
{
    return (a.d < b.d) ? a : b;
}

Sd opSubtraction(Sd a, Sd b)
{
    float na = -a.d;
    return Sd(max(na, b.d), (na > b.d) ? a.mat : b.mat);
}

Sd opIntersection(Sd a, Sd b)
{
    return (a.d > b.d) ? a : b;
}

Sd opXor(Sd a, Sd b)
{
    float u = min(a.d, b.d);
    float i = max(a.d, b.d);

    int matU = (a.d < b.d) ? a.mat : b.mat;
    int matI = (a.d < b.d) ? b.mat : a.mat;

    return Sd(max(u, -i), (u > -i) ? matU : matI);
}

Sd opSmoothUnion(Sd a, Sd b, float k)
{
    return Sd(_op_smin(a.d, b.d, k), (a.d < b.d) ? a.mat : b.mat);
}

Sd opSmoothSubtraction(Sd a, Sd b, float k)
{
    float na = -a.d;
    return Sd(-_op_smin(a.d, -b.d, k), (na > b.d) ? a.mat : b.mat);
}

Sd opSmoothIntersection(Sd a, Sd b, float k)
{
    return Sd(-_op_smin(-a.d, -b.d, k), (a.d > b.d) ? a.mat : b.mat);
}

// ================================
// Functions: Domain Operators
// ================================

vec3 opTx(vec3 p, mat4 invT)
{
    return (invT * vec4(p, 1.0)).xyz;
}

vec3 opTranslate(vec3 p, vec3 t)
{
    return p - t;
}

vec3 opScale(vec3 p, float s)
{
    return p / s;
}

Sd opScaleSd(Sd a, float s)
{
    return Sd(a.d * s, a.mat);
}

vec3 opSymX(vec3 p)
{
    p.x = abs(p.x);
    return p;
}

vec3 opSymXZ(vec3 p)
{
    p.xz = abs(p.xz);
    return p;
}

vec3 opRepetition(vec3 p, vec3 s)
{
    return p - s * round(p / s);
}

vec3 opLimitedRepetition(vec3 p, float s, vec3 l)
{
    return p - s * clamp(round(p / s), -l, l);
}

vec3 opTwist(vec3 p, float k)
{
    float c = cos(k * p.y);
    float s = sin(k * p.y);
    mat2  m = mat2(c, -s, s, c);
    return vec3(m * p.xz, p.y);
}

vec3 opCheapBend(vec3 p, float k)
{
    float c = cos(k * p.x);
    float s = sin(k * p.x);
    mat2  m = mat2(c, -s, s, c);
    return vec3(m * p.xy, p.z);
}

vec3 opElongate(vec3 p, vec3 h)
{
    return p - clamp(p, -h, h);
}

float opElongateEx(vec3 p, vec3 h, out vec3 q)
{
    vec3 v = abs(p) - h;
    q = max(v, 0.0);
    return min(max(v.x, max(v.y, v.z)), 0.0);
}

// ================================
// Functions: Domain Operators
// ================================

vec2 opRevolution(vec3 p, float o)
{
    return vec2(length(p.xz) - o, p.y);
}

Sd opExtrusion(vec3 p, float d2, float h, int mat)
{
    vec2 w = vec2(d2, abs(p.z) - h);
    return Sd(min(max(w.x, w.y), 0.0) + length(max(w, 0.0)), mat);
}

// ================================
// Functions: Distance Operators
// ================================

Sd opDisplace(Sd a, float displacement)
{
    return Sd(a.d + displacement, a.mat);
}

Sd opRound(Sd a, float rad)
{
    return Sd(a.d - rad, a.mat);
}

Sd opOnion(Sd a, float thickness)
{
    return Sd(abs(a.d) - thickness, a.mat);
}

#endif // OP_GLSL
