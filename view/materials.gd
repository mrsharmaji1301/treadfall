extends RefCounted
## Materials. Sand, camouflage and tracks use the painted textures in
## assets/; smaller surfaces use generated noise. Materials are cached.

static var _cache: Dictionary = {}


## Loads a texture and gives it mipmaps, so it stays clean at a distance.
static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var result: Texture2D = null
	var source = load(path)
	if source is Texture2D:
		var img: Image = source.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			result = ImageTexture.create_from_image(img)
	_cache[path] = result
	return result


static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


static func noise_tex(seed_value: int, frequency: float, size: int, ramp: Gradient,
		as_normal: bool) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = 5.0
	elif ramp != null:
		t.color_ramp = ramp
	return t


static func _grime() -> NoiseTexture2D:
	if not _cache.has("grime"):
		_cache["grime"] = noise_tex(7, 0.02, 256,
			_ramp(Color(0.78, 0.76, 0.73), Color(1, 1, 1)), false)
	return _cache["grime"]


static func _bumps() -> NoiseTexture2D:
	if not _cache.has("bumps"):
		_cache["bumps"] = noise_tex(5, 0.08, 256, null, true)
	return _cache["bumps"]


## Plain surface with grime and fine bumps, mapped without UVs (triplanar).
static func surface(key: String, color: Color, roughness: float, metallic: float,
		tex_scale: float = 1.5) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _grime()
	m.normal_enabled = true
	m.normal_texture = _bumps()
	m.normal_scale = 0.4
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## A tank paint picture, with mud or rust streaks painted over it when
## `wear` asks for them. Mixed once and kept.
static func _skin_tex(look: String, wear: String) -> Texture2D:
	var path := "res://assets/tank/camo_albedo.png" if look == "camo" \
		else "res://assets/tank/tank_%s.jpg" % look
	var base := tex(path)
	if base == null or wear == "":
		return base
	var key := "skin_%s_%s" % [look, wear]
	if _cache.has(key):
		return _cache[key]
	var over := tex("res://assets/tank/tank_%s.png" % ("mud" if wear == "mud" else "rust_streaks"))
	if over == null:
		return base
	var img: Image = base.get_image()
	var top: Image = over.get_image()
	for i in [img, top]:
		if i.is_compressed():
			i.decompress()
		i.convert(Image.FORMAT_RGBA8)
		i.resize(512, 512, Image.INTERPOLATE_BILINEAR)
	img.blend_rect(top, Rect2i(0, 0, 512, 512), Vector2i.ZERO)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out


## Weathered camouflage paint. `tint` shifts it per tank type. `stage` 1..3
## adds battle damage: soot, bare metal, rust and dents that spread.
static func paint(tint: Color, stage: int = 0, skin: String = "", wear: String = "") -> StandardMaterial3D:
	var key := "paint_%s_%d_%s_%s" % [tint.to_html(false), stage, skin, wear]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	# The photo paint that suits the colour asked for: red for the enemy's
	# buildings, grey for dark tanks, desert camouflage for the rest.
	var look := "camo_desert"
	var wash := tint * 0.8
	var dim: float = maxf(tint.r, maxf(tint.g, tint.b))
	if skin != "":
		# A named paint job (enemy tanks): the tint only shades it.
		look = skin
		wash = tint * (0.8 if skin == "camo_desert" or skin == "camo" else 1.25)
	elif tint.r > tint.g * 1.5:
		look = "paint_red"
		wash = Color(1.6, 1.6, 1.6) * dim
	elif dim < 0.8 and tint.r - tint.b < 0.08:
		look = "paint_grey"
		wash = Color(2.0, 2.0, 2.0) * dim
	var camo := _skin_tex(look, wear)
	if camo == null:
		camo = tex("res://assets/tank/camo_albedo.png")
		wash = tint
	if camo != null:
		m.albedo_color = wash
		m.albedo_texture = camo
		m.normal_enabled = true
		m.normal_texture = tex("res://assets/tank/camo_normal.png")
		m.normal_scale = 0.6
	else:
		m.albedo_color = tint * Color(0.66, 0.55, 0.42)
	var mask: Texture2D = null
	if stage > 0:
		mask = tex("res://assets/tank/damage_mask_%d.png" % stage)
	if mask != null:
		m.detail_enabled = true
		m.detail_mask = mask
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
		m.detail_albedo = tex("res://assets/tank/damage_albedo.png")
		m.detail_normal = tex("res://assets/tank/damage_normal.png")
	m.roughness = 0.82
	m.metallic = 0.15
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


