module rlm;

import std::math;
import raylib6;

// ================================
// Public: RLM Functions
// ================================

fn void init(int w, int h)
{
	const TILE = BEAM_TILE_SIZE;

	ctx.rt_beam = rl::load_render_texture((w + TILE - 1) / TILE, (h + TILE - 1) / TILE);
	ctx.rt      = rl::load_render_texture(w, h);

	ctx.vao = rl::gl_load_vertex_array();
	ctx.vbo = rl::gl_load_vertex_buffer(TRIANGLE.ptr, (int)(TRIANGLE.len * RLVector2::size), false);

	rl::gl_enable_vertex_array(ctx.vao);
	defer rl::gl_disable_vertex_array();
	setup_attributes();
}

fn void quit()
{
	rl::unload_render_texture(ctx.rt_beam);
	rl::unload_render_texture(ctx.rt);

	rl::gl_unload_vertex_buffer(ctx.vbo);
	rl::gl_unload_vertex_array(ctx.vao);

	ctx = {};
}

fn RLTexture render(RLMShader* shader, RLCamera3D camera, RLRectangle viewport = {}, float aspect = 0.0f, float far = 100.0f) => @draw_state(shader)
{
	viewport = resolve_viewport(viewport);

	if (aspect <= 0.0f)
	{
		aspect = viewport.width / viewport.height;
	}

	int vw = (int)viewport.width;
	int vh = (int)viewport.height;

	RLRectangle beam_vp = tile_viewport(viewport);

	CameraBasis cam = camera_basis(camera, aspect);

	float cone_x    = aspect * cam.tan_half / (float)vw;
	float cone_y    = cam.tan_half / (float)vh;
	float cone      = math::max(cone_x, cone_y);
	float beam_cone = (float)BEAM_TILE_SIZE * math::sqrt(cone_x * cone_x + cone_y * cone_y) + cone;

	shader.set_value("RES",           (Vec2){ (float)vw, (float)vh });
	shader.set_value("BEAM_RES",      (Vec2){ beam_vp.width, beam_vp.height });
	shader.set_value("BEAM_TEX_SIZE", (Vec2){ (float)ctx.rt_beam.texture.width, (float)ctx.rt_beam.texture.height });
	shader.set_value("BEAM_TILE",     (float)BEAM_TILE_SIZE);

	shader.set_value("CAM_POS",   cam.pos);
	shader.set_value("CAM_FWD",   cam.fwd);
	shader.set_value("CAM_RIGHT", cam.right * (aspect * cam.tan_half));
	shader.set_value("CAM_UP",    cam.up    * cam.tan_half);
	shader.set_value("CAM_FAR",   far);

	shader.set_value("CONE",      cone);
	shader.set_value("BEAM_CONE", beam_cone);
	shader.set_value("BEAM_TEX",  1);

	@texture_mode(ctx.rt_beam, beam_vp)
	{
		shader.set_value("CURRENT_PASS", 0);
		rl::gl_draw_vertex_array(0, 3);
	};

	@texture_mode(ctx.rt, { viewport.x, viewport.y, vw, vh })
	{
		rl::gl_active_texture_slot(1);
		rl::gl_enable_texture(ctx.rt_beam.texture.id);
		shader.set_value("CURRENT_PASS", 1);

		rl::gl_draw_vertex_array(0, 3);

		rl::gl_active_texture_slot(1);
		rl::gl_disable_texture();
		rl::gl_active_texture_slot(0);
	};

	return ctx.rt.texture;
}

fn void present(RLMShader* shader, RLCamera3D camera, RLRectangle viewport = {}, float far = 100.0f)
{
	float sw = (float)rl::get_screen_width();
	float sh = (float)rl::get_screen_height();

	if (viewport.width <= 0.0f && viewport.height <= 0.0f)
	{
		viewport = present_viewport(sw, sh);
	}

	viewport = resolve_viewport(viewport);

	RLTexture texture = render(shader, camera, viewport, sw / sh, far);

	float tex_w = (float)texture.width;
	float tex_h = (float)texture.height;

	float tx = viewport.x      / tex_w;
	float ty = viewport.y      / tex_h;
	float tw = viewport.width  / tex_w;
	float th = viewport.height / tex_h;

	rl::gl_set_texture(texture.id);
	rl::gl_begin(rl::RL_QUADS);
	{
		rl::gl_color4ub(255, 255, 255, 255);

		rl::gl_tex_coord2f(tx, ty + th);
		rl::gl_vertex2f(0, 0);

		rl::gl_tex_coord2f(tx, ty);
		rl::gl_vertex2f(0, sh);

		rl::gl_tex_coord2f(tx + tw, ty);
		rl::gl_vertex2f(sw, sh);

		rl::gl_tex_coord2f(tx + tw, ty + th);
		rl::gl_vertex2f(sw, 0);
	}
	rl::gl_end();
	rl::gl_set_texture(0);
}

