extends SceneTree
class Body extends RefCounted:
	var actor:=Node3D.new()
	var positions: Array[Vector3]=[Vector3.UP,Vector3.UP*2]
	var previous: Array[Vector3]=[Vector3.UP-Vector3.RIGHT/60,Vector3.UP*2-Vector3.RIGHT/60]
	var ids: Dictionary={"Pelvis":0,"Spine2":1}
	var launch_velocity:=Vector3.RIGHT
	var launch_remaining:=.5
	var launch_cap:=5.0
	var launch_kind:="shotgun_death"
	var sleeping:=false
	var active:=false
	var impulses:=0
	var steps:=0
	func start(_push: Vector3,_point: Vector3) -> void:active=true
	func apply_pose() -> void:pass
	func impulse(_part: String,_direction: Vector3,_point: Vector3,_info: Dictionary) -> void:impulses+=1
	func advance(dt: float) -> void:assert(dt==1.0/60.0);steps+=1
class Replica extends CharacterBody3D:
	var replica_only:=true
class ProxyActor extends Node3D:
	var game: Dictionary={"firearms":{"feedback_data":{"shotgun":{"air_drag":1.7}}}}
class ProxyBody extends Body:
	var age:=0.0
	var frame_contacts:=0
	var frame_wall_contact:=false
	var frame_floor_contact:=false
	var quiet_time:=0.0
	var sleep_reason:=""
	var max_speed:=0.0
	var queries:=0
	var hitbox_updates:=0
	var corpse_stream=preload("res://coop/corpse_replication.gd").new()
	func add_point(_name: String,point: Vector3,_radius: float) -> void:
		positions.append(point);previous.append(point)
	func speed_limit() -> float:return launch_cap
	func collide(i: int,_old: Vector3) -> void:
		queries+=1
		if positions[i].y<=.28:
			positions[i].y=.28;previous[i]=positions[i];frame_contacts=1;frame_floor_contact=true
	func collide_living(_before: Array[Vector3],_dt: float) -> void:pass
	func update_hitboxes() -> void:hitbox_updates+=1

func _initialize() -> void:run.call_deferred()
func run() -> void:
	var codec=preload("res://coop/corpse_replication.gd").new()
	var body:=Body.new();root.add_child(body.actor)
	codec.death(body);var death: Dictionary=codec.state
	var client=preload("res://coop/corpse_replication.gd").new()
	var replica:=Body.new();root.add_child(replica.actor)
	client.receive(replica,death);assert(replica.active and replica.positions==body.positions)
	codec.impact("Body",Vector3.RIGHT,Vector3.UP,{"weapon":"shotgun","blast":1.0,"private":"excluded"})
	assert(death.revision==1 and death.impacts.is_empty(),"A baseline was mutated")
	codec.impact("Head",Vector3.LEFT,Vector3.UP,{"weapon":"pistol"})
	# Drop the first impulse snapshot, then recover both exactly once.
	client.receive(replica,codec.state);client.receive(replica,codec.state)
	assert(replica.impulses==2 and not codec.state.impacts[0].info.has("private"))
	var before: Dictionary=codec.state
	codec.rest(Vector3(3,.28,0),Basis(Vector3.RIGHT,PI/2))
	assert(not before.has("rest"))
	var late=preload("res://coop/corpse_replication.gd").new();var late_body:=Body.new();root.add_child(late_body.actor)
	late.receive(late_body,codec.state);late.receive(late_body,codec.state)
	assert(late_body.impulses==0 and late_body.launch_remaining==0)
	assert(((late_body.positions[0]+late_body.positions[1])*.5).is_equal_approx(Vector3(3,.28,0)))
	client.advance(replica,1.0);assert(replica.steps==8,"Hitch catch-up must be bounded")
	for i in 20:codec.impact("Body",Vector3.RIGHT,Vector3.ZERO,{})
	assert(codec.state.impacts.size()==codec.MAX_IMPACTS)
	var real_body=preload("res://scripts/infected_ragdoll.gd").new()
	var actor:=Replica.new();root.add_child(actor);real_body.actor=actor
	real_body.collide_living([],1.0/60) # Must return without consulting AI/targets.
	client.reset();assert(not client.received and client.received_impact==0)
	var proxy=preload("res://scripts/corpse_proxy.gd").new();var proxy_body:=ProxyBody.new()
	proxy_body.actor.free();proxy_body.actor=ProxyActor.new();root.add_child(proxy_body.actor)
	for i in 62:proxy_body.positions.append(Vector3.UP);proxy_body.previous.append(Vector3.UP)
	proxy_body.corpse_stream.death(proxy_body);proxy.setup(proxy_body)
	var frames:=0
	for i in 180:
		proxy.advance(proxy_body,1.0/60);frames+=1
		if proxy_body.sleeping:break
	assert(proxy_body.sleeping and proxy_body.corpse_stream.state.has("rest"))
	assert(proxy_body.queries==frames and proxy_body.hitbox_updates==frames,"One particle collision update per awake body, independent of joint count")
	proxy.wake(proxy_body)
	print("BANK_CORPSE_EVENTS_PASS immutable / loss / duplicate / late join / bounded / visual authority")
	quit()
