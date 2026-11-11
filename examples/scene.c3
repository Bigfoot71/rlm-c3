import raylib6;
import std::math;
import rlm;

const WIN_W = 1280;
const WIN_H = 720;

fn int main()
{
	rl::init_window(WIN_W, WIN_H, "RLM Scene");
	defer rl::close_window();
	rl::set_target_fps(60);

	rlm::init(WIN_W, WIN_H);
	defer rlm::quit();

	RLMShader shader = rlm::load_shader_from_memory(SHADER)!!;
	defer shader.free();

	RLCamera3D camera = {
		.position   = { 0.0f, 2.5f, 7.0f },
		.target     = { 0.0f, 0.8f, 0.0f },
		.up         = { 0.0f, 1.0f, 0.0f },
		.fovy       = 60.0f,
		.projection = PERSPECTIVE,
	};

	float angle = 0.0f;

	while (!rl::window_should_close())
	{
		if (!rl::is_mouse_button_down(LEFT))
		{
			angle += rl::get_frame_time() * 0.4f;
		}

		camera.position.x = 7.0f * math::sin(angle);
		camera.position.z = 7.0f * math::cos(angle);

		rl::@drawing()
		{
			rl::clear_background(rl::BLACK);
			rlm::present(&shader, camera);
			rl::draw_fps(10, 10);
		};
	}

	return 0;
}

const SHADER = `
#include <math.glsl>
#include <sd.glsl>
#include <op.glsl>
#include <sf.glsl>
#include <sh.glsl>

// ================================
// Constants
// ================================

#define MAT_FLOOR  1
#define MAT_MIRROR 2
#define MAT_RED    3
#define MAT_GOLD   4
#define MAT_BLUE   5

const vec3 SUN       = normalize(vec3(0.4, 0.8, 0.45));
const vec3 SUN_COLOR = vec3(1.0, 0.9, 0.75) * 2.5;

const vec3 SKY_HORIZON = vec3(0.75, 0.85, 0.95);
const vec3 SKY_TOP     = vec3(0.15, 0.35, 0.75);

const vec3 AMBIENT_SKY = vec3(0.25, 0.35, 0.55);
const vec3 AMBIENT_GND = vec3(0.15, 0.12, 0.10);

// ================================
// Scene
// ================================

Sd scene(vec3 p)
{
    Sd floor  = sdPlane(p, vec3(0.0, 1.0, 0.0), 0.0, MAT_FLOOR);
    Sd mirror = sdSphere(p - vec3(0.0, 1.0, 0.0), 1.0, MAT_MIRROR);
    Sd box    = sdRoundBox(p - vec3(-2.4, 0.5, 0.8), vec3(0.5), 0.1, MAT_RED);
    Sd torus  = sdTorus(p - vec3(2.4, 0.25, 0.4), vec2(0.7, 0.25), MAT_GOLD);
    Sd caps   = sdVerticalCapsule(p - vec3(0.6, 0.0, -2.2), 1.2, 0.3, MAT_BLUE);

    return opUnion(opUnion(opUnion(floor, mirror), opUnion(box, torus)), caps);
}

SF_NORMAL_TETRAHEDRON(sceneNormal, scene)
SH_SOFT_SHADOW(softShadow, scene)
SH_AO(sceneAO, scene)

// ================================
// Materials
// ================================

struct Material
{
    vec3  albedo;
    float roughness;
    float metallic;
};

Material getMaterial(int mat, vec3 p)
{
    if (mat == MAT_FLOOR)
    {
        float chk = mod(floor(p.x) + floor(p.z), 2.0);
        return Material(mix(vec3(0.1), vec3(0.8), chk), 0.5, 0.0);
    }
    if (mat == MAT_MIRROR) return Material(vec3(0.9),           0.08, 1.0);
    if (mat == MAT_RED)    return Material(vec3(0.8, 0.1, 0.1), 0.5,  0.0);
    if (mat == MAT_GOLD)   return Material(vec3(1.0, 0.7, 0.2), 0.3,  1.0);
    return Material(vec3(0.1, 0.3, 0.9), 0.5, 0.0);
}

vec3 shadeReflected(vec3 p, vec3 n, vec3 rd, int mat)
{
    float ndl = saturate(dot(n, SUN));
    return getMaterial(mat, p).albedo * (ndl * 0.8 + 0.2);
}

SH_REFLECTION(sceneReflect, scene, shadeReflected)

// ================================
// Sky and Tonemapping
// ================================

vec3 skyColor(vec3 dir)
{
    vec3  c = mix(SKY_HORIZON, SKY_TOP, pow(saturate(dir.y), 0.6));
    float s = saturate(dot(dir, SUN));
    return c + SUN_COLOR * pow(s, 400.0);
}

vec3 tonemap(vec3 c)
{
    const float EXPOSURE = 0.8;
    const float WHITE    = 1.2;

    const float A = 0.22 * EXPOSURE * EXPOSURE;
    const float B = 0.30 * EXPOSURE;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.01;
    const float F = 0.30;

    vec3  v = (c * (c * A + C * B) + D * E) / (c * (c * A + B) + D * F) - E / F;
    float w = (WHITE * (A * WHITE + C * B) + D * E) / (WHITE * (A * WHITE + B) + D * F) - E / F;

    return saturate(v / w);
}

// ================================
// Shading
// ================================

vec4 shade(Ray ray, Hit hit, float cone)
{
    vec3 sky = skyColor(ray.dir);
    if (!hit.hit) return vec4(tonemap(sky), 1.0);

    vec3 p = hit.pos;
    vec3 n = sceneNormal(p, 0.001);
    vec3 v = -ray.dir;

    int      mat = scene(p).mat;
    Material m   = getMaterial(mat, p);

    float NdotV = max(dot(n, v), 1e-4);
    vec3  so    = p + n * 0.01;

    float shadow  = softShadow(so, SUN, 0.02, 30.0, 64, 0.001, 12.0);
    float ao      = sceneAO(p, n, 5, 0.12, 0.95, 3.0);
    vec3  ambient = shAmbientHemisphere(n, vec3(0.0, 1.0, 0.0), AMBIENT_SKY, AMBIENT_GND);

    vec3 brdf = shBrdfGGX(n, v, SUN, m.albedo, m.roughness, m.metallic);
    vec3 col  = shDirect(brdf, SUN_COLOR * shadow, n, SUN);

    vec3 f0      = shF0(m.albedo, m.metallic);
    vec3 envBrdf = shEnvBrdfApprox(f0, m.roughness, NdotV);

    col += (1.0 - m.metallic) * m.albedo * (vec3(1.0) - envBrdf) * ambient * ao;

    vec3 env = ambient;
    if (m.roughness < 0.4)
    {
        vec3 r      = reflect(ray.dir, n);
        vec3 mirror = sceneReflect(so, r, 48, 30.0, 0.002, skyColor(r));
        env = mix(mirror, ambient, smoothstep(0.1, 0.4, m.roughness));
    }
    col += env * envBrdf * shSpecularOcclusion(NdotV, ao, m.roughness);

    float dist = length(p - ray.origin);
    col = shFogApply(col, SKY_HORIZON, shFogExp(dist, 0.024));

    return vec4(tonemap(col), 1.0);
}
`;
