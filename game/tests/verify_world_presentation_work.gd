extends SceneTree
class Body extends RefCounted:
	var positions: Array[Vector3]=[Vector3.ZERO,Vector3.UP]
	var samples := 0
	var fitting := 0
	var anatomy: Dictionary={"current_basis":Basis.IDENTITY}
	func apply_pose() -> void:
		samples+=1
		if fitting>0:anatomy.current_basis=Basis(Vector3.UP,float(fitting)*.1);fitting-=1
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
	actor.mode="dead";row=row.duplicate(true);row[5]="dead";row[9]=[Vector3.ZERO,Vector3.UP]
	presentation.push(18,{"doors":{},"enemies":[row]});presentation.render_tick=18;presentation.advance(1.0/60)
	var samples:=actor.ragdoll.samples
	for i in 60:presentation.advance(1.0/60)
	assert(actor.ragdoll.samples==samples and presentation.corpse_skipped==60)
	row=row.duplicate(true);row[9][0]=Vector3.RIGHT
	presentation.push(24,{"doors":{},"enemies":[row]});presentation.render_tick=24;presentation.advance(1.0/60)
	assert(actor.ragdoll.samples==samples+1 and actor.ragdoll.positions[0]==Vector3.RIGHT,"Wake pose was incorrectly skipped")
	row=row.duplicate(true);row[9][0]=Vector3(2,0,0);actor.ragdoll.fitting=3
	presentation.push(30,{"doors":{},"enemies":[row]});presentation.render_tick=30
	samples=actor.ragdoll.samples
	for i in 20:presentation.advance(1.0/60)
	assert(actor.ragdoll.fitting==0 and actor.ragdoll.samples==samples+4,"Static joint points must not freeze an unconverged torso fit")
	presentation.reset();assert(presentation.settled_poses.is_empty())
	print("BANK_PRESENTATION_WORK_PASS hidden / reactivation / sleeping / wake / reset")
	quit()
