extends CharacterBody3D
## Native skins and retail ANI motion, contact-aware combat and intact ragdolls.
var game: Node3D
var definition: Dictionary
var stats: Dictionary
var home: Vector3
var hp := 65.0
var mode := "idle"
var state_time := 0.0
var animation_time := 0.0
var animation_name := "idle"
var animator: AnimationPlayer
var model: Node3D
var skeleton: Skeleton3D
var clock := 0.0
var cooldown := 0.0
var lost_time := 0.0
var stagger := 0.0
var hit_applied := false
var path := PackedVector3Array()
var path_index := 0
var path_timer := 0.0
var nav_revision := -1
var detection := false
var active := true
var anchored := false
var spawn_adjustment := Vector3.ZERO
var hit_count := 0
var speed := 1.0
var head_hitbox: Area3D
var head_bone := -1
var pose_blend=preload("res://scripts/pose_transition.gd").new()
var last_sample_time := -1.0
var reaction_time := 10.0
var reaction_duration := .4
var reaction_zone := "chest"
var reaction_direction := "front"
var reaction_vector := Vector3.BACK
var reaction_strength := 0.0
var reaction_serial := 0
var strong_reaction := false
var base_pose: Array[Transform3D]=[]
var locomotion_recovery := 0.0
var collision_radius := .34
var bone_ids: Dictionary={}
var fixture_facing_locked := false
var ragdoll=preload("res://scripts/infected_ragdoll.gd").new()
var animation_origin := "project_authored"
var resting_position := Vector3.INF
var resting_nav_revision := -1
var render_meshes: Array=[]
var shadow_layers := 0
var pending_dt := 0.0
var pending_pose_dt := 0.0
var last_pose_tick := -1
var last_sight_tick := -1
var sight_revision := -1
var sight_origin := Vector3.INF
var sight_target := Vector3.INF
var sight_result := false
var sight_query := PhysicsRayQueryParameters3D.new()
var priority_tick := -1
var priority_result := false
var motion_profile: Dictionary={}
var attack_serial := 0
var native_motion=preload("res://scripts/infected_native_motion.gd").new()
var reactions=preload("res://scripts/infected_reactions.gd").new()
var body_collision_count := 0
var last_body_collision: Dictionary={}
const ARCHETYPES=preload("res://scripts/infected_archetypes.gd")

func setup(world: Node3D,source: Dictionary,type: Dictionary,pin: Dictionary) -> void:
	game=world;definition=source.duplicate(true);stats=type.duplicate(true)
	motion_profile=world.infected_profiles[source.type].duplicate(true)
	name=source.id;home=Vector3(source.position[0],source.position[1],source.position[2]);position=home+Vector3.UP*.04
	rotation.y=source.yaw;hp=float(stats.hp)*float(source.options.get("hpMul",1))
	speed=(float(stats.speed[0])+float(stats.speed[1]))*.5
	anchored=source.options.get("stairCrowd",false) or source.options.get("outside",false)
	collision_layer=8;collision_mask=11;floor_snap_length=.40;floor_max_angle=deg_to_rad(48)
	# Limit dense crowd contact resolution to three sweeps per tick; unresolved
	# motion waits for the next tick instead of six repeated crowd sweeps.
	max_slides=3
	var c:=CollisionShape3D.new();var shape:=CapsuleShape3D.new()
	collision_radius=minf(.48,float(stats.r))
	shape.radius=collision_radius;shape.height=1.58*float(motion_profile.visual_scale)
	c.shape=shape;c.position.y=shape.height*.5+.01;add_child(c)
	model=(load(pin.resource) as PackedScene).instantiate();add_child(model)
	model.scale=Vector3.ONE*float(motion_profile.visual_scale)
	var origin:=model.find_child("ActorOrigin",true,false) as Node3D
	assert(origin,"Infected asset lost canonical foot origin")
	model.position-=to_local(origin.global_position)
	animator=model.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	skeleton=model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	pose_blend.setup([skeleton])
	for bone in skeleton.get_bone_count():
		bone_ids[str(skeleton.get_bone_name(bone)).trim_prefix("ValveBiped.Bip01_")]=bone
	base_pose.resize(skeleton.get_bone_count())
	sight_query.collision_mask=3;sight_query.exclude=[get_rid()]
	head_bone=skeleton.find_bone("ValveBiped.Bip01_Head1")
	assert(head_bone>=0,"Infected has no native head bone")
	head_hitbox=Area3D.new();head_hitbox.name="HeadHitbox";head_hitbox.collision_layer=16;head_hitbox.collision_mask=0;head_hitbox.monitoring=false
	head_hitbox.set_meta("shot_owner",self);add_child(head_hitbox)
	var head_shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=float(motion_profile.head_radius)*float(motion_profile.visual_scale);head_shape.shape=sphere;head_hitbox.add_child(head_shape)
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in ["idle","walk","run","attack","hurt","death"]:assert(animator.has_animation(clip))
	native_motion.setup(self)
	reactions.setup(self)
	animation_origin="l4d2_retail_mdl_ani"
	ragdoll.setup(self)
	render_meshes=model.find_children("*","MeshInstance3D",true,false)
	for mesh in render_meshes:mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	update_shadow_layers()
	play_pose(0)

