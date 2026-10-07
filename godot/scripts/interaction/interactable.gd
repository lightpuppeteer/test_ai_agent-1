class_name Interactable
extends Node3D
## Something the player can use with E: sit on a bench, lie on a towel, drive a
## car, talk to a villager… Anchors ("seats") are child Node3Ds whose transform is
## where a character's root goes; the character faces the anchor's -Z.

signal used(by: Node, seat: Node3D)

@export var kind := "sit"            ## sit | lie | drive | talk | look
@export var prompt := "Sit"
@export var radius := 1.8            ## how close the player must be (from this node's origin)
@export var enabled := true
## Quest hook: quests can wait for "use" on this tag (see QuestData).
@export var tag := ""

var seats: Array[Node3D] = []
var occupants := {}                  ## seat -> character
var owner_node: Node = null          ## e.g. the Car or Villager this belongs to


func _ready() -> void:
	add_to_group("interactable")
	for c in get_children():
		if c is Node3D and c.name.begins_with("Seat"):
			seats.append(c)


func add_seat(local_pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var s := Node3D.new()
	s.name = "Seat%d" % seats.size()
	s.position = local_pos
	s.rotation.y = deg_to_rad(yaw_deg)
	add_child(s)
	seats.append(s)
	return s


## Free seat nearest to `pos` (or null).
func free_seat(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for s in seats:
		if occupants.has(s):
			continue
		var d := s.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = s
	return best


func has_free_seat() -> bool:
	return seats.is_empty() or occupants.size() < seats.size()


func occupy(seat: Node3D, who: Node) -> void:
	occupants[seat] = who


func release(who: Node) -> void:
	for s in occupants.keys():
		if occupants[s] == who:
			occupants.erase(s)


func can_use(_by: Node) -> bool:
	return enabled and has_free_seat()


func interact(by: Node) -> void:
	var seat := free_seat(by.global_position) if not seats.is_empty() else null
	used.emit(by, seat)
	if tag != "" and Game.quests:
		Game.quests.on_use(tag)
