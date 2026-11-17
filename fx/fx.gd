extends RefCounted
## Particle effects in the 3D view: gun fire, impacts, explosions, dust.
## Fire and sparks use additive (glowing) particles, smoke and dust use soft
## billowing puffs. Positions come in 2D game units (48 px = 1 cell).

const Sfx := preload("res://fx/sfx.gd")

const S := 1.0 / 48.0

static var _quads: Dictionary = {}
static var _puff: ImageTexture
static var _chunk: BoxMesh


## Soft, lumpy puff: a round falloff broken up by noise.
static func puff_texture() -> ImageTexture:
	if _puff != null:
		return _puff
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.06
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d: float = Vector2(x - 31.5, y - 31.5).length() / 32.0
			var fall: float = clampf(1.0 - d, 0.0, 1.0)
			var lump: float = 0.65 + 0.35 * noise.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(fall * fall * lump * 1.6, 0.0, 1.0)))
	_puff = ImageTexture.create_from_image(img)
	return _puff


## Particle card. `look` picks the picture: "puff" (soft blob), or a sheet
## of four from assets/fx: "smoke", "dust", "fire", "explosion".
static func quad(additive: bool, look: String = "puff") -> QuadMesh:
	var key := "%s_%s" % [look, additive]
	if _quads.has(key):
		return _quads[key]
	var sheet: Texture2D = null
	if look != "puff" and ResourceLoader.exists("res://assets/fx/fx_%s_sheet.png" % look):
		sheet = load("res://assets/fx/fx_%s_sheet.png" % look)
	if sheet == null and look != "puff":
		_quads[key] = quad(additive)
		return _quads[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.albedo_texture = puff_texture()
	if sheet != null:
		mat.albedo_texture = sheet
		mat.particles_anim_h_frames = 2
		mat.particles_anim_v_frames = 2
		mat.particles_anim_loop = false
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var mesh := QuadMesh.new()
	mesh.material = mat
	_quads[key] = mesh
	return mesh


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / float(colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	return g


static func _grow(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.max_value = 4.0
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, to))
	return c


## Builds a particle emitter from a settings dictionary.
static func make(cfg: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = cfg.get("mesh", quad(cfg.get("add", false), cfg.get("look", "puff")))
	if cfg.has("look"):
		# Each particle shows one of the four pictures on its sheet.
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
	p.amount = cfg.get("amount", 8)
	p.lifetime = cfg.get("life", 0.6)
	p.one_shot = cfg.get("one_shot", true)
	p.explosiveness = cfg.get("explosive", 0.9)
	p.direction = cfg.get("dir", Vector3.UP)
	p.spread = cfg.get("spread", 60.0)
	p.gravity = cfg.get("gravity", Vector3.ZERO)
	p.initial_velocity_min = cfg.get("speed_min", 0.5)
	p.initial_velocity_max = cfg.get("speed_max", 2.0)
	p.damping_min = cfg.get("damping", 1.0)
	p.damping_max = cfg.get("damping", 1.0) * 1.5
	p.scale_amount_min = cfg.get("size_min", 0.2)
	p.scale_amount_max = cfg.get("size_max", 0.4)
	p.scale_amount_curve = _grow(cfg.get("grow_from", 1.0), cfg.get("grow_to", 1.0))
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	if cfg.has("radius"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = cfg["radius"]
	if cfg.has("colors"):
		p.color_ramp = _ramp(cfg["colors"])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _view(parent: Node) -> Node:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	return parent.get_tree().get_first_node_in_group("world_view")


static func _fire(view: Node, pos: Vector3, cfg: Dictionary) -> void:
	var p := make(cfg)
	p.position = pos
	view.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _at(view: Node, pos: Vector2, y: float) -> Vector3:
	var x: float = pos.x * S
	var z: float = pos.y * S
	return Vector3(x, view.ground(x, z) + y, z)


# ---- Settings for each kind of particle -------------------------------------

static func smoke_cfg(amount: int, size: float, life: float) -> Dictionary:
	return {"amount": amount, "life": life, "speed_min": 0.3, "speed_max": 1.2,
		"spread": 35.0, "gravity": Vector3(0.25, 1.1, 0.0), "damping": 0.4,
		"size_min": size * 0.7, "size_max": size * 1.3, "grow_from": 0.5, "grow_to": 2.6,
		"radius": size * 0.3, "explosive": 0.0, "one_shot": false, "look": "smoke",
		"colors": [Color(0.12, 0.11, 0.1, 0.0), Color(0.16, 0.15, 0.14, 0.7),
			Color(0.36, 0.34, 0.32, 0.4), Color(0.55, 0.52, 0.48, 0.0)]}


static func flame_cfg(amount: int, size: float) -> Dictionary:
	return {"add": true, "amount": amount, "life": 0.6, "speed_min": 0.4, "speed_max": 1.3,
		"spread": 20.0, "gravity": Vector3(0.0, 1.6, 0.0), "damping": 0.2,
		"size_min": size * 0.7, "size_max": size * 1.3, "grow_from": 1.0, "grow_to": 0.3,
		"radius": size * 0.35, "explosive": 0.0, "one_shot": false, "look": "fire",
		"colors": [Color(1.0, 0.95, 0.8, 0.9), Color(1.0, 0.75, 0.5, 0.8),
			Color(0.7, 0.3, 0.15, 0.0)]}


static func dust_cfg(amount: int, size: float) -> Dictionary:
	return {"amount": amount, "life": 0.9, "speed_min": 0.3, "speed_max": 1.4,
		"spread": 75.0, "gravity": Vector3(0.1, 0.3, 0.0), "damping": 1.2,
		"size_min": size * 0.9, "size_max": size * 1.8, "grow_from": 0.5, "grow_to": 2.2,
		"look": "dust",
		"colors": [Color(1.0, 0.97, 0.92, 0.7), Color(1.0, 0.97, 0.92, 0.4),
			Color(1.0, 0.97, 0.92, 0.0)]}


static func _sparks(amount: int, speed: float) -> Dictionary:
	return {"add": true, "amount": amount, "life": 0.3, "speed_min": speed * 0.4,
		"speed_max": speed, "spread": 70.0, "gravity": Vector3(0.0, -6.0, 0.0),
		"damping": 2.0, "size_min": 0.05, "size_max": 0.11,
		"colors": [Color(1, 1, 0.85, 1), Color(1.0, 0.6, 0.15, 0.9), Color(0.8, 0.2, 0.0, 0.0)]}


## Loose sand thrown up and falling back: many small grains on arcs.
static func spray_cfg(amount: int, speed: float) -> Dictionary:
	return {"amount": amount, "life": 0.8, "speed_min": speed * 0.35, "speed_max": speed,
		"spread": 48.0, "gravity": Vector3(0.0, -9.8, 0.0), "damping": 0.3,
		"size_min": 0.03, "size_max": 0.075, "explosive": 0.95,
		"colors": [Color(0.78, 0.68, 0.5, 1.0), Color(0.72, 0.62, 0.45, 0.9),
			Color(0.7, 0.6, 0.44, 0.0)]}


## Foam churned up around a tank wading through water.
static func wake_cfg(amount: int) -> Dictionary:
	return {"amount": amount, "life": 0.9, "speed_min": 0.2, "speed_max": 0.9,
		"spread": 80.0, "gravity": Vector3(0.0, -0.5, 0.0), "damping": 1.5,
		"size_min": 0.14, "size_max": 0.3, "grow_from": 0.6, "grow_to": 2.0,
		"explosive": 0.0, "one_shot": false,
		"colors": [Color(0.93, 0.97, 1.0, 0.6), Color(0.86, 0.93, 0.97, 0.32),
			Color(0.8, 0.9, 0.95, 0.0)]}


## Water drops thrown up and falling back in arcs.
static func droplet_cfg(amount: int, speed: float) -> Dictionary:
	return {"amount": amount, "life": 0.75, "speed_min": speed * 0.35, "speed_max": speed,
		"spread": 50.0, "gravity": Vector3(0.0, -9.8, 0.0), "damping": 0.2,
		"size_min": 0.035, "size_max": 0.085, "explosive": 0.9,
		"colors": [Color(0.95, 0.98, 1.0, 0.95), Color(0.8, 0.9, 0.95, 0.8),
			Color(0.7, 0.85, 0.92, 0.0)]}


## Something heavy hitting the water: a burst of drops and a foam puff.
static func splash(view: Node, at: Vector3, power: float) -> void:
	Sfx.at(view, "water_splash", at, -8.0 + 4.0 * power)
	_fire(view, at, droplet_cfg(int(46.0 * power), 3.6 * sqrt(power)))
	var foam := wake_cfg(int(10.0 * power))
	foam["one_shot"] = true
	foam["explosive"] = 0.9
	foam["speed_max"] = 1.6 * sqrt(power)
	_fire(view, at, foam)
	# The crown of water thrown up, from the splash picture.
	var crown := sprite(view, "fx_splash", at + Vector3(0.0, 0.22 * sqrt(power), 0.0), 0.5 * sqrt(power), false)
	if crown != null:
		var tw := crown.create_tween()
		tw.set_parallel(true)
		tw.tween_property(crown, "scale", crown.scale * Vector3(1.7, 1.5, 1.7), 0.5)
		tw.tween_property(crown.material_override, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(crown.queue_free)


## One picture from assets/fx standing in the world, always facing the
## camera. The caller animates and frees it. Null if the picture is missing.
static func sprite(view: Node, name: String, at: Vector3, size: float, additive: bool) -> MeshInstance3D:
	var path := "res://assets/fx/%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	var pic: Texture2D = load(path)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = pic
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var card := QuadMesh.new()
	card.size = Vector2(1.0, float(pic.get_height()) / float(pic.get_width()))
	var m := MeshInstance3D.new()
	m.mesh = card
	m.material_override = mat
	m.position = at
	m.scale = Vector3(size, size, size)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(m)
	return m


## Green sparkle rising off a tank that picked up a repair or armour.
static func heal(parent: Node, pos: Vector2) -> void:
	Net.fx(parent, "heal", [pos])
	var view := _view(parent)
	if view == null:
		return
	var glow := sprite(view, "fx_heal", _at(view, pos, 0.5), 0.9, true)
	if glow == null:
		return
	var tw := glow.create_tween()
	tw.set_parallel(true)
	tw.tween_property(glow, "position:y", glow.position.y + 0.9, 0.9)
	tw.tween_property(glow, "scale", glow.scale * 1.5, 0.9)
	tw.tween_property(glow.material_override, "albedo_color:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(glow.queue_free)


# ---- Effects ----------------------------------------------------------------

static func dust(parent: Node, pos: Vector2, amount: int = 8) -> void:
	Net.fx(parent, "dust", [pos, amount])
	var view := _view(parent)
	if view != null:
		_fire(view, _at(view, pos, 0.15), dust_cfg(amount, 0.3))


## Shell hitting something: sparks and a dust puff. `what` picks the sound:
## "armour", "wall" or "sand".
static func hit(parent: Node, pos: Vector2, what: String = "sand") -> void:
	Net.fx(parent, "hit", [pos, what])
	var view := _view(parent)
	if view == null:
		return
	Sfx.at(view, "hit_" + what, _at(view, pos, 0.35), -3.0)
	_fire(view, _at(view, pos, 0.35), _sparks(10, 5.0))
	_fire(view, _at(view, pos, 0.1), spray_cfg(36, 5.0))
	_fire(view, _at(view, pos, 0.3), dust_cfg(6, 0.25))


## Gun firing: a bright flash down the barrel line, then drifting smoke.
static func muzzle(parent: Node, pos: Vector2, dir: Vector2, heavy: bool = true) -> void:
	Net.fx(parent, "muzzle", [pos, dir, heavy])
	var view := _view(parent)
	if view == null:
		return
	if heavy:
		Sfx.at(view, "cannon_shot", _at(view, pos, 0.4), 0.0)
	else:
		Sfx.at(view, "mg_shot", _at(view, pos, 0.4), -6.0)
	var d := Vector3(dir.x, 0.0, dir.y)
	var at := _at(view, pos, 0.4)
	_fire(view, at, {"add": true, "amount": 7, "life": 0.1, "dir": d, "spread": 14.0,
		"speed_min": 2.0, "speed_max": 7.0, "damping": 6.0, "size_min": 0.25,
		"size_max": 0.5, "grow_from": 1.0, "grow_to": 0.4, "explosive": 1.0,
		"colors": [Color(1, 1, 0.85, 1), Color(1.0, 0.65, 0.2, 0.9), Color(1.0, 0.3, 0.05, 0.0)]})
	_fire(view, at, {"amount": 8, "life": 1.3, "dir": d, "spread": 25.0,
		"speed_min": 0.5, "speed_max": 2.2, "damping": 2.0, "gravity": Vector3(0.15, 0.5, 0.0),
		"size_min": 0.2, "size_max": 0.36, "grow_from": 0.5, "grow_to": 2.6, "look": "smoke",
		"colors": [Color(0.75, 0.72, 0.68, 0.55), Color(0.55, 0.53, 0.5, 0.3),
			Color(0.5, 0.48, 0.45, 0.0)]})
	_fire(view, _at(view, pos, 0.08), dust_cfg(8, 0.3))
	_fire(view, _at(view, pos, 0.05), spray_cfg(24, 3.0))


## Vehicle or building blowing up. `big` is for the base.
static func explosion(parent: Node, pos: Vector2, big: bool = false, scale: float = 1.0) -> void:
	Net.fx(parent, "explosion", [pos, big, scale])
	var view := _view(parent)
	if view == null:
		return
	var k: float = (1.7 if big else 1.0) * scale
	Sfx.at(view, "explosion_tank", _at(view, pos, 0.4), 2.0 if scale >= 1.0 else -5.0,
		0.8 if big else (1.0 if scale >= 1.0 else 1.5))
	var at := _at(view, pos, 0.35)
	_fire(view, at, {"add": true, "amount": 3, "life": 0.14, "speed_min": 0.0,
		"speed_max": 0.2, "size_min": 1.4 * k, "size_max": 2.0 * k, "explosive": 1.0,
		"colors": [Color(1, 1, 0.9, 1), Color(1.0, 0.7, 0.3, 0.0)]})
	_fire(view, at, {"add": true, "amount": 18, "life": 0.6, "speed_min": 1.0 * k,
		"speed_max": 3.6 * k, "spread": 80.0, "gravity": Vector3(0.0, 1.6, 0.0), "damping": 3.0,
		"size_min": 0.55 * k, "size_max": 1.1 * k, "grow_from": 0.5, "grow_to": 1.7,
		"look": "explosion",
		"colors": [Color(1.0, 1.0, 0.9, 1.0), Color(1.0, 0.8, 0.6, 0.9),
			Color(0.7, 0.35, 0.2, 0.5), Color(0.3, 0.12, 0.08, 0.0)]})
	var smoke := smoke_cfg(18, 0.7 * k, 2.6)
	smoke["one_shot"] = true
	smoke["explosive"] = 0.8
	smoke["speed_max"] = 2.0 * k
	_fire(view, at, smoke)
	_fire(view, at, _sparks(16, 8.0))
	if _chunk == null:
		var scrap := StandardMaterial3D.new()
		scrap.albedo_color = Color(0.07, 0.07, 0.07)
		scrap.roughness = 0.9
		_chunk = BoxMesh.new()
		_chunk.size = Vector3(1, 0.6, 0.8)
		_chunk.material = scrap
	_fire(view, at, {"mesh": _chunk, "amount": 10, "life": 1.0, "speed_min": 2.5,
		"speed_max": 6.0, "spread": 55.0, "gravity": Vector3(0.0, -9.8, 0.0), "damping": 0.0,
		"size_min": 0.025, "size_max": 0.06, "explosive": 1.0,
		"colors": [Color(0.1, 0.1, 0.1, 1), Color(0.1, 0.1, 0.1, 1)]})
	_fire(view, _at(view, pos, 0.1), dust_cfg(14, 0.45 * k))
	_fire(view, _at(view, pos, 0.1), spray_cfg(90, 7.5 * k))
	view.add_scorch(pos.x * S, pos.y * S, 1.3 * k)
	view.add_shockwave(pos.x * S, pos.y * S, 1.3 * k)
	view.get_tree().call_group("shaker", "shake", (16.0 if big else 9.0) * scale)