func update_shadow_layers() -> void:
	var low: float=global_position.y
	var high: float=low+2.1*model.scale.y
	if mode=="dead" and not ragdoll.positions.is_empty():
		low=INF;high=-INF
		for point: Vector3 in ragdoll.positions:low=minf(low,point.y-.15);high=maxf(high,point.y+.15)
	var layers:=0
	for level in range(clampi(floori((low+.02)/3.6),0,3),clampi(floori((high-.02)/3.6),0,3)+1):layers|=1 << (level+1)
	if layers==shadow_layers:return
	shadow_layers=layers
	for mesh: MeshInstance3D in render_meshes:preload("res://scripts/render_layers.gd").assign(mesh,layers)

func set_mode(value: String) -> void:
	if mode==value:return
	mode=value;state_time=0;hit_applied=false
	if value=="attack":attack_serial+=1
	if value in ["attack","grab","dead"]:game.infected_audio.request(self,"death" if value=="dead" else value)

func sees_player() -> bool:
	var delta: Vector3=game.player.global_position-global_position
	if absf(delta.y)>1.6 or delta.length()>float(stats.notice):return false
	var eye:=global_position+Vector3.UP*1.48
	sight_query.from=eye;sight_query.to=game.player.global_position+Vector3.UP*1.0
	game.profiler.count("sight_rays")
	var hit:=get_world_3d().direct_space_state.intersect_ray(sight_query)
	return not hit.is_empty() and hit.collider==game.player

func priority_target() -> bool:
	if priority_tick==game.tick_count:return priority_result
	priority_tick=game.tick_count
	priority_result=global_position.distance_squared_to(game.player.global_position)<=16
	if not priority_result:
		# A conservative full-body bound covers head, torso and leg aiming, even
		# while the previous pose is held. A head-only cone misses aimed limbs.
		var visual_scale: float=motion_profile.visual_scale
		var offset: Vector3=global_position+Vector3.UP*.85*visual_scale-game.camera.global_position
		var depth: float=offset.dot(-game.camera.global_basis.z)
		var margin: float=maxf(.95*visual_scale,depth*.0875)
		priority_result=depth>0 and offset.length_squared()-depth*depth<=margin*margin
	return priority_result

func perceive_player() -> bool:
	var interval:=6 if global_position.distance_squared_to(game.player.global_position)>144 else 3
	var critical: bool=priority_target() or mode in ["hurt","attack","grab"] or reaction_time<reaction_duration
	var invalid: bool=last_sight_tick<0 or sight_revision!=game.navigation.revision or sight_origin.distance_squared_to(global_position)>.25 or sight_target.distance_squared_to(game.player.global_position)>.25
	if critical or invalid or game.tick_count-last_sight_tick>=interval or game.tick_count%interval==get_index()%interval:
		sight_result=sees_player();last_sight_tick=game.tick_count;sight_revision=game.navigation.revision
		sight_origin=global_position;sight_target=game.player.global_position
	else:game.profiler.count("sight_deferred")
	return sight_result

