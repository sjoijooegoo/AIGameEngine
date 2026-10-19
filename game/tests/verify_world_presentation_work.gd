extends SceneTree
class Body extends RefCounted:
	var positions: Array[Vector3]=[Vector3.ZERO,Vector3.UP]
	var samples := 0
	var sleeping := false
	var corpse_stream=Stream.new()
class Stream extends RefCounted:
	func advance(body,dt: float) -> void:
		assert(is_equal_approx(dt,1.0/60.0));body.samples+=1
class Actor extends Node3D:
	var active := false
	var mode := "idle"
	var clock := 0.0
	var state_time := 0.0
	var reaction_time := 0.0
	var samples := 0
	var ragdoll:=Body.new()
	var native_motion: Dictionary={"previous_position":Vector3.ZERO}
	func play_pose(_dt: float,_continuous: bool=false) -> void:samples+=1
	func update_shadow_layers() -> void:pass
class World extends Node3D:
	var infected: Array=[]
	var doors: Dictionary={}
	var player:=Node3D.new()

func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=World.new();root.add_child(world);world.add_child(world.player)
	var actor:=Actor.new();actor.name="enemy";world.add_child(actor);world.infected=[actor]
	var presentation=preload("res://coop/world_presentation.gd").new();presentation.world=world
	var row: Array=["enemy",Vector3.ZERO,0.0,Vector3.ZERO,65.0,"idle",0.0,0.0,false,[]]
	presentation.push(6,{"doors":{},"enemies":[row]})
	for i in 12:presentation.advance(1.0/60)
	assert(actor.samples==0 and presentation.hidden_skipped==12)
	actor.active=true;row=row.duplicate(true);row[8]=true;row[1]=Vector3(2,0,0)
	presentation.push(12,{"doors":{},"enemies":[row]});presentation.render_tick=12;presentation.advance(1.0/60)
	assert(actor.samples==1 and actor.position==Vector3(2,0,0))
	actor.mode="dead";row=row.duplicate(true);row[5]="dead";row[9]={"revision":1}
	presentation.push(18,{"doors":{},"enemies":[row]});presentation.render_tick=18;presentation.advance(1.0/60)
	var samples:=actor.ragdoll.samples
	actor.ragdoll.sleeping=true
	for i in 60:presentation.advance(1.0/60)
	assert(actor.ragdoll.samples==samples and presentation.corpse_skipped==60)
	actor.ragdoll.sleeping=false
	row=row.duplicate(true);row[9]={"revision":2};row[1]=Vector3(99,0,0)
	presentation.push(24,{"doors":{},"enemies":[row]});presentation.render_tick=24;presentation.advance(1.0/60)
	assert(actor.ragdoll.samples==samples+1,"Local wake was incorrectly skipped")
	assert(actor.position==Vector3(2,0,0) and actor.ragdoll.positions[0]==Vector3.ZERO,"Snapshots must not overwrite a local corpse")
	presentation.reset();assert(presentation.settled_poses.is_empty())
	print("BANK_PRESENTATION_WORK_PASS hidden / reactivation / sleeping / wake / reset")
	quit()