static func steel() -> StandardMaterial3D:
	return surface("steel", Color(0.2, 0.19, 0.18), 0.5, 0.75, 3.0)


static func concrete() -> StandardMaterial3D:
	var photo := built("concrete_bunker", 0.5)
	if photo != null:
		return photo
	return surface("concrete", Color(0.5, 0.48, 0.45), 0.95, 0.0, 0.8)


static func rubble() -> StandardMaterial3D:
	return surface("rubble", Color(0.4, 0.31, 0.23), 1.0, 0.0, 2.0)


## Desert rock from the photo textures, mapped in world space. `kind` is
## cliff, dark, layers, mossy or red.
static func rock(kind: String = "cliff") -> StandardMaterial3D:
	if _cache.has("rock_" + kind):
		return _cache["rock_" + kind]
	var albedo := tex("res://assets/nature/rock_%s.jpg" % kind)
	if albedo == null:
		return surface("rock", Color(0.44, 0.37, 0.3), 0.95, 0.0, 0.6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.9, 0.84)
	m.albedo_texture = albedo
	m.normal_enabled = true
	m.normal_texture = tex("res://assets/nature/rock_%s_normal.jpg" % kind)
	m.normal_scale = 1.2
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 3.0
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["rock_" + kind] = m
	return m


## A wall or building surface from the photo textures in assets/build,
## mapped in world space. Returns null if the texture is missing.
static func built(name: String, tex_scale: float, tint: Color = Color.WHITE,
		metallic: float = 0.0, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "built_%s_%s" % [name, tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var albedo := tex("res://assets/build/%s.jpg" % name)
	if albedo == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = albedo
	var bump := tex("res://assets/build/%s_normal.jpg" % name) \
		if ResourceLoader.exists("res://assets/build/%s_normal.jpg" % name) else null
	m.normal_enabled = true
	m.normal_texture = bump if bump != null else _bumps()
	m.normal_scale = 1.0 if bump != null else 0.4
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Ringed palm trunk.
static func bark() -> Material:
	if _cache.has("bark"):
		return _cache["bark"]
	var albedo := tex("res://assets/nature/palm_bark.jpg")
	if albedo == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.36, 0.29, 0.22)
		plain.roughness = 1.0
		plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["bark"] = plain
		return plain
	_hero_globals()
	var shader := Shader.new()
	shader.code = BARK_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("bark", albedo)
	m.set_shader_parameter("bumps", tex("res://assets/nature/palm_bark_normal.jpg"))
	_cache["bark"] = m
	return m


## The two world positions the cut-away shaders read: the player's tank
## and the camera. world_view.gd sets them every frame.
static func _hero_globals() -> void:
	if _cache.has("hero_globals"):
		return
	_cache["hero_globals"] = true
	for n in ["hero_pos", "eye_pos"]:
		RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_VEC3,
			Vector3(0.0, -999.0, 0.0))


const BARK_SHADER := """shader_type spatial;
render_mode cull_disabled;

uniform sampler2D bark : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D bumps : hint_normal, repeat_enable, filter_linear_mipmap;
global uniform vec3 hero_pos;
global uniform vec3 eye_pos;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(bark, UV).rgb * vec3(0.95, 0.86, 0.76);
	NORMAL_MAP = texture(bumps, UV).rgb;
	NORMAL_MAP_DEPTH = 1.3;
	ROUGHNESS = 1.0;
	// A trunk standing between the camera and the player's tank is cut
	// away, like the leaves. Not in the shadow pass (flat view).
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		vec3 d = hero_pos - eye_pos;
		float along = dot(world_pos - eye_pos, d) / dot(d, d);
		if (along < 0.9) {
			along = clamp(along, 0.0, 1.0);
			float off = length(world_pos - (eye_pos + d * along));
			float reach = 1.3 * mix(0.35, 1.0, along);
			float keep = smoothstep(reach * 0.6, reach, off);
			float grain = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
			if (keep < grain * 0.98 + 0.02) {
				discard;
			}
		}
	}
}
"""


const FOLIAGE_SHADER := """shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf : source_color, repeat_disable, filter_linear_mipmap;
// Where the player's tank is. Leaves between the camera and the tank are
// cut away, so the tank always shows under the palms.
global uniform vec3 hero_pos;
global uniform vec3 eye_pos;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(leaf, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	ROUGHNESS = 0.75;
	BACKLIGHT = vec3(0.14, 0.19, 0.05);
	// Shadows are drawn with a flat (orthographic) view: keep those whole,
	// so the cut-away does not punch a sunlit hole in the shade.
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		vec3 d = hero_pos - eye_pos;
		float along = clamp(dot(world_pos - eye_pos, d) / dot(d, d), 0.0, 1.0);
		float off = length(world_pos - (eye_pos + d * along));
		float reach = 1.7 * mix(0.35, 1.0, along);
		float keep = smoothstep(reach * 0.55, reach, off);
		float grain = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (keep < grain * 0.98 + 0.02) {
			discard;
		}
	}
}
"""


