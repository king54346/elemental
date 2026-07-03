@tool
class_name WaterCutoutTrapezoid
extends MeshInstance3D
## Editable trapezoid water-cutout segment (ported from the RealisticEnvironments
## ocean_system). Draws a wireframe gizmo in the editor and exposes get_segment()
## which FloatingBoat feeds to the water shader (WaterVolume.set_hull_cutouts) to
## carve the water out of the open hull. Length runs along local +Z; width along
## local X (start_half_width at -Z, end_half_width at +Z). Add these under the boat
## (in group "boat_cutout") oriented so +Z points along the hull.

const DEBUG_COLOR := Color(0.2, 0.7, 1.0, 0.9)

@export_range(0.01, 100.0, 0.01, "or_greater") var half_length := 0.5 :
	set(v): half_length = maxf(v, 0.01); _rebuild()
@export_range(0.01, 100.0, 0.01, "or_greater") var start_half_width := 0.4 :
	set(v): start_half_width = maxf(v, 0.01); _rebuild()
@export_range(0.01, 100.0, 0.01, "or_greater") var end_half_width := 0.4 :
	set(v): end_half_width = maxf(v, 0.01); _rebuild()
@export_range(-20.0, 20.0, 0.01) var vertical_min_offset := -0.35 :
	set(v): vertical_min_offset = v; _rebuild()
@export_range(-20.0, 20.0, 0.01) var vertical_max_offset := 0.4 :
	set(v): vertical_max_offset = v
@export_range(0.001, 10.0, 0.01, "or_greater") var height_feather := 0.15
@export var debug_draw := true :
	set(v): debug_draw = v; _update_visibility()
@export var debug_draw_in_game := false :
	set(v): debug_draw_in_game = v; _update_visibility()

var _mesh := ImmediateMesh.new()
var _mat: StandardMaterial3D

func _ready() -> void:
	if not is_in_group(&"boat_cutout"):
		add_to_group(&"boat_cutout")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 10000.0
	mesh = _mesh
	_rebuild()
	_update_visibility()

## The cutout segment in the format WaterVolume.set_hull_cutouts expects.
func get_segment() -> Dictionary:
	return {
		"center": global_position,
		"right": global_transform.basis.x.normalized(),
		"forward": global_transform.basis.z.normalized(),
		"half_width": maxf(start_half_width, end_half_width),
		"half_length": half_length,
		"start_w": start_half_width,
		"end_w": end_half_width,
		"shape_type": 1.0 if absf(start_half_width - end_half_width) > 0.001 else 0.0,
		"max_y": global_position.y + vertical_max_offset,
		"feather": height_feather,
	}

func _rebuild() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var y0 := vertical_min_offset
	var y1 := vertical_max_offset
	var corners := [
		Vector3(-start_half_width, y0, -half_length), Vector3(start_half_width, y0, -half_length),
		Vector3(-end_half_width, y0, half_length), Vector3(end_half_width, y0, half_length),
		Vector3(-start_half_width, y1, -half_length), Vector3(start_half_width, y1, -half_length),
		Vector3(-end_half_width, y1, half_length), Vector3(end_half_width, y1, half_length),
	]
	var edges := [0,1, 1,3, 3,2, 2,0, 4,5, 5,7, 7,6, 6,4, 0,4, 1,5, 2,6, 3,7]
	for i in range(0, edges.size(), 2):
		_mesh.surface_add_vertex(corners[edges[i]])
		_mesh.surface_add_vertex(corners[edges[i + 1]])
	_mesh.surface_end()
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.no_depth_test = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = DEBUG_COLOR
	material_override = _mat

func _update_visibility() -> void:
	visible = debug_draw and (Engine.is_editor_hint() or debug_draw_in_game)
