module rlm;

import std::collections::map;
import std::math;
import raylib6;

// ================================
// Public: Shader Definitions
// ================================

struct RLMUniform
{
	typeid kind;    // Type of the stored value (RLTexture for samplers)
	sz     offset;  // offset of the value inside RLMShader.data
	sz     size;    // size in bytes of the stored value
	int    loc;     // GL location; -1 if unknown (review that)
	int    gl_type; // RLShaderUniformDataType ordinal (or internal matrix code)
	int    slot;    // texture unit (samplers only)
	bool   valid;   // true once a value has been stored (and uploaded)
}

struct RLMSampler
{
	int slot;
	sz  offset;     // where the texture id lives in RLMShader.data
}

struct RLMShader
{
	uint  id;
	char* data;
	sz    data_len;
	sz    data_cap;
	int   sampler_count;

	RLMSampler[MAX_SAMPLERS] samplers;
	HashMap{String, RLMUniform} uniforms;
}

excuse
{
	INVALID_UNIFORM,
	MISSING_SCENE,
	MISSING_SHADE,
	UNSUPPORTED_GL,
	COMPILE_FAILED,
	SHADER_FILE_NOT_FOUND,
}

// ================================
// Public: Shader Functions
// ================================

fn RLMShader? load_shader(String file_path) => @pool()
{
	ZString code = rl::load_file_text(file_path.zstr_tcopy());
	if ((char*)code == null)
	{
		rl::trace_log(RLTraceLogLevel.ERROR, "RLM: cannot read shader file '%s'", file_path);
		return SHADER_FILE_NOT_FOUND~;
	}
	defer rl::unload_file_text(code);

	return load_shader_from_memory(code.str_view());
}

fn RLMShader? load_shader_from_memory(String code)
{
	RLMShader shader;
	shader.init(code)!;
	return shader;
}

// ================================
// Public: Shader Methods
// ================================

fn RLMShader*? RLMShader.init(&self, String code) => @pool()
{
	*self = {};

	if (!has_function(code, "Sd", "scene"))
	{
		rl::trace_log(RLTraceLogLevel.ERROR, "RLM: user shader must define 'Sd scene(vec3 p)'");
		return MISSING_SCENE~;
	}
	if (!has_function(code, "vec4", "shade"))
	{
		rl::trace_log(RLTraceLogLevel.ERROR, "RLM: user shader must define 'vec4 shade(...)'");
		return MISSING_SHADE~;
	}

	String main_vert = MAIN_VERT;
	String main_frag = MAIN_FRAG;

	if (!main_frag.contains(USER_MARKER))
	{
		rl::trace_log(RLTraceLogLevel.ERROR, "RLM: built-in main.frag has no '%s' marker", USER_MARKER);
		return COMPILE_FAILED~;
	}

	Dialect g = get_dialect()!;

	String user = expand_includes(code);

	DString vs = dstring::temp_with_capacity(main_vert.len + 256);
	vs.append(g.header_vs);
	vs.append(apply_tags(main_vert, g.attr, g.vary_out, g.frag));

	String fs_body = apply_tags(main_frag, g.attr, g.vary_in, g.frag).treplace(USER_MARKER, user);
	DString fs = dstring::temp_with_capacity(fs_body.len + 256);
	fs.append(g.header_fs);
	fs.append(fs_body);

	self.id = rl::gl_load_shader_program(vs.zstr_view(), fs.zstr_view());
	if (self.id == 0)
	{
		rl::trace_log(RLTraceLogLevel.ERROR, "RLM: shader compilation failed");
		return COMPILE_FAILED~;
	}

	self.uniforms.init(mem);

	return self;
}

fn void RLMShader.free(&self)
{
	if (self.id != 0) rl::gl_unload_shader_program(self.id);
	alloc::free(mem, self.data);
	self.uniforms.free();
	*self = {};
}

macro void RLMShader.set_value(&self, String name, value)
{
	$switch $Typeof(value):
	$case RLTexture:
		self.set_value_texture(name, value.id);
	$case double:
		float f = (float)value;
		self.set_value_raw(name, float::typeid, &f, float::size);
	$default:
		self.set_value_raw(name, $Typeof(value)::typeid, &value, $Typeof(value)::size);
	$endswitch
}

