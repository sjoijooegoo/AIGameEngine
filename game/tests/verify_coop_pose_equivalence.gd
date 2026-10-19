extends SceneTree
## Differential calculation check against a preserved pre-optimization actor.
## Fixture states here test math only; normal combat is verified separately.
var reference_dir: String
var compared := 0
var max_error := 0.0
var authority_only := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference-dir="):reference_dir=arg.trim_prefix("--reference-dir=")
		if arg=="--authority-only":authority_only=true
	assert(not reference_dir.is_empty());run.call_deferred()

func compare(a: Transform3D,b: Transform3D) -> void:
	var error:=maxf(a.origin.distance_to(b.origin),maxf(a.basis.x.distance_to(b.basis.x),maxf(a.basis.y.distance_to(b.basis.y),a.basis.z.distance_to(b.basis.z))))
	max_error=maxf(max_error,error);compared+=1
	assert(error<.00002,"Pose/hitbox math diverged: "+str(error))

func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.testing=true
	game.ensure_infected()
	game.player.position=Vector3(18,.04,19)
	var visited: Dictionary={}
	for actor in game.infected:
		if visited.has(actor.definition.model):continue
		visited[actor.definition.model]=true
		var reference=load(reference_dir.path_join("infected.gd")).new();game.add_child(reference)
		reference.setup(game,actor.definition,actor.stats,game.infected_data.pins[actor.definition.model])
		actor.configure_authority(authority_only)
		for value in [actor,reference]:
			value.position=Vector3(18,.04,15);value.rotation.y=.5;value.clock=0;value.state_time=0;value.last_sample_time=-1;value.native_motion.reset();value.pose_blend.reset();value.animation_name="";value.reaction_time=10;value.reactions.reset();value.play_pose(0)
			value.collision_mask=1;value.velocity=Vector3.DOWN
			for settle in 12:
				await physics_frame;value.velocity=Vector3.DOWN;value.move_and_slide()
			assert(value.is_on_floor(),"Foot IK fixture must have physical floor contact")
		for state in ["idle","chase","attack","grab","hurt","flinch","return"]:
			var mode: String="hurt" if state=="flinch" else state
			for frame in 36:
				for value in [actor,reference]:
					value.mode=mode;value.clock+=1.0/60;value.state_time=float(frame)/60;value.reaction_time=float(frame)/60 if mode=="hurt" else 10.0
					value.strong_reaction=state=="hurt";value.reaction_strength=.8;value.velocity=Vector3(.7,0,.5) if mode in ["chase","return"] else Vector3.ZERO
					value.position+=value.velocity/60;value.play_pose(1.0/60,true)
				for bone in (actor.authority_bones if authority_only else range(actor.skeleton.get_bone_count())):compare(actor.skeleton.get_bone_global_pose(bone),reference.skeleton.get_bone_global_pose(bone))
				compare(actor.head_hitbox.global_transform,reference.head_hitbox.global_transform)
				for part in actor.ragdoll.hitboxes:
					compare(actor.ragdoll.hitboxes[part].global_transform,reference.ragdoll.hitboxes[part].global_transform)
					assert(absf(actor.ragdoll.hit_shapes[part].height-reference.ragdoll.hit_shapes[part].height)<.00002)
		# Identical imposed joint poses isolate the corpse-to-skeleton projection
		# from the solver. This is fixture math, not evidence of a player kill.
		actor.configure_authority(false) # Single-player/client joint math stays exact.
		for value in [actor,reference]:value.ragdoll.start(Vector3.ZERO,value.position)
		for frame in 20:
			for value in [actor,reference]:
				for i in value.ragdoll.positions.size():value.ragdoll.positions[i]+=Vector3(.001*sin(i+frame),-.002,.001*cos(i-frame))
				value.ragdoll.apply_pose();value.ragdoll.update_hitboxes()
			for bone in actor.skeleton.get_bone_count():compare(actor.skeleton.get_bone_global_pose(bone),reference.skeleton.get_bone_global_pose(bone))
			for part in actor.ragdoll.hitboxes:compare(actor.ragdoll.hitboxes[part].global_transform,reference.ragdoll.hitboxes[part].global_transform)
		# The solver itself, including floor collision and all joint passes,
		# must retain the same particle positions/velocities after loop typing.
		for frame in 90:
			actor.ragdoll.advance(1.0/60);reference.ragdoll.advance(1.0/60)
			assert(actor.ragdoll.sleeping==reference.ragdoll.sleeping)
			for i in actor.ragdoll.positions.size():
				assert(actor.ragdoll.positions[i].distance_to(reference.ragdoll.positions[i])<.00002)
				assert(actor.ragdoll.previous[i].distance_to(reference.ragdoll.previous[i])<.00002)
			for part in actor.ragdoll.hitboxes:compare(actor.ragdoll.hitboxes[part].global_transform,reference.ragdoll.hitboxes[part].global_transform)
		reference.free()
	print("BANK_POSE_EQUIVALENCE_PASS models=",visited.size()," transform_comparisons=",compared," max_error=",max_error)
	quit()