func reset_scheduling() -> void:
	pending_dt=0;pending_pose_dt=0;last_pose_tick=-1;last_sight_tick=-1
	sight_revision=-1;sight_origin=Vector3.INF;sight_target=Vector3.INF;sight_result=false
	priority_tick=-1;priority_result=false

func advance(dt: float) -> void:
	if not active:return
	game.profiler.count("active_actors")
	pending_dt+=dt
	# Full rate within 12 m, plus all hurt/attack/grab/death states. Distant
	# locomotion is 30 Hz, with accumulated simulation time (no slower enemies).
	if mode in ["idle","chase","return"] and reaction_time>=reaction_duration and global_position.distance_squared_to(game.player.global_position)>144 and not priority_target() and game.tick_count%2!=get_index()%2 and game.tick_count>3:
		game.profiler.count("distant_updates_deferred");return
	dt=pending_dt;pending_dt=0
	update_shadow_layers()
	clock+=dt;state_time+=dt;reaction_time+=dt;cooldown=maxf(0,cooldown-dt);path_timer-=dt
	if mode=="dead":
		var started: int=game.profiler.mark()
		game.profiler.count("sleeping_corpses" if ragdoll.sleeping else "awake_corpses")
		ragdoll.advance(dt)
		game.profiler.end_scope("ragdoll",started);return
	var target: Vector3=game.player.global_position
	var delta:=target-global_position;var flat:=Vector2(delta.x,delta.z).length()
	var detected: bool=not game.player_dead and perceive_player()
	if detected and not detection:game.infected_audio.request(self,"alert")
	detection=detected
	if mode=="grab":
		if game.feedback.grabber!=self:set_mode("hurt");stagger=.5
		else:
			rotation.y=atan2(-delta.x,-delta.z)
			var forward:=Vector3(delta.x,0,delta.z).normalized()
			velocity=forward*clampf((flat-.84)*5,0,.6);velocity.y=-1 if is_on_floor() else velocity.y-20*dt
			advance_movement(dt);play_pose(dt);return
	if stagger>0:
		stagger-=dt;set_mode("hurt")
		velocity.x=move_toward(velocity.x,0,dt*4);velocity.z=move_toward(velocity.z,0,dt*4)
	elif mode=="attack":
		velocity.x=0;velocity.z=0
		if state_time>=float(motion_profile.contact) and not hit_applied:
			hit_applied=true
			if detection and flat<float(stats.reach)+.3 and absf(delta.y)<.8:
				if bool(stats.get("grab",false)) and game.feedback.start_grab(self):play_pose(dt);return
				if not game.feedback.is_grabbed():game.hurt_player(float(stats.dmg),str(definition.id),global_position)
			else:game.infected_audio.request(self,"miss")
		if state_time>=float(motion_profile.duration):set_mode("chase" if detection else "idle");cooldown=float(motion_profile.cooldown)
	else:
		if mode=="hurt":set_mode("chase" if detection and not anchored else "idle")
		if detection:
			lost_time=0
			if flat<float(stats.reach)+.15 and absf(delta.y)<.8 and cooldown<=0 and not game.feedback.is_grabbed():set_mode("attack")
			elif not anchored:set_mode("chase")
		else:
			lost_time+=dt
			if game.player_dead or lost_time>4:set_mode("return" if global_position.distance_to(home)>1.0 and not anchored else "idle")
		velocity.x=0;velocity.z=0
		if mode in ["chase","return"]:
			var goal: Vector3=home if mode=="return" else target
			if (path_timer<=0 or nav_revision!=game.navigation.revision) and game.navigation.can_route():
				path=game.navigation.route(global_position,goal);path_index=0;path_timer=.8;nav_revision=game.navigation.revision
			while path_index<path.size() and Vector2(path[path_index].x-global_position.x,path[path_index].z-global_position.z).length()<.22:path_index+=1
			if path_index<path.size():
				var direction: Vector3=path[path_index]-global_position;direction.y=0;direction=direction.normalized()
				var recover: float=1.0-smoothstep(0,float(game.firearms.feedback_data.pistol.recovery_blend),locomotion_recovery)
				velocity.x=direction.x*speed*recover;velocity.z=direction.z*speed*recover
				rotation.y=lerp_angle(rotation.y,atan2(-direction.x,-direction.z),minf(1,dt*8))
			if mode=="return" and global_position.distance_to(home)<.7:set_mode("idle")
		locomotion_recovery=maxf(0,locomotion_recovery-dt)
		if detection and mode in ["idle","attack"] and not fixture_facing_locked:rotation.y=atan2(-delta.x,-delta.z)
	# Small planar separation keeps crowds from all steering through one point;
	# normal move_and_slide still owns wall, floor, player and actor contacts.
	if mode in ["chase","return"]:
		var separation_started: int=game.profiler.mark()
		var separation:=Vector3.ZERO
		var neighbours: Array=game.crowd.neighbours(self)
		game.profiler.count("neighbour_candidates",neighbours.size())
		var origin:=global_position
		for other in neighbours:
			if other==self or not other.active or other.mode=="dead":continue
			var apart: Vector3=origin-other.global_position
			if absf(apart.y)>.65:continue
			apart.y=0
			var radius: float=collision_radius+other.collision_radius+.10
			if apart.length_squared()>=radius*radius:continue
			var length:=apart.length()
			if length>.01 and length<radius:separation+=apart/length*(1-length/radius)
		separation=separation.limit_length(.65)
		velocity+=separation
		game.profiler.end_scope("separation",separation_started)
	velocity.y=-1 if is_on_floor() else velocity.y-20*dt
	# CharacterBody3D is kinematic: an idle body resting on unchanged static
	# support does not need the same sweep again. Keep perception/animation at
	# 60 Hz; wake immediately for movement, displacement or a door revision.
	var resting: bool=mode=="idle" and is_on_floor() and Vector2(velocity.x,velocity.z).length_squared()<.000001 and global_position.is_equal_approx(resting_position) and resting_nav_revision==game.navigation.revision
	var movement_started: int=game.profiler.mark()
	if not resting or game.tick_count<=3 or game.tick_count%12==get_index()%12:
		advance_movement(dt);game.profiler.count("movement_sweeps")
	else:game.profiler.count("resting_sweeps_skipped")
	resting_position=global_position;resting_nav_revision=game.navigation.revision
	game.profiler.end_scope("movement",movement_started)
	play_pose(dt)

