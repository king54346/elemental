extends Node3D
## Applies a material_override to every MeshInstance3D under this node.
## Mirrors the original's `traverse(mesh => mesh.material = ...)` pattern used for
## imported GLB scenes (rocks, etc.).

@export var material: Material

func _ready() -> void:
	if material == null:
		return
	_apply(self)

func _apply(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		_apply(child)
