extends CharacterBody3D
## The server advances this body once per 60 Hz tick. Clients interpolate snapshots.
const WALK_SPEED := 2.8
const RUN_SPEED := 4.6
var peer_id := 0
var slot := 0
var display_name := ""
var aim_pitch := 0.0
var axes := Vector2.ZERO
var running := false
var last_input_tick := -1000
var last_sequence := -1
var avatar: Node3D
var target_position := Vector3.ZERO
var target_yaw := 0.0
var motion := "idle"

func configure(id: int, player_slot: int, label: String, visuals: bool) -> void:
	peer_id=id;slot=player_slot;display_name=label
	name="Player_%d" % id
	collision_layer=2;collision_mask=1 # Players do not push/block each other in this first slice.
	floor_snap_length=.3;floor_max_angle=deg_to_rad(48)
	var shape:=CapsuleShape3D.new();shape.radius=.27;shape.height=1.72
	var collider:=CollisionShape3D.new();collider.shape=shape;collider.position.y=.88
	add_child(collider)
	if visuals:
		avatar=preload("res://coop/avatar.gd").new();add_child(avatar);avatar.setup(slot)

func simulate(dt: float, tick: int) -> void:
	if tick-last_input_tick>18:axes=Vector2.ZERO;running=false
	var direction:=Vector3(axes.x,0,axes.y).rotated(Vector3.UP,rotation.y)
	var speed:=RUN_SPEED if running else WALK_SPEED
	velocity.x=direction.x*speed;velocity.z=direction.z*speed
	velocity.y=-1.0 if is_on_floor() else velocity.y-20.0*dt
	move_and_slide()
	var horizontal:=Vector2(velocity.x,velocity.z).length()
	motion="run" if horizontal>3.3 else "walk" if horizontal>.1 else "idle"

func snapshot() -> Dictionary:
	return {"id":peer_id,"slot":slot,"name":display_name,"position":position,"yaw":rotation.y,"pitch":aim_pitch,"velocity":velocity,"motion":motion,"ack":last_sequence}

func apply_snapshot(row: Dictionary, first: bool=false) -> void:
	target_position=row.position;target_yaw=row.yaw;aim_pitch=row.pitch
	velocity=row.velocity;motion=row.motion;last_sequence=row.ack
	if first:position=target_position;rotation.y=target_yaw

func present(dt: float, local: bool) -> void:
	position=position.lerp(target_position,1.0-exp(-18.0*dt))
	rotation.y=lerp_angle(rotation.y,target_yaw,1.0-exp(-18.0*dt))
	if avatar:
		avatar.visible=not local
		avatar.advance(dt,motion,Vector2(velocity.x,velocity.z).length(),aim_pitch)

func observe() -> Dictionary:
	return {"id":peer_id,"slot":slot,"name":display_name,"position":[position.x,position.y,position.z],"target":[target_position.x,target_position.y,target_position.z],"yaw":rotation.y,"motion":motion,"ack":last_sequence,"avatar":avatar.observe() if avatar else {}}