func advance_movement(dt: float) -> void:
	# move_and_slide uses the engine's 60 Hz delta, so scale velocity for a
	# deferred 30 Hz step and restore its physical units after collision response.
	var factor: float=dt*Engine.physics_ticks_per_second
	velocity*=factor;move_and_slide();velocity/=factor

func receive_hit(damage: float,push: Vector3,info: Dictionary={}) -> void:
	if not active:return
	var weapon: String=info.get("weapon","melee")
	var part: String=info.get("part","Head" if info.get("head",false) else "Body")
	if mode=="dead":
		ragdoll.impulse(part,info.get("direction",push.normalized()),info.get("point",ragdoll.point("Spine2")),info)
		if info.get("head_burst",false):ragdoll.destroy_head()
		return
	var point: Vector3=info.get("point",global_position+Vector3.UP*1.1)
	var soft_body: bool=weapon=="pistol" and not info.get("head",false)
	var push_speed:=0.0
	var hit_stagger:=0.0
	var preserve_reaction: bool=soft_body and stagger>0 and reaction_time<reaction_duration
	if not preserve_reaction:
		strong_reaction=weapon in ["shotgun","shove","melee","baton","body_collision"]
		reaction_time=0;reaction_duration=.55 if strong_reaction else .30;reaction_serial+=1
		if weapon=="baton" and info.get("finisher",false):reaction_duration=.72
		reaction_vector=(global_basis.orthonormalized().inverse()*push).normalized()
		reaction_direction=("right" if reaction_vector.x<0 else "left") if absf(reaction_vector.x)>.6 else "front" if reaction_vector.z>0 else "back"
		reaction_zone="head" if info.get("head",false) else "arm_left" if part=="ArmL" else "arm_right" if part=="ArmR" else "leg_left" if part=="LegL" else "leg_right" if part=="LegR" else "abdomen" if ragdoll.hitboxes.Body.to_local(point).y<0 else "chest"
		reaction_strength=(1.0 if strong_reaction else .55)*(.65 if stats.get("heavy",false) else 1.0)*float(motion_profile.reaction_gain)
		push_speed=push.length()*(2.5 if strong_reaction else 1.4)*float(motion_profile.push_gain)
		hit_stagger=.55 if strong_reaction else .10 if stats.get("heavy",false) else .18
		if weapon=="pistol":
			var tuning: Dictionary=game.firearms.feedback_data.pistol
			var head: bool=info.get("head",false)
			push_speed=float(tuning.head_push_speed if head else tuning.body_push_speed)*float(motion_profile.push_gain)
			hit_stagger=float(tuning.head_stagger if head else tuning.body_stagger)
			reaction_strength=float(tuning.head_reaction if head else tuning.body_reaction)*float(motion_profile.reaction_gain)
			reaction_duration=.42 if head else .20
		elif weapon=="shotgun":
			var tuning: Dictionary=game.firearms.feedback_data.shotgun
			var blast: float=info.get("blast",0)
			push_speed=lerpf(1.3,float(tuning.live_push_speed),blast)*float(motion_profile.push_gain)
			hit_stagger=lerpf(.28,float(tuning.live_stagger),blast)
			reaction_strength=lerpf(.65,1.35,blast)*float(motion_profile.reaction_gain)
		elif weapon=="body_collision":
			push_speed=float(info.speed)*float(motion_profile.push_gain)
			hit_stagger=.65;reaction_duration=.65
			reaction_strength=clampf(push_speed/4.0,.5,1.25)*float(motion_profile.reaction_gain)
		if weapon=="shotgun":reaction_duration=maxf(reaction_duration,hit_stagger)
		reactions.begin(info)
		if not reactions.profile.is_empty():push_speed*=float(reactions.profile.step)
	hp=maxf(0,hp-damage);hit_count+=1
	if hp<=0:
		set_mode("dead");game.kills+=1
		ragdoll.start(push,point,info)
		if info.get("head_burst",false):ragdoll.destroy_head()
	else:
		game.infected_audio.request(self,"hurt")
		if not soft_body:
			stagger=hit_stagger
			locomotion_recovery=float(game.firearms.feedback_data.pistol.recovery_blend)
			if weapon=="baton" and info.get("finisher",false):stagger=.75
			set_mode("hurt");state_time=0;velocity=push.normalized()*push_speed;cooldown=maxf(cooldown,stagger+.1);lost_time=0
	if game.feedback.grabber==self:game.feedback.release("killed" if hp<=0 else "shove" if weapon=="shove" else "interrupted",hp>0)
	if mode=="dead":ragdoll.advance(0)
	else:play_pose(0)

