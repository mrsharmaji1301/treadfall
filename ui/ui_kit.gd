extends RefCounted
## Shared neon look for labels and buttons.


static func label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func centered(text: String, font_size: int, color: Color, y: float) -> Label:
	var l := label(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(1280, font_size + 16)
	return l


## A picture from assets/ui, or null if it is not there.
static func art(name: String) -> Texture2D:
	var path := "res://assets/ui/" + name
	if not ResourceLoader.exists(path):
		return null
	var t = load(path)
	return t if t is Texture2D else null


## A slot-bar icon: the painted PNG if there is one, else the old SVG.
static func icon(name: String) -> Texture2D:
	var t := art("icons/%s.png" % name)
	return t if t != null else art("icons/%s.svg" % name)


## Full-screen picture that covers the 1280 x 720 view.
static func backdrop(name: String, dim: float = 0.0) -> Control:
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := art(name)
	if t != null:
		var pic := TextureRect.new()
		pic.texture = t
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.size = Vector2(1280, 720)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pic)
	if dim > 0.0 or t == null:
		var shade := ColorRect.new()
		shade.color = Color(0.03, 0.03, 0.025, dim) if t != null else Color(0.1, 0.095, 0.08)
		shade.size = Vector2(1280, 720)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(shade)
	return holder


## A steel frame stretched round a rectangle, corners kept square.
## `shrink` first scales the picture down to that many pixels wide, for a
## thin frame round something small.
static func frame(name: String, at: Vector2, size: Vector2, margin: int, centre: bool,
		shrink: int = 0) -> NinePatchRect:
	var t := art(name)
	if t == null:
		return null
	if shrink > 0:
		var img: Image = t.get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(shrink, shrink * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
		t = ImageTexture.create_from_image(img)
	var f := NinePatchRect.new()
	f.texture = t
	f.draw_center = centre
	f.patch_margin_left = margin
	f.patch_margin_right = margin
	f.patch_margin_top = margin
	f.patch_margin_bottom = margin
	f.position = at
	f.size = size
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


static func _plate(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = art(name)
	return sb


static func button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 54)
	b.add_theme_font_size_override("font_size", 22)
	if art("hud_button.png") != null and art("hud_button_hover.png") != null:
		# Painted steel plates. The text is dark, to read on the tan paint.
		b.custom_minimum_size = Vector2(340, 62)
		var ink := Color(0.16, 0.12, 0.07) if color != Cfg.COL_WARN else Color(0.5, 0.08, 0.04)
		b.add_theme_color_override("font_color", ink)
		b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.0))
		b.add_theme_color_override("font_focus_color", Color(0.05, 0.03, 0.0))
		b.add_theme_color_override("font_pressed_color", Color(0.05, 0.03, 0.0))
		b.add_theme_stylebox_override("normal", _plate("hud_button.png"))
		b.add_theme_stylebox_override("hover", _plate("hud_button_hover.png"))
		b.add_theme_stylebox_override("focus", _plate("hud_button_hover.png"))
		b.add_theme_stylebox_override("pressed", _plate("hud_button_hover.png"))
		return b
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(color, 0.08, 0.6))
	b.add_theme_stylebox_override("hover", _box(color, 0.25, 1.0))
	b.add_theme_stylebox_override("focus", _box(color, 0.25, 1.0))
	b.add_theme_stylebox_override("pressed", _box(color, 0.45, 1.0))
	return b


static func _box(color: Color, fill: float, border: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * fill, color.g * fill, color.b * fill, 0.92)
	sb.border_color = Color(color, border)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb
