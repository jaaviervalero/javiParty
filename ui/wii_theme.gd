class_name WiiTheme
extends RefCounted
## Tema visual propio inspirado en las consolas de salón de los 2000: fondo
## blanco/gris claro, acento cian, píldoras redondeadas con brillo y fuente
## redondeada (Nunito, OFL). Todo generado por código, sin assets de terceros.

const BG_TOP := Color("fbfcfd")
const BG_BOTTOM := Color("e3e8ed")
const STRIPE := Color(0.0, 0.0, 0.0, 0.025)
const PANEL := Color("ffffff")
const PANEL_BORDER := Color("cfd8e0")
const TEXT := Color("5b6670")
const TEXT_SOFT := Color("8e99a3")
const ACCENT := Color("33b5e5")
const ACCENT_DARK := Color("1b8fc0")
const ACCENT_LIGHT := Color("e6f7fd")
const SHADOW := Color(0.2, 0.3, 0.4, 0.14)

const FONT_PATH := "res://assets/fonts/Nunito.ttf"


static func font(weight := 600) -> Font:
	var base: FontFile = load(FONT_PATH)
	var f := FontVariation.new()
	f.base_font = base
	var ts := TextServerManager.get_primary_interface()
	f.variation_opentype = {ts.name_to_tag("wght"): weight}
	return f


static func panel_style(radius := 22, border := PANEL_BORDER, bg := PANEL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = SHADOW
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	s.set_content_margin_all(18)
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 22

	# --- Botón píldora ---
	var normal := panel_style(28)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = ACCENT_LIGHT
	hover.border_color = ACCENT
	hover.set_border_width_all(3)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("c9ecfa")
	pressed.shadow_size = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("f1f3f5")
	# El foco (mando de la tele) se ve como un halo cian grueso alrededor.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ACCENT
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(32)
	focus.set_expand_margin_all(4)
	focus.anti_aliasing = true

	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT_DARK)
	t.set_color("font_focus_color", "Button", ACCENT_DARK)
	t.set_color("font_pressed_color", "Button", ACCENT_DARK)
	t.set_color("font_hover_pressed_color", "Button", ACCENT_DARK)
	t.set_color("font_disabled_color", "Button", TEXT_SOFT)

	# --- Paneles y textos ---
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_color("font_color", "Label", TEXT)

	# --- Campo de texto ---
	var le := panel_style(16)
	le.content_margin_left = 16
	le.content_margin_right = 16
	le.content_margin_top = 10
	le.content_margin_bottom = 10
	le.shadow_size = 0
	var le_focus := focus.duplicate() as StyleBoxFlat
	le_focus.set_corner_radius_all(18)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT_DARK)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_SOFT)
	t.set_font_size("font_size", "LineEdit", 26)
	return t