func receive_body_collision(direction: Vector3,speed_m_s: float,point: Vector3,source_id: String) -> void:
	if not active or mode=="dead":return
	body_collision_count+=1
	last_body_collision={"source":source_id,"speed":speed_m_s,"tick":game.tick_count}
	# Impact interrupts and moves a living enemy but is not another bullet hit:
	# no damage, blood, kill credit, or recursive knockdown cascade.
	receive_hit(0,direction,{"weapon":"body_collision","point":point,"speed":speed_m_s})

func play_pose(dt: float, continuous: bool=false) -> void:
	# Setup/reset already invalidates last_sample_time before its forced sample.
	if dt==0 and last_sample_time<0:reset_scheduling()
	# Visual pose LOD only: AI, movement, contact timers and health still advance
	# above. Child hitboxes retain exactly the displayed pose between samples.
	pending_pose_dt+=dt
	var distance_squared: float=global_position.distance_squared_to(game.player.global_position)
	var stride: int=1
	if not continuous and dt>0 and last_sample_time>=0 and reaction_time>=reaction_duration and mode in ["idle","chase","return"] and not priority_target():
		if distance_squared>16:stride=4 if mode=="idle" else 2
		if distance_squared>144:stride=6 if mode=="idle" else 4
	if stride>1 and game.tick_count%stride!=get_index()%stride:
		game.profiler.count("pose_lod_deferred");return
	dt=pending_pose_dt;pending_pose_dt=0
	last_pose_tick=game.tick_count
	var started: int=game.profiler.mark()
	game.profiler.count("pose_samples")
	var sampled: Dictionary=native_motion.sample(dt)
	var clip: String=sampled.clip
	var changed:=animation_name!=clip
	if changed:
		if last_sample_time>=0:pose_blend.begin(.24 if reaction_time<reaction_duration+.30 else .12,[base_pose] if not base_pose.is_empty() else [])
		animation_name=clip
	animation_time=sampled.time
	if not changed and animation_time<last_sample_time-.03 and mode in ["hurt","attack"]:pose_blend.begin(.065,[base_pose] if not base_pose.is_empty() else [])
	last_sample_time=animation_time
	# Native rotations are complete; constant bind translations are omitted.
	# Reset on clip changes only, then absolute tracks replace each layered pose.
	if changed:skeleton.reset_bone_poses()
	if animator.current_animation!=clip:animator.play(clip)
	animator.seek(animation_time,false);animator.advance(0)
	pose_blend.apply(dt)
	if base_pose.size()!=skeleton.get_bone_count():base_pose.resize(skeleton.get_bone_count())
	for bone in skeleton.get_bone_count():base_pose[bone]=skeleton.get_bone_pose(bone)
	native_motion.ground_feet(dt)
	native_motion.flinch()
	if reaction_time>=reaction_duration:reactions.current_deltas.clear();reactions.peak_degrees=0
	if reaction_time<reaction_duration or mode in ["grab","attack"]:skeleton.force_update_all_bone_transforms()
	if reaction_time<reaction_duration and mode!="dead":
		var pulse: float=(1-exp(-reaction_time*65))*exp(-reaction_time*7)*reaction_strength
		var pitch: float=reaction_vector.z*deg_to_rad(18)*pulse
		var roll: float=-reaction_vector.x*deg_to_rad(14)*pulse
		if not reactions.profile.is_empty():
			reactions.apply()
		elif reaction_zone=="head":
			rotate_world("Head1",global_basis.x,pitch*1.7);rotate_world("Head1",global_basis.z,roll*1.3+sin(float(reaction_serial)*2)*.07*pulse)
			rotate_world("Spine2",global_basis.x,pitch*.3)
		elif reaction_zone=="leg":
			rotate_world("L_Thigh" if reaction_serial%2==0 else "R_Thigh",global_basis.x,.22*pulse)
			rotate_world("Spine",global_basis.z,roll*.5)
		else:
			rotate_world("Spine2",global_basis.x,pitch);rotate_world("Spine1",global_basis.z,roll)
			rotate_world("L_UpperArm",global_basis.x,-pitch*.4);rotate_world("R_UpperArm",global_basis.x,-pitch*.4)
	if mode=="grab":
		rotate_world("Spine1",global_basis.x,-.16)
		rotate_world("Spine2",global_basis.x,-.10)
		rotate_world("Head1",global_basis.x,-.10+sin(state_time*9)*.018)
		skeleton.force_update_all_bone_transforms()
		for side in ["L","R"]:
			var sign_side: float=-1 if side=="L" else 1
			var target: Vector3=game.player.global_position+Vector3.UP*1.35+global_basis.x*sign_side*.23+global_basis.z*.20
			reach_arm(side,target,1.0)
	elif mode=="attack":
		native_motion.align_contact()
	skeleton.force_update_all_bone_transforms()
	head_hitbox.global_position=skeleton.to_global(skeleton.get_bone_global_pose(head_bone).origin)+Vector3.UP*.075*float(motion_profile.visual_scale)
	head_hitbox.collision_layer=16 if active and mode!="dead" else 0
	ragdoll.update_hitboxes()
	game.profiler.end_scope("pose",started)