fn void RLMShader.set_value_raw(&self, String name, typeid kind, void* src, sz size)
{
	RLMUniform* u = get_uniform(self, name);
	if (u.loc < 0) return;

	if (u.valid)
	{
		if (u.kind != kind)
		{
			rl::trace_log(RLTraceLogLevel.ERROR, "RLM: uniform '%s' changed type after its first set_value()", name);
			return;
		}
		if (mem::equals(self.data + u.offset, (char*)src, size)) return;
	}
	else
	{
		int gl_type = uniform_type_of(kind);
		if (gl_type < 0)
		{
			rl::trace_log(RLTraceLogLevel.ERROR, "RLM: unsupported type for uniform '%s'", name);
			return;
		}
		u.kind    = kind;
		u.size    = size;
		u.gl_type = gl_type;
		u.offset  = reserve_buffer(self, size);
		u.valid   = true;
	}

	mem::copy(self.data + u.offset, src, size);

	void* ptr = self.data + u.offset;
	rl::gl_enable_shader(self.id);
	if (u.gl_type == TYPE_MATRIX)
	{
		rl::gl_set_uniform_matrix(u.loc, *(Mat4*)ptr);
	}
	else
	{
		rl::gl_set_uniform(u.loc, ptr, u.gl_type, 1);
	}
}

fn void RLMShader.set_value_texture(&self, String name, uint tex_id)
{
	RLMUniform* u = get_uniform(self, name);
	if (u.loc < 0) return;

	bool changed = false;
	if (!u.valid)
	{
		if (self.sampler_count >= MAX_SAMPLERS)
		{
			rl::trace_log(RLTraceLogLevel.ERROR, "RLM: no texture unit left for sampler '%s'", name);
			return;
		}
		int slot  = FIRST_TEXTURE_SLOT + self.sampler_count;
		u.kind    = RLTexture::typeid;
		u.size    = uint::size;
		u.gl_type = RLShaderUniformDataType.SAMPLER2D.ordinal;
		u.slot    = slot;
		u.offset  = reserve_buffer(self, uint::size);
		u.valid   = true;
		changed   = true;

		self.samplers[self.sampler_count] = { .slot = slot, .offset = u.offset };
		self.sampler_count++;

		rl::gl_enable_shader(self.id);
		rl::gl_set_uniform(u.loc, &slot, RLShaderUniformDataType.INT.ordinal, 1);
	}

	uint* stored = (uint*)(self.data + u.offset);
	if (!changed && *stored == tex_id) return;
	*stored = tex_id;
}

// ================================
// Private: Shader Functions
// ================================