## Cut-out foliage card: palm fronds and grass. Lit from both sides, the
## sun glows through it a little, and it opens up over the player's tank.
static func foliage(path: String) -> Material:
	if _cache.has("foliage_" + path):
		return _cache["foliage_" + path]
	var albedo := tex(path)
	if albedo == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.3, 0.4, 0.18)
		plain.vertex_color_use_as_albedo = true
		plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["foliage_" + path] = plain
		return plain
	var shader: Shader = _cache.get("foliage_shader")
	if shader == null:
		_hero_globals()
		shader = Shader.new()
		shader.code = FOLIAGE_SHADER
		_cache["foliage_shader"] = shader
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("leaf", albedo)
	_cache["foliage_" + path] = m
	return m


const PLANT_SHADER := """shader_type spatial;
render_mode cull_disabled;

uniform sampler2D sheet : source_color, repeat_disable, filter_linear_mipmap;

void vertex() {
	// Each sheet holds 4 plants side by side; the instance picks one.
	UV.x = (UV.x + INSTANCE_CUSTOM.x) * 0.25;
}

void fragment() {
	vec4 t = texture(sheet, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.14, 0.18, 0.05);
}
"""


## Cut-out plants from a sheet of 4 (assets/nature/<name>.png).
static func plants(name: String) -> Material:
	if _cache.has("plants_" + name):
		return _cache["plants_" + name]
	var sheet := tex("res://assets/nature/%s.png" % name)
	if sheet == null:
		return foliage("res://assets/nature/grass_tuft.png")
	var shader: Shader = _cache.get("plant_shader")
	if shader == null:
		shader = Shader.new()
		shader.code = PLANT_SHADER
		_cache["plant_shader"] = shader
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("sheet", sheet)
	_cache["plants_" + name] = m
	return m


## Burnt-out wreck: the same paint, scorched dark, so the detail stays.
static func charred() -> StandardMaterial3D:
	if _cache.has("charred"):
		return _cache["charred"]
	var m: StandardMaterial3D = paint(Color(0.4, 0.34, 0.29), 2).duplicate()
	m.roughness = 1.0
	m.metallic = 0.0
	_cache["charred"] = m
	return m


const WATER_SHADER := """shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D waves : repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_map : repeat_enable, filter_linear_mipmap;
uniform sampler2D flow_map : repeat_enable, filter_linear_mipmap;
// River colours: clear green over the shallows, dark and murky in the
// channel. Kept low and unsaturated; the sun and sky add the brightness.
uniform vec3 shallow_color : source_color = vec3(0.15, 0.36, 0.33);
uniform vec3 deep_color : source_color = vec3(0.045, 0.2, 0.24);
uniform vec3 channel_color : source_color = vec3(0.02, 0.1, 0.15);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = COLOR.r;
	float chan = COLOR.g;
	vec2 uv = world_pos.xz;
	// Three sizes of ripple sliding over each other.
	vec2 a = texture(waves, uv * 0.31 + TIME * vec2(0.021, 0.013)).xy;
	vec2 b = texture(waves, uv * 0.73 - TIME * vec2(0.017, 0.029)).xy;
	vec2 c = texture(waves, uv * 1.9 + TIME * vec2(-0.03, 0.041)).xy;
	vec2 tilt = (a + b - 1.0) * 0.45 + (c - 0.5) * 0.35;
	vec3 wn = normalize(vec3(tilt.x, 1.0, tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// Foam: a broken white line where the water meets the bank.
	float patchy = texture(foam_map, uv * 0.35 + tilt * 0.06 + TIME * vec2(0.012, 0.004)).r;
	float lap = 0.5 + 0.5 * sin(TIME * 1.1 + uv.x * 2.3 + uv.y * 1.7);
	float edge = smoothstep(0.0, 0.035, depth) * (1.0 - smoothstep(0.05 + 0.05 * lap, 0.16 + 0.08 * lap, depth));
	float foam = edge * smoothstep(0.25, 0.6, patchy + 0.25 * lap);
	// Current lines drifting down the deep channel.
	float lines = texture(flow_map, uv * vec2(0.07, 0.19) + tilt * 0.03 - vec2(TIME * 0.045, 0.0)).r;
	foam = max(foam, smoothstep(0.55, 0.9, lines) * chan * 0.12);
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.08, 0.8, depth));
	col = mix(col, channel_color, smoothstep(0.0, 1.0, chan));
	// The surface reflects more of the sky the flatter you look along it.
	float graze = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, vec3(0.36, 0.43, 0.46), graze * 0.45);
	ALBEDO = mix(col, vec3(0.86, 0.88, 0.84), foam * 0.8);
	ROUGHNESS = mix(0.07, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// Clear over the shallows, so the stones on the bed show; the bed fades
	// from sight as it drops away.
	float body = mix(0.5, 0.92, smoothstep(0.0, 0.5, depth));
	body = mix(body, 0.97, smoothstep(0.0, 0.9, chan));
	ALPHA = smoothstep(0.0, 0.06, depth) * body;
	ALPHA = max(ALPHA, foam * 0.85);
}
"""