func rotate_world(suffix: String, axis: Vector3, angle: float) -> void:
	var bone: int=bone_ids.get(suffix,-1)
	if bone<0:return
	var basis: Basis=(skeleton.global_basis*skeleton.get_bone_global_pose(bone).basis).orthonormalized()
	var local_axis:=basis.inverse()*axis.normalized()
	skeleton.set_bone_pose_rotation(bone,(skeleton.get_bone_pose_rotation(bone)*Quaternion(local_axis,angle)).normalized())

func bone_position(suffix: String) -> Vector3:
	return skeleton.to_global(skeleton.get_bone_global_pose(bone_ids[suffix]).origin)

func aim_bone(suffix: String, child: String, target: Vector3, weight: float) -> void:
	var origin:=bone_position(suffix)
	var current: Vector3=(bone_position(child)-origin).normalized()
	var desired: Vector3=(target-origin).normalized()
	var axis:=current.cross(desired)
	if axis.length_squared()>.000001:rotate_world(suffix,axis.normalized(),acos(clampf(current.dot(desired),-1,1))*weight)
	skeleton.force_update_all_bone_transforms()

func reach_arm(side: String, target: Vector3, weight: float) -> void:
	if weight<.001:return
	var shoulder:=bone_position(side+"_UpperArm")
	var elbow:=bone_position(side+"_Forearm")
	var wrist:=bone_position(side+"_Hand")
	var upper:=shoulder.distance_to(elbow);var lower:=elbow.distance_to(wrist)
	var distance:=clampf(shoulder.distance_to(target),absf(upper-lower)+.005,(upper+lower)*.975)
	var direction: Vector3=(target-shoulder).normalized()
	var pole: Vector3=global_basis*Vector3(-.5 if side=="L" else .5,-.8,.12)
	pole=(pole-direction*pole.dot(direction)).normalized()
	var along: float=(upper*upper-lower*lower+distance*distance)/(2*distance)
	var bend:=sqrt(maxf(0,upper*upper-along*along))
	var elbow_target:=shoulder+direction*along+pole*bend
	aim_bone(side+"_UpperArm",side+"_Forearm",elbow_target,weight)
	aim_bone(side+"_Forearm",side+"_Hand",shoulder+direction*distance,weight)

