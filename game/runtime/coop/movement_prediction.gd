extends RefCounted
## Local collision prediction, corrected against the server's consumed sequence.
## History is bounded; damage, grabs, doors and legal positions stay authoritative.
const LIMIT := 120
var history: Array=[]
var correction := Vector3.ZERO
var last_error := 0.0
var corrections := 0
var last_ack := -1
var replay_steps := 0

func reset() -> void:
	history.clear();correction=Vector3.ZERO;last_error=0;last_ack=-1;replay_steps=0

func advance(body: CharacterBody3D,serial: int,move: Vector2,look: float,run: bool,dt: float,allowed: bool) -> void:
	body.axes=move if allowed else Vector2.ZERO;body.rotation.y=look;body.running=run
	body.last_input_tick=serial;body.simulate(dt,serial)
	history.append({"seq":serial,"move":body.axes,"yaw":look,"run":run,"position":body.position,"velocity":body.velocity})
	while history.size()>LIMIT:history.pop_front()
	correction=correction.lerp(Vector3.ZERO,1.0-exp(-dt*14.0))

func reconcile(body: CharacterBody3D,row: Dictionary) -> void:
	var ack: int=row.ack
	if ack<last_ack:return
	last_ack=ack
	var before: Vector3=body.position
	var acknowledged: Dictionary={}
	while not history.is_empty() and int(history[0].seq)<=ack:acknowledged=history.pop_front()
	if acknowledged.get("seq",-2)==ack and Vector3(acknowledged.position).distance_squared_to(row.position)<.000001 and Vector3(acknowledged.velocity).distance_squared_to(row.velocity)<.0001:
		body.target_position=row.position;body.last_sequence=ack;last_error=0;return
	body.position=row.position;body.velocity=row.velocity
	# move_and_slide uses the fixed 60 Hz physics delta, exactly as the server.
	for command in history:
		replay_steps+=1
		body.axes=command.move;body.rotation.y=command.yaw;body.running=command.run
		body.last_input_tick=command.seq;body.simulate(1.0/60.0,command.seq)
		command.position=body.position;command.velocity=body.velocity
	last_error=before.distance_to(body.position)
	if last_error>.01:corrections+=1
	if last_error<1.5:correction+=before-body.position
	else:correction=Vector3.ZERO
	correction=correction.limit_length(.75)
	body.target_position=row.position;body.last_sequence=ack

func observe() -> Dictionary:
	return {"pending":history.size(),"error":last_error,"corrections":corrections,"ack":last_ack,"replay_steps":replay_steps}
