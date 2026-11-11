# rlm-c3

A raymarching toolkit for [raylib](https://www.raylib.com/) written in [C3](https://c3-lang.org/).

With it you just have to write the scene and the shading function, then the lib handles the rest.

It's the GPU follow-up to my CPU raymarcher, [rm-c3](https://github.com/Bigfoot71/rm-c3).

Works with OpenGL 2.1 / 3.3 / 4.3, OpenGL ES 2.0 / 3.0 and WebGL 1 / 2.

## Usage

```c3
rlm::init(w, h);
defer rlm::quit();

RLMShader shader = rlm::load_shader("scene.glsl")!!;
defer shader.free();

while (!rl::window_should_close())
{
    rl::@drawing()
    {
        shader.set_value("time", (float)rl::get_time());
        rlm::present(&shader, camera);
    };
}
```

- `render()` renders to an internal texture and returns it.
- `present()` render the scene and draw it directly to the screen.
- Both take an optional viewport, aspect ratio and far distance.

## Writing a shader

Your shader should defines two functions:

```glsl
Sd scene(vec3 p);
vec4 shade(Ray ray, Hit hit, float cone);
```

`Sd` is a distance plus a material id.
`Hit` holds the hit position, distance, material, step count and coverage.
`cone` is the pixel footprint per unit of distance, handy for filtering procedural textures.

```glsl
#include <sd.glsl>
#include <op.glsl>

Sd scene(vec3 p)
{
    Sd ground = sdPlane(p, vec3(0, 1, 0), 1.0, 0);
    Sd ball   = sdSphere(p, 1.0, 1);
    return opUnion(ground, ball);
}

vec4 shade(Ray ray, Hit hit, float cone)
{
    if (!hit.hit) return vec4(0.5, 0.7, 1.0, 1.0);
    // ...
}
```

You can set uniforms with `set_value()`, they are cached and uploaded only when they change.
The supported types are all those supported by raylib, you can also pass 2D textures.

## Built-in headers

| Header | Content |
|---|---|
| `math.glsl` | Constants, `saturate`, `dot2`, `basis`, etc. |
| `sd.glsl` | SDF primitives (Inigo Quilez) |
| `op.glsl` | Boolean, smooth, and domain operators |
| `sf.glsl` | Normal, gradient, curvature, projection, thickness |
| `sh.glsl` | PBR BRDFs, point and spot lights, hard and soft shadows, AO, reflections, transmittance, fog, rim light, glow |

Functions that call `scene()` are macros you instantiate yourself, for example:

```glsl
SF_NORMAL(getNormal, scene)
SH_SOFT_SHADOW(softShadow, scene)
```

## Built-in optimizations

- A low-res pass (one ray per 16x16 tile by default) to find a safe starting distance for every pixel in the tile.
- Over relaxed sphere tracing with automatic backtracking ([enhanced sphere tracing](https://kev.town/raymarching-toolkit/media/enhanced_sphere_tracing.pdf)).
- Edge anti aliasing, near misses are tracked during the march and a second shading is blended in where a ray grazes an edge.
- Hit threshold scales with distance (cone tracing).

## Defines

You can redefine these constants in your code to override them:

`MAX_STEPS` (128), `BEAM_STEPS`, `EPS`, `OMEGA0`, `BEAM_SAFETY`, `SRGB_OUTPUT` (1), `EDGE_AA` (1)

## Contributing

Need a feature? Open an issue!