macro @use_shader(#shader; @body) @private
{
	rl::gl_draw_render_batch_active();

	for (int i = 0; i < #shader.sampler_count; i++)
	{
		RLMSampler* s = &#shader.samplers[i];
		uint tex_id = *(uint*)(#shader.data + s.offset);
		rl::gl_active_texture_slot(s.slot);
		rl::gl_enable_texture(tex_id);
	}
	rl::gl_active_texture_slot(0);

	rl::gl_enable_shader(#shader.id);
	defer rl::gl_disable_shader();

	@body();
}

// ================================
// Local: Shader Constants
// ================================

const int FIRST_TEXTURE_SLOT  @local = 5;
const int MAX_SAMPLERS        @local = 11; // units 5..15
const sz  INITIAL_BUFFER_SIZE @local = 256;
const int TYPE_MATRIX         @local = 100;

// ================================
// Local: Uniform Buffer
// ================================

fn sz reserve_buffer(RLMShader* shader, sz size)
{
	sz offset = (shader.data_len + 15) & ~(sz)15;
	sz needed = offset + size;

	if (needed > shader.data_cap)
	{
		sz cap = shader.data_cap != 0 ? shader.data_cap : INITIAL_BUFFER_SIZE;
		while (cap < needed) cap *= 2;

		if (shader.data_cap == 0)
		{
			shader.data = alloc::malloc(mem, cap);
		}
		else
		{
			shader.data = alloc::realloc(mem, shader.data, cap);
		}
		shader.data_cap = cap;
	}

	shader.data_len = needed;

	return offset;
}

fn int uniform_type_of(typeid kind) @local
{
	switch
	{
		case kind == float::typeid:      return RLShaderUniformDataType.FLOAT.ordinal;
		case kind == float[<2>]::typeid: return RLShaderUniformDataType.VEC2.ordinal;
		case kind == float[<3>]::typeid: return RLShaderUniformDataType.VEC3.ordinal;
		case kind == float[<4>]::typeid: return RLShaderUniformDataType.VEC4.ordinal;
		case kind == int::typeid:        return RLShaderUniformDataType.INT.ordinal;
		case kind == int[<2>]::typeid:   return RLShaderUniformDataType.IVEC2.ordinal;
		case kind == int[<3>]::typeid:   return RLShaderUniformDataType.IVEC3.ordinal;
		case kind == int[<4>]::typeid:   return RLShaderUniformDataType.IVEC4.ordinal;
		case kind == uint::typeid:       return RLShaderUniformDataType.UINT.ordinal;
		case kind == uint[<2>]::typeid:  return RLShaderUniformDataType.UIVEC2.ordinal;
		case kind == uint[<3>]::typeid:  return RLShaderUniformDataType.UIVEC3.ordinal;
		case kind == uint[<4>]::typeid:  return RLShaderUniformDataType.UIVEC4.ordinal;
		case kind == Mat4::typeid:       return TYPE_MATRIX;
	}
	return -1;
}

fn RLMUniform* get_uniform(RLMShader* shader, String name) @local
{
	RLMUniform*? found = shader.uniforms.get_ref(name);
	if (try found) return found;

	RLMUniform u = { .loc = -1 };
	@pool()
	{
		u.loc = rl::gl_get_location_uniform(shader.id, name.zstr_tcopy());
	};
	if (u.loc < 0)
	{
		rl::trace_log(RLTraceLogLevel.WARNING, "RLM: uniform '%s' not found (absent or optimized out)", name);
	}

	shader.uniforms.set(name, u);
	return shader.uniforms.get_ref(name)!!;
}

// ================================
// Local: Source Generation
// ================================

struct Dialect @local
{
	String header_vs; // #version + stage defines (vertex)
	String header_fs; // #version + precision + stage defines (fragment)
	String attr;      // <ATTR>
	String vary_out;  // <VARY> in the vertex stage
	String vary_in;   // <VARY> in the fragment stage
	String frag;      // <FRAG>
}

fn Dialect? get_dialect() @local
{
	RLGlVersion ver = (RLGlVersion)rl::gl_get_version();
	Dialect d;

	if (ver == RLGlVersion.OPENGL_33 || ver == RLGlVersion.OPENGL_43)
	{
		d.header_vs = "#version 330\n#define POS vertexPosition\n#define TEXTURE texture\n";
		d.header_fs = "#version 330\n#define TEXTURE texture\n";
		d.attr = "in"; d.vary_out = "out"; d.vary_in = "in"; d.frag = "out";
	}
	else if (ver == RLGlVersion.OPENGL_ES_30)
	{
		d.header_vs = "#version 300 es\n#define POS vertexPosition\n#define TEXTURE texture\n";
		d.header_fs = "#version 300 es\nprecision highp float;\nprecision highp int;\n#define TEXTURE texture\n";
		d.attr = "in"; d.vary_out = "out"; d.vary_in = "in"; d.frag = "out";
	}
	else if (ver == RLGlVersion.OPENGL_ES_20)
	{
		d.header_vs = "#version 100\n#define POS vertexPosition\n#define TEXTURE texture2D\n";
		d.header_fs = "#version 100\n#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#else\nprecision mediump float;\n#endif\n#define COLOR gl_FragColor\n#define TEXTURE texture2D\n";
		d.attr = "attribute"; d.vary_out = "varying"; d.vary_in = "varying"; d.frag = "//";
	}
	else if (ver == RLGlVersion.OPENGL_21)
	{
		d.header_vs = "#version 120\n#define POS vertexPosition\n#define TEXTURE texture2D\n";
		d.header_fs = "#version 120\n#define COLOR gl_FragColor\n#define TEXTURE texture2D\n";
		d.attr = "attribute"; d.vary_out = "varying"; d.vary_in = "varying"; d.frag = "//";
	}
	else
	{
		rl::trace_log(RLTraceLogLevel.ERROR, "RLM: shaders are not available on this OpenGL version");
		return UNSUPPORTED_GL~;
	}
	return d;
}

fn String apply_tags(String src, String attr, String vary, String frag) @local
{
	return src
		.treplace("<ATTR>", attr)
		.treplace("<VARY>", vary)
		.treplace("<FRAG>", frag);
}

fn String expand_includes(String code) @local
{
	DString out = dstring::temp_with_capacity(code.len + 1024);
	Splitter lines = code.tokenize_all("\n");

	while (try line = lines.next())
	{
		String t = line.trim();
		if (!t.starts_with("#include"))
		{
			out.append(line);
			out.append_char('\n');
			continue;
		}

		String name = include_name(t);
		if (name == "math.glsl")
		{
			out.append(INC_MATH_GLSL);
		}
		else if (name == "shading.glsl")
		{
			out.append(INC_SHADING_GLSL);
		}
		else
		{
			rl::trace_log(RLTraceLogLevel.WARNING, "RLM: unknown #include \"%s\" ignored", name);
		}
		out.append_char('\n');
	}
	return out.str_view();
}

fn String include_name(String directive) @local
{
	String rest = directive.strip_prefix("#include").trim();
	if (rest.len < 2) return "";
	if (rest[0] != '<' && rest[0] != '"') return "";

	char close = rest[0] == '<' ? '>' : '"';
	sz? end = rest[1..].index_of_char(close);
	if (catch end) return "";

	String name = rest[1:end];
	sz? slash = name.rindex_of_char('/');
	if (try slash) name = name[slash + 1..];
	return name;
}

// ================================
// Local: User Code Validation
// ================================

fn bool is_space(char c) @local
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

fn bool is_ident(char c) @local
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

fn String strip_comments(String s) @local
{
	DString d = dstring::temp_with_capacity(s.len);
	sz i = 0;
	while (i < s.len)
	{
		if (s[i] == '/' && i + 1 < s.len && s[i + 1] == '/')
		{
			while (i < s.len && s[i] != '\n') i++;
		}
		else if (s[i] == '/' && i + 1 < s.len && s[i + 1] == '*')
		{
			i += 2;
			while (i + 1 < s.len && !(s[i] == '*' && s[i + 1] == '/')) i++;
			i += 2;
			d.append_char(' ');
		}
		else
		{
			d.append_char(s[i]);
			i++;
		}
	}
	return d.str_view();
}

fn bool has_function(String code, String ret_type, String name) @local => @pool()
{
	String src = strip_comments(code);
	sz from = 0;

	while (from < src.len)
	{
		sz? found = src[from..].index_of(name);
		if (catch found) return false;

		sz pos = from + found;
		from = pos + name.len;

		// whole word
		if (pos > 0 && is_ident(src[pos - 1])) continue;
		if (pos + name.len < src.len && is_ident(src[pos + name.len])) continue;

		// followed by '('
		sz after = pos + name.len;
		while (after < src.len && is_space(src[after])) after++;
		if (after >= src.len || src[after] != '(') continue;

		// preceded by the return type
		sz before = pos;
		while (before > 0 && is_space(src[before - 1])) before--;
		if (before < ret_type.len) continue;
		if (src[before - ret_type.len : ret_type.len] != ret_type) continue;
		if (before > ret_type.len && is_ident(src[before - ret_type.len - 1])) continue;

		return true;
	}
	return false;
}

// ================================
// Local: Buil-In Shaders
// ================================

const INC_SHADING_GLSL @local = $embed("./glsl/include/shading.glsl");
const INC_MATH_GLSL    @local = $embed("./glsl/include/math.glsl");

const MAIN_VERT @local = $embed("./glsl/main.vert");
const MAIN_FRAG @local = $embed("./glsl/main.frag");

const String USER_MARKER @local = "//@USER_CODE";