func observe() -> Dictionary:
	return {"model":definition.model,"motion_profile":motion_profile,"attack_serial":attack_serial,"attack_time":state_time if mode=="attack" else -1.0,"hit_applied":hit_applied,"hand_positions":[bone_position("L_Hand"),bone_position("R_Hand")],"ragdoll":ragdoll.observe(),"animation_origin":animation_origin,"native_source":native_motion.last_source,"body_collisions":{"count":body_collision_count,"last":last_body_collision},"reaction":{"part":reactions.part,"layer_peak_degrees":reactions.peak_degrees,"recovery":locomotion_recovery,"variant":reactions.blend_id,"zone":reaction_zone,"direction":reaction_direction,"time":reaction_time,"strength":reaction_strength,"serial":reaction_serial},"collision_radius":collision_radius,"head_position":[head_hitbox.global_position.x,head_hitbox.global_position.y,head_hitbox.global_position.z],"id":str(definition.id),"type":definition.type,"position":[position.x,position.y,position.z],"home":[home.x,home.y,home.z],"state":mode,"hp":hp,"sees_player":detection,"animation":animation_name,"animation_time":animation_time,"bones":skeleton.get_bone_count(),"path_points":path.size(),"path_index":path_index,"anchored":anchored,"hit_count":hit_count,"active":active,"source_position":definition.position,"spawn_adjustment":[spawn_adjustment.x,spawn_adjustment.y,spawn_adjustment.z]}
