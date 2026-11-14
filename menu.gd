extends Control

## The start menu. Click anywhere (or press any key) to begin the game —
## this swaps to the main scene, where the opening cutscene plays.

@onready var prompt: Label = $PromptLabel

var _time := 0.0


func _ready() -> void:
	# Make sure the cursor is visible and free on the menu.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton and event.pressed:
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		pressed = true
	if pressed:
		get_tree().change_scene_to_file("res://main.tscn")


func _process(delta: float) -> void:
	# The prompt breathes gently while waiting for a click.
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * 2.5)
	prompt.modulate.a = 0.6 + pulse * 0.4