## Oasis water: two layers of ripples sliding over each other, sky and sun
## reflections, clear in the shallows and darker in the deep, foam at the shore.
static func water() -> ShaderMaterial:
	if _cache.has("water"):
		return _cache["water"]
	var shader := Shader.new()
	shader.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("waves", tex("res://assets/water/water_normal.png"))
	m.set_shader_parameter("foam_map", tex("res://assets/water/water_foam.jpg"))
	m.set_shader_parameter("flow_map", tex("res://assets/water/water_flow.jpg"))
	_cache["water"] = m
	return m


## Soft ring texture for ripples spreading over the water.
static func ring_texture() -> ImageTexture:
	if _cache.has("ring"):
		return _cache["ring"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d: float = Vector2(x - 31.5, y - 31.5).length() / 32.0
			var band: float = smoothstep(0.62, 0.8, d) * (1.0 - smoothstep(0.84, 0.98, d))
			var inner: float = 0.35 * smoothstep(0.3, 0.42, d) * (1.0 - smoothstep(0.46, 0.56, d))
			img.set_pixel(x, y, Color(1, 1, 1, band + inner))
	var t := ImageTexture.create_from_image(img)
	_cache["ring"] = t
	return t


## One ripple ring. Each ring fades its own copy.
static func ripple() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.97, 1.0, 0.5)
	m.albedo_texture = ring_texture()
	return m


## Mud-brick wall: real courses of bricks with mortar lines.
static func mud_brick() -> StandardMaterial3D:
	if _cache.has("mud_brick"):
		return _cache["mud_brick"]
	var photo := built("mud_brick", 0.7, Color(0.95, 0.88, 0.8))
	if photo != null:
		_cache["mud_brick"] = photo
		return photo
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var img := Image.create(128, 64, false, Image.FORMAT_RGB8)
	for row in 4:
		var shift: int = 16 if row % 2 == 1 else 0
		var tones: Array = []
		for i in 5:
			tones.append(rng.randf_range(0.78, 1.0))
		for y in 16:
			for x in 128:
				var bx: int = (x + shift) % 128
				var tone: float = tones[bx / 32]
				if y < 2 or bx % 32 < 2:
					tone = 0.55
				img.set_pixel(x, row * 16 + y, Color(tone, tone, tone))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.39, 0.28)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.normal_enabled = true
	m.normal_texture = _bumps()
	m.normal_scale = 0.6
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.43, 1.43, 1.43)
	_cache["mud_brick"] = m
	return m


