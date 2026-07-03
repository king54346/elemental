extends CanvasLayer
## In-game UI — ported from the DOM-based MusicControlUI / LightningButtonUI /
## ToastManager. Bottom-right control buttons + top-left toast notifications.
## Season/time toasts fire from EnvState signals so keyboard toggles (S/T) show them too.

const SEASON_NAMES := {
	"spring": "Blooming Spring",
	"winter": "Frosty Winter",
	"autumn": "Cozy Autumn",
	"rainy": "Thundering Rain",
}

var _toast_box: VBoxContainer
var _music_btn: Button
var _lightning_btn: Button

func _ready() -> void:
	_build()
	EnvState.season_changed.connect(_on_season_changed)
	EnvState.env_time_changed.connect(_on_time_changed)
	_update_lightning_visibility()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# toast column, top-left
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toast_box.position = Vector2(24, 24)
	_toast_box.add_theme_constant_override("separation", 10)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	# control panel, bottom-right
	var panel := HBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-24, -24)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_constant_override("separation", 10)
	root.add_child(panel)

	_lightning_btn = _make_button("⚡ Lightning", _on_lightning)
	panel.add_child(_lightning_btn)
	panel.add_child(_make_button("Season", _on_season_btn))
	panel.add_child(_make_button("Day / Night", _on_time_btn))
	_music_btn = _make_button("♪ Music: On", _on_music_btn)
	panel.add_child(_music_btn)

func _sbox(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(12)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.border_color = border
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 6
	return s

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 0.9))
	b.add_theme_stylebox_override("normal", _sbox(Color(0.09, 0.11, 0.14, 0.72), Color(1, 1, 1, 0.10)))
	b.add_theme_stylebox_override("hover", _sbox(Color(0.16, 0.19, 0.24, 0.85), Color(1, 1, 1, 0.22)))
	b.add_theme_stylebox_override("pressed", _sbox(Color(0.06, 0.07, 0.09, 0.9), Color(1, 1, 1, 0.15)))
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call())
	b.mouse_entered.connect(func(): AudioManager.play_sfx("hover", 0.5))
	return b

# ---------- button handlers ----------
func _on_season_btn() -> void:
	EnvState.toggle_season()

func _on_time_btn() -> void:
	EnvState.toggle_time()

func _on_music_btn() -> void:
	var on := AudioManager.toggle_music()
	_music_btn.text = "♪ Music: On" if on else "♪ Music: Off"
	if not on:
		show_toast("Music", "Disabled")

func _on_lightning() -> void:
	AudioManager.play_thunder_strike()
	get_tree().call_group("lightning", "manual_strike")

# ---------- env reactions ----------
func _on_season_changed(new_season: String, _old: String) -> void:
	show_toast("Season Changed", SEASON_NAMES.get(new_season, new_season))
	_update_lightning_visibility()

func _on_time_changed(new_time: String, _old: String) -> void:
	show_toast("Time Changed", "Daytime" if new_time == "day" else "Nighttime")

func _update_lightning_visibility() -> void:
	if _lightning_btn:
		_lightning_btn.visible = EnvState.season == "rainy"

# ---------- toasts ----------
func show_toast(label: String, title: String) -> void:
	var panel := PanelContainer.new()
	panel.modulate.a = 0.0
	var sb := _sbox(Color(0.09, 0.11, 0.14, 0.82), Color(1, 1, 1, 0.12))
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var l := Label.new()
	l.text = label.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	vb.add_child(l)
	vb.add_child(t)
	_toast_box.add_child(panel)

	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.35)
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)
