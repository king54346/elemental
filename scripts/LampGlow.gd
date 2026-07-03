extends Node3D
## Makes the lantern's glass/shade self-illuminate (emissive), like the original
## Tent lamp. Traverses child mesh surfaces, finds materials whose name suggests a
## lamp/glass, and drives their emission by day/night via EnvState.

@export var lamp_color: Color = Color(1.0, 0.886, 0.525)   # 0xffe286
@export var night_energy: float = 2.0
@export var day_energy: float = 0.1
@export var name_hints: PackedStringArray = ["glass", "lantern", "bulb", "emis"]

var _mats: Array[StandardMaterial3D] = []
var _lamp_mesh: MeshInstance3D          # the lantern mesh (kept on layer 1 so the lamp casts its frame shadow)

## Tent meshes go on render layer 2 so the TentLamp (which sits at the tent) can be
## told to ignore them via its light_cull_mask — the lamp lights/shadows everything
## else but never casts the tent's own (wrong) self-shadow.
const TENT_RENDER_LAYER := 2

func _ready() -> void:
	_collect(self)
	if _mats.is_empty():
		push_warning("LampGlow: no lamp/glass material found under " + name)
	_set_render_layer(self)
	_apply(EnvState.is_night())
	EnvState.env_time_changed.connect(_on_time_changed)

func _set_render_layer(node: Node) -> void:
	# all tent + lantern meshes go on layer 2 so the TentLamp ignores them: a light
	# sitting inside the lantern frame would otherwise project a huge frame shadow.
	# The lamp still shadows external objects (rocks/ground); the lantern just glows.
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = TENT_RENDER_LAYER
	for c in node.get_children():
		_set_render_layer(c)

func _on_time_changed(_a: String, _b: String) -> void:
	_apply(EnvState.is_night())

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				var nm := ""
				if mat != null:
					nm = str(mat.resource_name).to_lower()
				if _matches(nm):
					# translucent glowing glass: transparent so it doesn't block the
					# light inside the lantern (transparent = no shadow cast); the
					# opaque frame surface still casts a lantern-cage shadow.
					var m := StandardMaterial3D.new()
					m.albedo_color = Color(lamp_color.r, lamp_color.g, lamp_color.b, 0.45)
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.emission_enabled = true
					m.emission = lamp_color
					m.emission_energy_multiplier = night_energy
					mi.set_surface_override_material(i, m)
					_mats.append(m)
					_lamp_mesh = mi
					print("LampGlow: emissive applied to '", nm, "' (surface ", i, " of ", mi.name, ")")
	for c in node.get_children():
		_collect(c)

func _matches(nm: String) -> bool:
	if nm == "":
		return false
	for h in name_hints:
		if nm.find(h) >= 0:
			return true
	return false

func _apply(night: bool) -> void:
	var e: float = night_energy if night else day_energy
	for m in _mats:
		m.emission_energy_multiplier = e
