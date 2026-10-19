extends "bank_coop_driver.gd"
## Read-only local debug inspection; all shooting still enters normal input.
func execute(request: Dictionary) -> void:
	if request.command!="pose_state":super.execute(request);return
	var actors: Array=[]
	for actor in game.world.infected:
		if not actor.active:continue
		var targets: Dictionary={}
		for part in actor.ragdoll.hitboxes:
			var point: Vector3=actor.ragdoll.hitboxes[part].global_position
			targets[part]=[point.x,point.y,point.z]
		var head: Vector3=actor.head_hitbox.global_position;targets.Head=[head.x,head.y,head.z]
		actors.append({"id":str(actor.name),"mode":actor.mode,"sleeping":actor.ragdoll.sleeping,"wake_count":actor.ragdoll.wake_count,"targets":targets,"replica":actor.replica_only,"hit_layer":actor.ragdoll.hitboxes.Body.collision_layer,
			"authority_proxy":actor.ragdoll.authority_proxy!=null,"local_corpse":actor.ragdoll.corpse_stream.received,
			"corpse_revision":actor.ragdoll.corpse_stream.state.get("revision",0),"impacts":actor.ragdoll.impact_count})
	var camera: Vector3=game.world.camera.global_position
	write_json("response.json",{"id":request.id,"result":{"actors":actors,"camera":[camera.x,camera.y,camera.z],"presentation":game.presentation.observe()}});busy=false
