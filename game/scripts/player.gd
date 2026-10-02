extends CharacterBody3D

const Props = preload("res://scripts/props.gd")
var yaw := 0.0
var pitch := -0.15
var hp := 100.0
var speed := 3.0
var model: Node3D
var animator: AnimationPlayer
var animation_preview := false

func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
	model = Props.mannequin(self, Color("437e91"))
	animator = Props.animator(self)

func tick(dt: float, enabled: bool) -> void:
	var axes := Input.get_vector("left", "right", "forward", "back") if enabled and hp > 0 else Vector2.ZERO
	var direction := Vector3(axes.x, 0, axes.y).rotated(Vector3.UP, yaw)
	var move_speed := speed * (1.65 if Input.is_action_pressed("run") else 1.0)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * dt
	move_and_slide()
	if direction.length() > 0.01:
		model.rotation.y = atan2(-direction.x, -direction.z)
	Props.animate(animator, dt, direction.length() > 0.01, animation_preview)

func reset_at(pos: Vector3) -> void:
	position = pos
	velocity = Vector3.ZERO
	yaw = 0
	pitch = -0.15
	hp = 100
	model.rotation = Vector3.ZERO
	animation_preview = false
	animator.play("idle")
	animator.seek(0, true)

func state() -> Dictionary:
	return {"position": [position.x, position.y, position.z], "velocity": [velocity.x, velocity.y, velocity.z], "hp": hp, "yaw": yaw, "pitch": pitch, "on_floor": is_on_floor(), "model_yaw": model.rotation.y, "animation": Props.animation_state(animator, animation_preview)}