// ================================
// Local: RLM Constants
// ================================

const int BEAM_TILE_SIZE @local = 16;

const int GL_FLOAT @local = 0x1406;

const RLVector2[] TRIANGLE @local =
{
	{ 0.0f, 0.0f },
	{ 2.0f, 0.0f },
	{ 0.0f, 2.0f },
};

// ================================
// Local: RLM Definitions
// ================================

struct CameraBasis @local
{
	Vec3  pos;
	Vec3  fwd;
	Vec3  right;
	Vec3  up;
	float tan_half;
}

// ================================
// Local: RLM Functions
// ================================

fn void setup_attributes() @local
{
	rl::gl_enable_vertex_buffer(ctx.vbo);
	rl::gl_set_vertex_attribute(0, 2, GL_FLOAT, false, 0, 0);
	rl::gl_enable_vertex_attribute(0);
}

macro @draw_state(#shader; @body) @local => @use_shader(#shader)
{
	rl::gl_disable_color_blend();
	rl::gl_disable_backface_culling();

	if (!rl::gl_enable_vertex_array(ctx.vao))
	{
		setup_attributes();
	}

	defer
	{
		rl::gl_enable_backface_culling();
		rl::gl_enable_color_blend();

		rl::gl_disable_vertex_array();
		rl::gl_disable_vertex_buffer();
	}

	@body();
}

macro @texture_mode(RLRenderTexture rt, RLRectangle vp; @body) @local
{
    rl::gl_enable_framebuffer(rt.id);
	defer rl::gl_disable_framebuffer();
    rl::gl_viewport((int)vp.x, (int)vp.y, (int)vp.width, (int)vp.height);
	@body();
}

fn CameraBasis camera_basis(RLCamera3D camera, float aspect) @local
{
	assert((int)camera.projection == 0, "rlm: only perspective projection is supported");

	Vec3 pos  = camera.position;
	Vec3 dir  = camera.target - pos;
	Vec3 hint = camera.up;

	Vec3 fwd   = dir.normalize();
	Vec3 right = fwd.cross(hint).normalize();
	Vec3 up    = right.cross(fwd);

	return {
		.pos      = pos,
		.fwd      = fwd,
		.right    = right,
		.up       = up,
		.tan_half = math::tan(camera.fovy * 0.5f * (float)math::PI / 180.0f),
	};
}

fn RLRectangle resolve_viewport(RLRectangle viewport) @local
{
	float rw = (float)ctx.rt.texture.width;
	float rh = (float)ctx.rt.texture.height;

	viewport.x = math::clamp(math::floor(viewport.x), 0.0f, rw - 1.0f);
	viewport.y = math::clamp(math::floor(viewport.y), 0.0f, rh - 1.0f);

	viewport.width  = viewport.width  <= 0.0f ? rw - viewport.x : math::min(math::floor(viewport.width),  rw - viewport.x);
	viewport.height = viewport.height <= 0.0f ? rh - viewport.y : math::min(math::floor(viewport.height), rh - viewport.y);

	return viewport;
}

fn RLRectangle present_viewport(float sw, float sh) @local
{
	float rw = (float)ctx.rt.texture.width;
	float rh = (float)ctx.rt.texture.height;

	float s = math::min(1.0f, math::min(rw / sw, rh / sh));

	return {
		.x      = 0.0f,
		.y      = 0.0f,
		.width  = math::max(1.0f, math::floor(sw * s)),
		.height = math::max(1.0f, math::floor(sh * s)),
	};
}

fn RLRectangle tile_viewport(RLRectangle viewport) @local
{
	const TILE = BEAM_TILE_SIZE;

	return {
		.x      = 0.0f,
		.y      = 0.0f,
		.width  = (float)(((int)viewport.width  + TILE - 1) / TILE),
		.height = (float)(((int)viewport.height + TILE - 1) / TILE),
	};
}

// ================================
// Local: RLM Context
// ================================

struct Context @local
{
	RLRenderTexture rt_beam;
	RLRenderTexture rt;

	uint vao;
	uint vbo;
}

Context ctx @local;
