extends CharacterBody3D

const Props = preload("res://scripts/props.gd")
var mode := "patrol"
var hp := 100.0
var cooldown := 0.0
var home := Vector3(5, 0, -6)
var patrol_target := Vector3(6, 0, -6)
var enabled := true
var last_seen := false
var attacks := 0
var model: Node3D
var animator: AnimationPlayer
var animation_preview := false

func _ready() -> void:
	name = "Guard"
	collision_layer = 4
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	model = Props.mannequin(self, Color("a76a60"))
	animator = Props.animator(self)

func reset_at(pos: Vector3, active: bool = true) -> void:
	position = pos
	home = pos
	patrol_target = pos + Vector3(1, 0, 0)
	velocity = Vector3.ZERO
	hp = 100
	cooldown = 0
	attacks = 0
	last_seen = false
	enabled = active
	mode = "patrol" if active else "idle"
	model.rotation = Vector3.ZERO
	animation_preview = false
	animator.play("idle")
	animator.seek(0, true)

func tick(dt: float, player: CharacterBody3D) -> void:
	if not enabled or hp <= 0:
		mode = "dead" if hp <= 0 else "idle"
		Props.animate(animator, dt, false, animation_preview)
		return
	cooldown = maxf(0, cooldown - dt)
	var dist: float = position.distance_to(player.position)
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, player.global_position + Vector3.UP, 1)
	last_seen = dist < 6 and get_world_3d().direct_space_state.intersect_ray(ray).is_empty() and player.hp > 0
	var destination: Vector3
	var walk_speed := 0.8
	if last_seen:
		destination = player.position
		mode = "chase" if dist > 1.2 else "attack"
		walk_speed = 1.8
		if mode == "attack":
			walk_speed = 0
			if cooldown <= 0:
				player.hp = maxf(0, player.hp - 10)
				attacks += 1
				cooldown = 1.0
	else:
		mode = "patrol"
		destination = patrol_target
		if position.distance_to(patrol_target) < 0.2:
			patrol_target = home if patrol_target != home else home + Vector3(1, 0, 0)
	var direction := (destination - position)
	direction.y = 0
	direction = direction.normalized()
	velocity = direction * walk_speed
	velocity.y = -2
	move_and_slide()
	if direction.length() > 0.01:
		model.rotation.y = atan2(-direction.x, -direction.z)
	Props.animate(animator, dt, walk_speed > 0, animation_preview)

func state() -> Dictionary:
	return {"position": [position.x, position.y, position.z], "velocity": [velocity.x, velocity.y, velocity.z], "state": mode, "hp": hp, "line_of_sight": last_seen, "attacks": attacks, "cooldown": cooldown, "home": [home.x, home.y, home.z], "patrol_target": [patrol_target.x, patrol_target.y, patrol_target.z], "enabled": enabled, "model_yaw": model.rotation.y, "animation": Props.animation_state(animator, animation_preview)}
