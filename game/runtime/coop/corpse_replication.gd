extends RefCounted
## Durable, immutable death seed + bounded cosmetic impulse history. A lost
## snapshot can delay a visual effect, never undo death or change combat.
const MAX_IMPACTS := 6
var state: Dictionary={}
var received := false
var received_impact := 0
var accumulator := 0.0

func reset() -> void:
	state={};received=false;received_impact=0;accumulator=0

func death(body) -> void:
	state={"revision":1,"seed":{"origin":body.actor.global_position,"yaw":body.actor.rotation.y,
		"points":body.positions.duplicate(),"previous":body.previous.duplicate(),
		"launch_velocity":body.launch_velocity,"launch_remaining":body.launch_remaining,
		"launch_cap":body.launch_cap,"launch_kind":body.launch_kind},"impacts":[]}

func impact(part: String,direction: Vector3,point: Vector3,info: Dictionary) -> void:
	var events: Array=state.impacts.duplicate()
	# Exclude shot metadata, other actors and per-pellet diagnostics from the wire.
	var effect: Dictionary={}
	for key in ["weapon","blast","total_pellets","finisher"]:
		if info.has(key):effect[key]=info[key]
	events.append({"serial":int(state.revision),"part":part,"direction":direction,"point":point,"info":effect})
	while events.size()>MAX_IMPACTS:events.pop_front()
	state=state.duplicate();state.revision+=1;state.impacts=events;state.erase("rest")

func rest(center: Vector3,rotation: Basis) -> void:
	state=state.duplicate();state.revision+=1;state.rest={"center":center,"rotation":rotation}

func receive(body,packet: Dictionary) -> void:
	if packet.is_empty():return
	if not received:
		var seed: Dictionary=packet.seed
		body.actor.global_position=seed.origin;body.actor.rotation.y=seed.yaw
		body.start(Vector3.ZERO,seed.origin)
		if seed.points.size()!=body.positions.size():return
		body.positions.assign(seed.points);body.previous.assign(seed.previous)
		body.launch_velocity=seed.launch_velocity;body.launch_remaining=seed.launch_remaining
		body.launch_cap=seed.launch_cap;body.launch_kind=seed.launch_kind
		if packet.has("rest"):
			# Late join: seed near the coarse resting location once, then let the
			# local joints settle. Existing clients never snap to a server pose.
			var center: Vector3=(body.positions[body.ids.Pelvis]+body.positions[body.ids.Spine2])*.5
			for i in body.positions.size():body.positions[i]=packet.rest.center+packet.rest.rotation*(body.positions[i]-center)
			body.previous=body.positions.duplicate();body.launch_remaining=0
			received_impact=int(packet.revision)-1
		body.apply_pose();received=true
	for event in packet.impacts:
		if int(event.serial)<=received_impact:continue
		body.impulse(event.part,event.direction,event.point,event.info)
		received_impact=int(event.serial)

func advance(body,dt: float) -> void:
	if not received or body.sleeping:return
	# Rendering cadence never changes solver speed; bound work after a hitch.
	accumulator=minf(accumulator+dt,8.0/60.0)
	while accumulator>=1.0/60.0:
		body.advance(1.0/60.0);accumulator-=1.0/60.0
