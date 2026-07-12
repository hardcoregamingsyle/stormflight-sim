class_name UIKit
## Shared UI construction helpers + palette. All UI is built in code.

const BG := Color(0.06, 0.08, 0.12, 0.94)
const BG_LIGHT := Color(0.11, 0.14, 0.2, 0.96)
const ACCENT := Color(1.0, 0.69, 0.12)
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.62, 0.68, 0.76)
const GOOD := Color(0.35, 0.9, 0.45)
const BAD := Color(1.0, 0.32, 0.28)
const WARN := Color(1.0, 0.78, 0.2)

static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func btn(text: String, cb: Callable, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_LIGHT
	sb.border_color = ACCENT * Color(1, 1, 1, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.17, 0.22, 0.3)
	sbh.border_color = ACCENT
	b.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = ACCENT
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
	b.focus_mode = Control.FOCUS_NONE  # keep Tab free for the ATC panel
	b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("click", 0.6))
	return b

static func panel(bg: Color = BG) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	return p

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func bar(value: float, color: Color, width: float = 120.0, height: float = 10.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = 1.0
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, height)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0, 0, 0, 0.5)
	bg_sb.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg_sb)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("fill", fill)
	return pb

static func spacer(h: float = 10.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func center(node: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.add_child(node)
	return c
