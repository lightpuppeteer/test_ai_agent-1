class_name Door
extends Interactable
## Press E to go through: fades out, moves you (and him) to the other side.

## Where you arrive (global), which way you face, and where that is ("outside", "pizza"…).
var target := Vector3.ZERO
var target_yaw := 0.0
var target_location := "outside"
var locked_text := ""     # if set, the door says this instead of opening


func _ready() -> void:
	kind = "door"
	radius = 2.2
	super._ready()
	used.connect(_on_used)


func _on_used(_by: Node, _seat: Node3D) -> void:
	if locked_text != "":
		if Game.hud:
			Game.hud.toast(locked_text)
		return
	await Places.travel(target, target_yaw, target_location)
