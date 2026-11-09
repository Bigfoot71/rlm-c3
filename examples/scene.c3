import raylib6;
import std::math;
import rlm;

fn int main()
{
	rl::init_window(800, 450, "UwU");
	defer rl::close_window();
	rl::set_target_fps(60);

	rlm::init(800, 450);
	defer rlm::quit();

	RLMShader shader = rlm::load_shader_from_memory(SHADER)!!;
	defer shader.free();

	RLCamera3D camera = {
		.position   = { 0.0f, 1.5f, 4.0f },
		.target     = { 0.0f, 0.0f, 0.0f },
		.up         = { 0.0f, 1.0f, 0.0f },
		.fovy       = 60.0f,
		.projection = RLCameraProjection.PERSPECTIVE,
	};

	while (!rl::window_should_close())
	{
		float t = (float)rl::get_time();

		camera.position.x = 4.0f * math::cos(t * 0.5f);
		camera.position.z = 4.0f * math::sin(t * 0.5f);

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
Sd scene(vec3 p)
{
    return sdSphere(p, 1.0, 1);
}

vec3 sceneNormal(vec3 p)
{
    vec2 e = vec2(0.001, 0.0);

    return normalize(vec3(
        scene(p + e.xyy).d - scene(p - e.xyy).d,
        scene(p + e.yxy).d - scene(p - e.yxy).d,
        scene(p + e.yyx).d - scene(p - e.yyx).d
    ));
}

vec4 shade(Ray ray, Hit hit, float cone)
{
    vec3 sky = mix(vec3(0.75, 0.85, 1.0), vec3(0.15, 0.30, 0.60), clamp(ray.dir.y * 0.5 + 0.5, 0.0, 1.0));

    if (!hit.hit)
    {
        return vec4(sky, 1.0);
    }

    vec3  n    = sceneNormal(hit.pos);
    vec3  l    = normalize(vec3(0.6, 0.8, 0.4));
    float diff = max(dot(n, l), 0.0);
    float amb  = 0.15 + 0.15 * n.y;

    vec3 col = vec3(0.9, 0.3, 0.4) * (diff + amb);

    return vec4(col, 1.0);
}
`;
