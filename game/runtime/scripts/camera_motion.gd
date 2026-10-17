extends RefCounted
## Only presentation is interpolated. Collision and gameplay queries retain the
## current 60 Hz pose. Mouse yaw/pitch are read live, never smoothed or delayed.
var world: Node3D
var ready := false
var previous_position := Vector3.ZERO
var position := Vector3.ZERO
var previous_offset := Vector3.ZERO
var offset := Vector3.ZERO
var previous_force := Vector3.ZERO
var force := Vector3.ZERO
var previous_fov := 75.0
var fov := 75.0

func setup(game: Node3D) -> void:world=game

func read_tick() -> void:
	position=world.player.global_position
	offset=world.feedback.camera_offset
	force=world.feedback.camera_rotation+Vector3(world.firearms.recoil.x,world.firearms.recoil.y,0)
	fov=75+world.feedback.grab_blend*1.5

func begin_tick() -> void:
	previous_position=position;previous_offset=offset;previous_force=force;previous_fov=fov

func reset() -> void:
	read_tick();begin_tick();ready=true;render(1.0)

func commit_tick() -> void:
	read_tick()
	# Standalone visual setup may advance bounded ticks outside the engine's
	# physics callback. Such snapshots must not drift while waiting for a PNG.
	if not Engine.is_in_physics_frame():begin_tick()

func apply_pose(foot: Vector3, eye_offset: Vector3, kick: Vector3, lens: float) -> void:
	var yaw:=Basis(Vector3.UP,world.player.global_rotation.y)
	var local_angles:=Vector3(clampf(world.pitch+kick.x,-1.4,1.4),kick.y,kick.z)
	world.camera.global_transform=Transform3D(yaw*Basis.from_euler(local_angles),foot+yaw*(Vector3(0,1.62,0)+eye_offset))
	world.camera.fov=lens

func physics_pose() -> void:
	apply_pose(world.player.global_position,world.feedback.camera_offset,world.feedback.camera_rotation+Vector3(world.firearms.recoil.x,world.firearms.recoil.y,0),75+world.feedback.grab_blend*1.5)

func render(alpha: float) -> void:
	if not ready:return
	alpha=clampf(alpha,0,1)
	apply_pose(previous_position.lerp(position,alpha),previous_offset.lerp(offset,alpha),previous_force.lerp(force,alpha),lerpf(previous_fov,fov,alpha))
