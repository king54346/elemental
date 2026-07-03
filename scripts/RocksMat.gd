extends Node3D
## Applies the rocks shader to the imported GLB meshes and recolors it on
## season/time change. Replaces the generic ApplyMaterialOverride for rocks.

@export var material: Material

func _ready() -> void:
	if material != null:
		_apply_override(self)
	_apply_colors()
	EnvState.season_changed.connect(_on_changed)
	EnvState.env_time_changed.connect(_on_changed)

func _on_changed(_a: String, _b: String) -> void:
	_apply_colors()

func _process(_dt: float) -> void:
	if EnvState.cycle_enabled:
		_apply_colors()   # continuous dawn/dusk color blend

func _apply_override(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		_apply_override(child)

func _apply_colors() -> void:
	if material == null or not material is ShaderMaterial:
		return
	var sm := material as ShaderMaterial
	var c := EnvState.rocks_blended()
	sm.set_shader_parameter("rock_color1", c.r1)
	sm.set_shader_parameter("rock_color2", c.r2)
	sm.set_shader_parameter("rock_color3", c.r3)
	sm.set_shader_parameter("moss_color1", c.m1)
	sm.set_shader_parameter("moss_color2", c.m2)
	sm.set_shader_parameter("moss_color3", c.m3)