const GROUND_SHADER := """shader_type spatial;

uniform sampler2D t_sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_dune : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_road : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_scrub : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_far : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_grove : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_bank : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_bed : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_deep : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_lush : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_sand : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D caustics : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
varying vec4 wa;
varying vec4 wb;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wa = CUSTOM0;
	wb = CUSTOM1;
}

// The texture's own light and dark decide where one ground gives way to
// the next, so borders are ragged instead of a smooth smear.
float edge(float w, float rough) {
	return smoothstep(0.35, 0.65, w + (rough - 0.5) * 0.5 * (1.0 - abs(2.0 * w - 1.0)));
}

void fragment() {
	vec2 uv = wpos.xz;
	vec3 warm = vec3(0.93, 0.84, 0.7);
	vec3 sand = texture(t_sand, uv * 0.21).rgb * warm;
	float rough = dot(texture(t_scrub, uv * 0.13).rgb, vec3(0.6, 0.9, 0.5));
	vec3 col = mix(sand, texture(t_dune, uv * 0.12).rgb * warm, COLOR.a);
	float k_scrub = edge(wa.g, rough);
	col = mix(col, texture(t_scrub, uv * 0.23).rgb * 1.25, k_scrub * 0.85);
	float k_far = edge(wa.b, rough);
	col = mix(col, texture(t_far, uv * 0.2).rgb * vec3(0.8, 0.84, 0.86), k_far * 0.85);
	float k_lush = edge(wb.a, rough);
	col = mix(col, texture(t_lush, uv * 0.27).rgb, k_lush);
	float k_grove = edge(wa.a, rough);
	col = mix(col, texture(t_grove, uv * 0.3).rgb * 1.5, k_grove * 0.9);
	float k_road = smoothstep(0.15, 0.85, wa.r + (rough - 0.5) * 0.3);
	col = mix(col, texture(t_road, uv * 0.26).rgb * 1.1, k_road);
	float k_bank = edge(wb.r, rough);
	col = mix(col, texture(t_bank, uv * 0.3).rgb * 1.1, k_bank);
	col = mix(col, texture(t_bed, uv * 0.33).rgb, wb.g);
	col = mix(col, texture(t_deep, uv * 0.25).rgb, wb.b);
	// Light dancing on the river bed.
	float c1 = texture(caustics, uv * 0.35 + TIME * vec2(0.03, 0.017)).r;
	float c2 = texture(caustics, uv * 0.27 - TIME * vec2(0.021, 0.026)).r;
	col += vec3(0.9, 1.0, 0.85) * min(c1, c2) * 1.4 * wb.g * (1.0 - 0.6 * wb.b);
	// Toned down a little and warmed: sun-baked sand, not white paper.
	ALBEDO = col * COLOR.rgb * vec3(0.84, 0.79, 0.72);
	NORMAL_MAP = texture(n_sand, uv * 0.21).rgb;
	NORMAL_MAP_DEPTH = 0.9 * (1.0 - 0.7 * max(max(k_grove, k_lush), max(max(k_far, k_road), wb.g)));
	ROUGHNESS = mix(0.95, 0.55, max(k_bank, wb.g));
	SPECULAR = 0.25;
}
"""


## The ground: one shader that lays sand, dune, road, scrub, badland, grove
## floor, river bank and river bed where the terrain says each belongs.
## Falls back to plain sand if the textures are missing.
static func sand() -> Material:
	if _cache.has("sand"):
		return _cache["sand"]
	var base := "res://assets/terrain/ground_"
	if tex(base + "sand.jpg") == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.71, 0.6, 0.44)
		plain.vertex_color_use_as_albedo = true
		plain.roughness = 0.95
		_cache["sand"] = plain
		return plain
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	var layers := {"t_sand": "sand", "t_dune": "dune", "t_road": "road_edge", "t_scrub": "scrub",
		"t_far": "badland_cracked", "t_grove": "jungle", "t_bank": "bank", "t_bed": "riverbed",
		"t_deep": "riverbed_deep", "t_lush": "grass", "n_sand": "sand_normal"}
	for key in layers:
		m.set_shader_parameter(key, tex(base + layers[key] + ".jpg"))
	m.set_shader_parameter("caustics", tex("res://assets/water/water_caustics.jpg"))
	_cache["sand"] = m
	return m


## Chevron-tread track. One material per tank, because each tank scrolls
## its own tracks.
static func track() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var albedo := tex("res://assets/tank/track_albedo.png")
	if albedo != null:
		m.albedo_texture = albedo
		m.normal_enabled = true
		m.normal_texture = tex("res://assets/tank/track_normal.png")
	else:
		m.albedo_color = Color(0.15, 0.14, 0.13)
	m.roughness = 0.8
	m.metallic = 0.4
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(6, 6, 6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Track ruts pressed into the sand.
static func track_mark() -> StandardMaterial3D:
	if _cache.has("track_mark"):
		return _cache["track_mark"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.62)
	m.albedo_texture = tex("res://assets/terrain/track_rut.png")
	# Each print carries its own fading alpha in the instance colour.
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	_cache["track_mark"] = m
	return m


static func glow(key: String, color: Color, energy: float) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * energy
	_cache[key] = m
	return m


## A cut-out picture card that is not a sheet: wire, a cut log end.
static func cutout(path: String, double_sided: bool = true) -> StandardMaterial3D:
	if _cache.has("cutout_" + path):
		return _cache["cutout_" + path]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(path)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.roughness = 0.8
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["cutout_" + path] = m
	return m
