#ifndef SF_GLSL
#define SF_GLSL

// ================================
// Functions: Surface
// ================================

#define SF_GRADIENT(name, scene)                                \
vec3 name(vec3 p, float e)                                      \
{                                                               \
    return vec3(                                                \
        scene(p + vec3(e, 0.0, 0.0)).d - scene(p - vec3(e, 0.0, 0.0)).d, \
        scene(p + vec3(0.0, e, 0.0)).d - scene(p - vec3(0.0, e, 0.0)).d, \
        scene(p + vec3(0.0, 0.0, e)).d - scene(p - vec3(0.0, 0.0, e)).d  \
    ) / (2.0 * e);                                              \
}

#define SF_NORMAL(name, scene)                                           \
vec3 name(vec3 p, float e)                                               \
{                                                                        \
    return normalize(vec3(                                               \
        scene(p + vec3(e, 0.0, 0.0)).d - scene(p - vec3(e, 0.0, 0.0)).d, \
        scene(p + vec3(0.0, e, 0.0)).d - scene(p - vec3(0.0, e, 0.0)).d, \
        scene(p + vec3(0.0, 0.0, e)).d - scene(p - vec3(0.0, 0.0, e)).d  \
    ));                                                                  \
}

#define SF_NORMAL_TETRAHEDRON(name, scene) \
vec3 name(vec3 p, float e)                 \
{                                          \
    const vec2 k = vec2(1.0, -1.0);        \
    return normalize(                      \
        k.xyy * scene(p + k.xyy * e).d +   \
        k.yyx * scene(p + k.yyx * e).d +   \
        k.yxy * scene(p + k.yxy * e).d +   \
        k.xxx * scene(p + k.xxx * e).d     \
    );                                     \
}

#define SF_CURVATURE(name, scene)                                               \
float name(vec3 p, float e)                                                     \
{                                                                               \
    float c = scene(p).d;                                                       \
    float s = scene(p + vec3(e, 0.0, 0.0)).d + scene(p - vec3(e, 0.0, 0.0)).d + \
              scene(p + vec3(0.0, e, 0.0)).d + scene(p - vec3(0.0, e, 0.0)).d + \
              scene(p + vec3(0.0, 0.0, e)).d + scene(p - vec3(0.0, 0.0, e)).d;  \
    return 0.5 * (s - 6.0 * c) / (e * e);                                       \
}

#define SF_PROJECT(name, scene)                                              \
vec3 name(vec3 p, int iterations, float e)                                   \
{                                                                            \
    for (int i = 0; i < iterations; i++)                                     \
    {                                                                        \
        float d = scene(p).d;                                                \
        vec3 n = normalize(vec3(                                             \
            scene(p + vec3(e, 0.0, 0.0)).d - scene(p - vec3(e, 0.0, 0.0)).d, \
            scene(p + vec3(0.0, e, 0.0)).d - scene(p - vec3(0.0, e, 0.0)).d, \
            scene(p + vec3(0.0, 0.0, e)).d - scene(p - vec3(0.0, 0.0, e)).d  \
        ));                                                                  \
        p -= d * n;                                                          \
    }                                                                        \
    return p;                                                                \
}

#define SF_THICKNESS(name, scene)                                  \
float name(vec3 p, vec3 n, int iterations, float maxDist, float e) \
{                                                                  \
    float t = e;                                                   \
    for (int i = 0; i < iterations; i++)                           \
    {                                                              \
        float d = scene(p - n * t).d;                              \
        if (d >= 0.0 || t >= maxDist) break;                       \
        t += max(-d, e);                                           \
    }                                                              \
    return min(t, maxDist);                                        \
}

#endif // SF_GLSL
