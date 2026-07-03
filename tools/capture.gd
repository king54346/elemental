extends Node
## Dev-only: loads Main.tscn, waits a few frames, saves a screenshot, quits.
## Run: godot --path <proj> res://tools/Capture.tscn  (windowed, needs a display)

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = scene.instantiate()
	add_child(main)
	# force the scene's own camera to be current (capture harness quirk)
	var cam := main.find_child("Camera3D", true, false)
	if cam is Camera3D:
		(cam as Camera3D).make_current()
	# let a few frames render so textures/shaders settle
	for i in 30:
		await get_tree().process_frame
	await get_tree().create_timer(3.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/capture.png")
	print("SCREENSHOT_SAVED")
	get_tree().quit()
