extends RefCounted
## Fixed-step position-based joint physics. The same solver runs in manual
## play and bounded tests; rendering and wall-clock waiting never advance it.
const PREFIX := "ValveBiped.Bip01_"
const SOLVER_HZ := 60.0
const MAX_SPEED := 5.0
const PART_ROOTS := {"Head":"Head1","ArmL":"L_UpperArm","ArmR":"R_UpperArm","LegL":"L_Thigh","LegR":"R_Thigh"}
const NAMES := ["Pelvis","Spine","Spine1","Spine2","Spine4","Neck1","Head1","L_Clavicle","L_UpperArm","L_Forearm","L_Hand","R_Clavicle","R_UpperArm","R_Forearm","R_Hand","L_Thigh","L_Calf","L_Foot","L_Toe0","R_Thigh","R_Calf","R_Foot","R_Toe0"]
# The solver visits these fields hundreds of times per awake body per tick.
# Typed constraints keep the same iteration order/math without Dictionary lookups.
class DistanceConstraint:
	var a: int
	var b: int
	var min: float
	var max: float
	func _init(first: int,second: int,lower: float,upper: float) -> void:
		a=first;b=second;min=lower;max=upper

# Immutable sphere resources are shared by radius. Each actor owns its mutable
# query, reused serially for all particles; neither death nor wake allocates one.
static var sphere_pool: Dictionary[float,SphereShape3D]={}
var collision_query:=PhysicsShapeQueryParameters3D.new()
var particle_shapes: Array[SphereShape3D]=[]
var actor: CharacterBody3D
var rig: Skeleton3D
var active := false
var sleeping := false
var age := 0.0
var positions: Array[Vector3]=[]
var previous: Array[Vector3]=[]
var radii: Array[float]=[]
var names: Array[String]=[]
var ids: Dictionary={}
var bones: Dictionary={}
var bases: Dictionary={}
var directions: Dictionary={}
var ends: Dictionary={}
var links: Array[DistanceConstraint]=[]
var detached: Array[String]=[]
var parts: Dictionary={}
var sever_parts: Dictionary={}
var hitboxes: Dictionary={}
var contacts := 0
var max_error := 0.0
var body_mesh: ArrayMesh
var intact_skin: MeshInstance3D
var intact_mesh: ArrayMesh
var headless_mesh: ArrayMesh
var head_destroyed := false
var launch_remaining := 0.0
var launch_velocity := Vector3.ZERO
var launch_cap := MAX_SPEED
var launch_kind := ""
var death_variant := ""
var launch_serial := 0
var body_contacts: Dictionary={}
var body_contact_events: Array=[]
var source_frame := Basis.IDENTITY
const HIT_PAIRS={"Body":["Pelvis","Spine2"],"ArmL":["L_UpperArm","L_Hand"],"ArmR":["R_UpperArm","R_Hand"],"LegL":["L_Thigh","L_Foot"],"LegR":["R_Thigh","R_Foot"]}
var point_bones: Dictionary={}
var hit_shapes: Dictionary={}
class HitBinding:
	var area: Area3D
	var shape: CapsuleShape3D
	var first: int
	var second: int
var hit_bindings: Array[HitBinding]=[]
var inverse_masses: Array[float]=[]
var quiet_time := 0.0
var max_speed := 0.0
var sleep_reason := ""
var wake_count := 0
var impact_count := 0
var last_impact: Dictionary={}
var landing_cooldown := 0.0
var landing_speed := 0.0
var frame_contacts := 0
var frame_wall_contact := false
var frame_floor_contact := false
var separation_pairs: Array=[]
var anatomy=preload("res://scripts/infected_anatomy.gd").new()

func setup(owner_actor: CharacterBody3D) -> void:
	actor=owner_actor;rig=actor.skeleton
	collision_query.collision_mask=1;collision_query.margin=.002
	for radius in [.028,.06,.075,.115,.13,.15]:sphere_for(radius*actor.model.scale.y)
	for i in rig.get_bone_count():point_bones[rig.get_bone_name(i).trim_prefix(PREFIX)]=i
	for mesh in actor.model.find_children("*","MeshInstance3D",true,false):
		if mesh.name.begins_with("Part_"):
			parts[str(mesh.name).trim_prefix("Part_").split(".")[0].split("_")[0]]=mesh
			for surface in mesh.mesh.get_surface_count():
				var material: Material=mesh.get_active_material(surface)
				if material.resource_name.begins_with("Cut_interior"):
					var hidden:=StandardMaterial3D.new();hidden.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;hidden.albedo_color=Color(0,0,0,0)
					mesh.set_surface_override_material(surface,hidden)
		elif mesh.name.begins_with("Sever_"):
			sever_parts[str(mesh.name).trim_prefix("Sever_").split(".")[0].split("_")[0]]=mesh;mesh.visible=false
	for part in ["Body","ArmL","ArmR","LegL","LegR"]:
		var area:=Area3D.new();area.name="Hit_"+part;area.collision_layer=16;area.collision_mask=0;area.monitoring=false;area.monitorable=false
		area.set_meta("shot_owner",actor);area.set_meta("hit_part",part);actor.add_child(area)
		var shape:=CollisionShape3D.new();shape.shape=CapsuleShape3D.new();area.add_child(shape);hitboxes[part]=area
		hit_shapes[part]=shape.shape
		shape.shape.radius=(float(actor.motion_profile.body_radius) if part=="Body" else .085 if part.begins_with("Arm") else .115)*actor.model.scale.y
		var binding:=HitBinding.new();binding.area=area;binding.shape=shape.shape
		binding.first=point_bones[HIT_PAIRS[part][0]];binding.second=point_bones[HIT_PAIRS[part][1]]
		hit_bindings.append(binding)
	if parts.has("Body"):body_mesh=parts.Body.mesh
	actor.head_hitbox.set_meta("hit_part","Head")
	intact_skin=preload("res://scripts/infected_skin_batch.gd").create(parts)
	if intact_skin!=null:
		for mesh in parts.values():mesh.visible=false
		intact_mesh=intact_skin.mesh
		# Prewarm once per source model, not during a shot's critical frame.
		headless_mesh=preload("res://scripts/infected_skin_batch.gd").mesh_for(parts,true)

func torso_frame() -> Basis:
	var x: Vector3=(positions[ids.R_Clavicle]-positions[ids.L_Clavicle]).normalized()
	var y: Vector3=(positions[ids.Spine2]-positions[ids.Pelvis]).normalized()
	var z:=x.cross(y).normalized();y=z.cross(x).normalized()
	return Basis(x,y,z).orthonormalized()

func point(suffix: String) -> Vector3:
	return rig.to_global(rig.get_bone_global_pose(int(point_bones[suffix])).origin)

func update_hitboxes() -> void:
	if actor.replica_only:return # Client shots are cosmetic; authority owns all hit tests.
	var started: int=actor.game.profiler.mark()
	var layer: int=(32 if active else 16) if actor.active else 0
	var transform: Transform3D=rig.global_transform
	for binding: HitBinding in hit_bindings:
		var area: Area3D=binding.area
		if area.collision_layer!=layer:area.collision_layer=layer
		if not actor.active:continue
		var a: Vector3=transform*rig.get_bone_global_pose(binding.first).origin
		var b: Vector3=transform*rig.get_bone_global_pose(binding.second).origin
		var axis: Vector3=(b-a).normalized()
		var shape: CapsuleShape3D=binding.shape
		var height:=maxf(shape.radius*2,a.distance_to(b)+shape.radius)
		# Radius never changes; avoid re-registering physics geometry for numerical
		# noise. Maximum endpoint error is 1.5 mm; transforms still update at 60 Hz.
		if absf(shape.height-height)>.003:shape.height=height
		area.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,axis)),(a+b)*.5)
	var head_layer: int=0 if head_destroyed else layer
	if actor.head_hitbox.collision_layer!=head_layer:actor.head_hitbox.collision_layer=head_layer
	actor.game.profiler.end_scope("hitboxes",started)

func radius_for(n: String) -> float:
	if n=="Head1":return .13
	if n.begins_with("Spine"):return .15
	if n=="Pelvis":return .15
	if "Thigh" in n:return .115
	return .075

func sphere_for(radius: float) -> SphereShape3D:
	if not sphere_pool.has(radius):
		var shape:=SphereShape3D.new();shape.radius=radius;sphere_pool[radius]=shape
	return sphere_pool[radius]

func add_point(n: String,p: Vector3,r: float) -> void:
	ids[n]=positions.size();names.append(n);positions.append(p);previous.append(p);radii.append(r*actor.model.scale.y)
	var mass:=3.0 if n=="Pelvis" else 2.4 if n.begins_with("Spine") else .7 if "Hand" in n else 1.1 if "Foot" in n or "Toe" in n else 1.0
	inverse_masses.append(1.0/mass)
	particle_shapes.append(sphere_for(r*actor.model.scale.y))

func link(a: String,b: String,minimum := -1.0,maximum := -1.0) -> void:
	if not ids.has(a) or not ids.has(b):return
	var length: float=positions[ids[a]].distance_to(positions[ids[b]])
	if length<.001:return
	links.append(DistanceConstraint.new(ids[a],ids[b],length if minimum<0 else minimum,length if maximum<0 else maximum))

func start(push: Vector3,impact: Vector3,info: Dictionary={}) -> void:
	if active:return
	# Keep the complete skin while its skeleton follows the joint solver.
	if intact_skin!=null:intact_skin.visible=true
	for mesh in parts.values():mesh.visible=intact_skin==null
	active=true;sleeping=false;age=0;contacts=0
	for n in NAMES:
		var bone:=rig.find_bone(PREFIX+n)
		if bone<0:continue
		var transform: Transform3D=rig.global_transform*rig.get_bone_global_pose(bone)
		bones[n]=bone;bases[n]=transform.basis;add_point(n,transform.origin,radius_for(n))
	for n in names.duplicate():
		var parent: int=rig.get_bone_parent(bones[n])
		while parent>=0:
			var parent_name: String=rig.get_bone_name(parent).trim_prefix(PREFIX)
			if ids.has(parent_name):link(parent_name,n);break
			parent=rig.get_bone_parent(parent)
	source_frame=torso_frame()
	# Triangle braces preserve thorax/pelvis volume; extremities remain free.
	for pair in [["L_Clavicle","R_Clavicle"],["Spine2","Pelvis"],["Spine2","L_Thigh"],["Spine2","R_Thigh"],["L_Thigh","R_Thigh"],["Pelvis","L_Clavicle"],["Pelvis","R_Clavicle"]]:link(pair[0],pair[1])
	var endpoint={"Pelvis":"Spine","Spine":"Spine1","Spine1":"Spine2","Spine2":"Spine4","Spine4":"Neck1","Neck1":"Head1","L_Clavicle":"L_UpperArm","L_UpperArm":"L_Forearm","L_Forearm":"L_Hand","R_Clavicle":"R_UpperArm","R_UpperArm":"R_Forearm","R_Forearm":"R_Hand","L_Thigh":"L_Calf","L_Calf":"L_Foot","L_Foot":"L_Toe0","R_Thigh":"R_Calf","R_Calf":"R_Foot","R_Foot":"R_Toe0"}
	for n in bones:
		var end: String=endpoint.get(n,"")
		if not ids.has(end):
			end=n+"Tip";var direction:=actor.global_basis*Vector3(0,.14,0)
			if "Hand" in n:direction=(point(n)-point(n.replace("Hand","Forearm"))).normalized()*.12
			elif "Foot" in n or "Toe" in n:direction=-actor.global_basis.z*.12
			add_point(end,positions[ids[n]]+direction,.06);link(n,end)
		ends[n]=end;directions[n]=(positions[ids[end]]-positions[ids[n]]).normalized()
	for side in ["L","R"]:
		for chain in [[side+"_UpperArm",side+"_Forearm",side+"_Hand"],[side+"_Thigh",side+"_Calf",side+"_Foot"]]:
			var reach: float=point(chain[0]).distance_to(point(chain[1]))+point(chain[1]).distance_to(point(chain[2]))
			# Avoid the old near-zero reach that folded knees and elbows into
			# the torso. These are coarse bend limits, not anatomical hinges.
			link(chain[0],chain[2],reach*(.24 if "Arm" in chain[0] else .27),reach*.998)
		for torso in ["Pelvis","Spine2","Head1"]:
			for limb in [side+"_Forearm",side+"_Hand",side+"_Calf",side+"_Foot"]:
				if ids.has(torso) and ids.has(limb):separation_pairs.append([ids[torso],ids[limb]])
	link("Pelvis","Head1",point("Pelvis").distance_to(point("Head1"))*.82,point("Pelvis").distance_to(point("Head1"))*1.04)
	link("Neck1","Head1Tip")
	anatomy.setup(self)
	var blast: float=info.get("blast",0.0)
	var blast_spin:=Vector3.ZERO
	if info.get("weapon","")=="shotgun" and blast>.15:
		blast_spin=prepare_blast(push,blast,false)
	elif info.get("weapon","")=="pistol":
		var tuning: Dictionary=actor.game.firearms.feedback_data.pistol
		var index: int=posmod(actor.native_motion.variation+actor.reaction_serial,4)
		death_variant=["back_arch","back_left","back_right","back_turn"][index]
		var sideways: float=[0.0,-.32,.32,.22][index]
		var flat:=Vector3(push.x,0,push.z).normalized()
		var side:=flat.cross(Vector3.UP)
		var gain: float=float(actor.motion_profile.push_gain)/maxf(1.0,actor.model.scale.y*actor.model.scale.y)
		var head_gain: float=1.0 if info.get("head",false) else .7
		launch_velocity=(flat*float(tuning.death_speed)+side*sideways+Vector3.UP*float(tuning.death_lift))*gain*head_gain
		blast_spin=(Vector3.UP.cross(flat)*float(tuning.death_spin)+Vector3.UP*sideways*5.0+flat*sideways*2.0)*gain
		launch_remaining=.62;launch_cap=7.0;launch_kind="pistol_death"
	for i in positions.size():
		var fall: Vector3=actor.velocity.limit_length(2.5)+push*(1.2+clampf(1-positions[i].distance_to(impact),0,1)*1.5)
		if launch_remaining>0:fall=launch_velocity+actor.velocity.limit_length(1.0)+blast_spin.cross(positions[i]-positions[ids.Pelvis]).limit_length(4.5)
		previous[i]=positions[i]-fall/SOLVER_HZ
	actor.velocity=Vector3.ZERO;actor.collision_layer=0;actor.collision_mask=0

func prepare_blast(direction: Vector3,blast: float,corpse: bool) -> Vector3:
	var tuning: Dictionary=actor.game.firearms.feedback_data.shotgun
	var flat:=Vector3(direction.x,0,direction.z).normalized()
	if flat.length_squared()<.01:
		flat=(positions[ids.Pelvis]-actor.game.player.global_position);flat.y=0;flat=flat.normalized()
	var gain: float=blast*float(actor.motion_profile.push_gain)/maxf(1.0,actor.model.scale.y*actor.model.scale.y)
	if corpse:gain*=float(tuning.corpse_launch_gain)
	launch_velocity=(flat*float(tuning.launch_speed)+Vector3.UP*float(tuning.launch_lift))*gain
	launch_remaining=float(tuning.launch_time);launch_cap=float(tuning.launch_speed_cap)
	launch_kind="shotgun_corpse" if corpse else "shotgun_death"
	launch_serial+=1;body_contacts.clear()
	return Vector3.UP.cross(flat)*float(tuning.launch_spin)*gain

func destroy_head() -> void:
	if not active or head_destroyed or headless_mesh==null:return
	head_destroyed=true;intact_skin.mesh=headless_mesh;actor.head_hitbox.collision_layer=0
	# Keep the internal skeleton connected, but remove the invisible head's
	# large floor support sphere as well as its bullet hit area.
	for name in ["Head1","Head1Tip"]:
		if ids.has(name):
			var id: int=ids[name];radii[id]=.028*actor.model.scale.y
			# Select a smaller shared shape; never mutate another corpse's sphere.
			particle_shapes[id]=sphere_for(radii[id])

func speed_limit() -> float:return launch_cap if launch_remaining>0 else MAX_SPEED

func region_for(n: String) -> String:
	for part in PART_ROOTS:
		var root: String=PART_ROOTS[part]
		if n==root or n==root+"Tip":return part
		var b: int=bones.get(n.trim_suffix("Tip"),-1)
		while b>=0:
			if rig.get_bone_name(b)==PREFIX+root:return part
			b=rig.get_bone_parent(b)
	return "Body"

func impulse(part: String, direction: Vector3, impact: Vector3, info: Dictionary) -> void:
	if not active or positions.is_empty():return
	var was_sleeping:=sleeping
	if sleeping:
		# A sleeping body must not retain the tiny pre-sleep velocities.
		previous=positions.duplicate();wake_count+=1
	sleeping=false;age=0;quiet_time=0;sleep_reason="";impact_count+=1
	var weapon: String=info.get("weapon","pistol")
	var strength:=3.2
	if weapon=="shotgun":strength=5.8*clampf(sqrt(float(info.get("total_pellets",1))/6.0),.45,1.15)
	elif weapon=="baton":strength=5.4 if info.get("finisher",false) else 4.2
	elif weapon=="shove":strength=2.0
	strength/=maxf(1.0,pow(actor.model.scale.y,2))
	var incoming:=direction.normalized()
	var flat:=Vector3(incoming.x,0,incoming.z).normalized()
	# Grounded downward impacts deflect locally along the floor with a small
	# rebound. Keep the downward component for airborne bodies.
	var supported:=was_sleeping or frame_contacts>0
	var kick: Vector3=incoming*strength
	if supported and incoming.y<-.25:kick=flat*strength*.9+Vector3.UP*(.3+strength*.22)
	var weights: Array[float]=[];var peak_weight:=0.0
	var radius: float=.34*actor.model.scale.y
	var hit_contacts: Array=info.get("contacts",[{"part":part,"point":impact,"direction":direction}])
	var hit_parts: Array=[]
	for contact in hit_contacts:
		if not contact.part in hit_parts:hit_parts.append(contact.part)
	for i in positions.size():
		var region:=region_for(names[i]);var weight:=0.0
		# Scatter hits distribute one bounded impulse across the actual pellet
		# contacts; one head pellet must not redirect the entire blast to the neck.
		for contact in hit_contacts:
			var same: bool=region==contact.part
			var distance:=positions[i].distance_to(contact.point)
			weight+=exp(-distance*distance/(2*radius*radius))*(1.0 if same else .12)+(.07 if same else 0.0)
		weight/=maxi(1,hit_contacts.size())
		weights.append(weight);peak_weight=maxf(peak_weight,weight)
	# Normalize the nearest point, not the whole body. Off-centre forces create
	# joint rotation; a chest hit no longer gives every extremity equal velocity.
	var affected: Array=[];var applied_velocity: Dictionary={}
	var blast_spin:=Vector3.ZERO
	var launched: bool=weapon=="shotgun" and float(info.get("blast",0))>.15
	if launched:blast_spin=prepare_blast(direction,float(info.blast),true)
	for i in positions.size():
		var weight:=weights[i]/maxf(.01,peak_weight)
		var before: Vector3=(positions[i]-previous[i])*SOLVER_HZ
		var velocity: Vector3=(before+kick*weight*inverse_masses[i]).limit_length(speed_limit())
		if launched:
			# A close shotgun lifts the whole corpse, while off-centre pellet
			# contacts still add local rotation. Replace old momentum to bound stacking.
			velocity=(before*.20+launch_velocity+blast_spin.cross(positions[i]-positions[ids.Pelvis]).limit_length(3.5)+kick*weight*.16).limit_length(speed_limit())
		previous[i]=positions[i]-velocity/SOLVER_HZ
		var change: Vector3=velocity-before;applied_velocity[names[i]]=[change.x,change.y,change.z]
		if weight>.25:affected.append(names[i])
	last_impact={"launched":launched,"part":part,"parts":hit_parts,"weapon":weapon,"point":[impact.x,impact.y,impact.z],"direction":[incoming.x,incoming.y,incoming.z],"strength":strength,"affected":affected,"applied_velocity":applied_velocity,"woke":was_sleeping,"serial":impact_count,"tick":actor.game.tick_count}

func collide_living(before: Array[Vector3],dt: float) -> void:
	if launch_remaining<=0 or not launch_kind.begins_with("shotgun"):return
	var tuning: Dictionary=actor.game.firearms.feedback_data.body_collision
	var from: Vector3=(before[ids.Pelvis]+before[ids.Spine2])*.5
	var to: Vector3=(positions[ids.Pelvis]+positions[ids.Spine2])*.5
	var incoming: Vector3=(to-from)/dt
	var flat:=Vector3(incoming.x,0,incoming.z)
	var speed:=flat.length()
	if speed<.2:return
	var direction:=flat/speed
	var radius: float=.28*actor.model.scale.y
	for other in actor.game.crowd.near_position(to):
		actor.game.profiler.count("body_contact_candidates")
		if other==actor or not other.active or other.mode=="dead":continue
		var contacted: bool=body_contacts.has(other.name)
		if not contacted and (speed<float(tuning.minimum_speed) or body_contacts.size()>=int(tuning.maximum_targets)):continue
		var base: Vector3=other.global_position
		# Sweep the torso sphere against the living character's vertical capsule.
		# This catches fast contact without per-bone or all-actor pair scans.
		var lower: Vector3=base+Vector3.UP*other.collision_radius
		var upper: Vector3=base+Vector3.UP*(1.58*other.model.scale.y-other.collision_radius)
		var nearest:=Geometry3D.get_closest_points_between_segments(from,to,lower,upper)
		if nearest[0].distance_to(nearest[1])>radius+other.collision_radius:continue
		if (nearest[1]-from).dot(direction)<-.15:continue
		var ray:=PhysicsRayQueryParameters3D.create(from,nearest[1],1)
		actor.game.profiler.count("body_contact_occlusion_rays")
		if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		if not contacted:
			var transferred: float=minf(float(tuning.maximum_push),speed*float(tuning.transfer))
			other.receive_body_collision(direction,transferred,nearest[1],str(actor.definition.id))
			body_contacts[other.name]=true
			body_contact_events.append({"target":str(other.definition.id),"speed":speed,"push":transferred,"launch":launch_serial,"tick":actor.game.tick_count})
			if body_contact_events.size()>12:body_contact_events.pop_front()
		# Uniform positional correction preserves joints and reduces forward
		# momentum in this very solver step. The target gets one impulse per flight.
		var correction: Vector3=(from-to)*(1.0-float(tuning.retained_velocity))
		var outward: Vector3=to-nearest[1]
		var penetration: float=maxf(0,radius+other.collision_radius-outward.length())
		if outward.length_squared()>.0001:correction+=outward.normalized()*minf(.20,penetration)
		for i in positions.size():
			positions[i]+=correction
			collide(i,before[i])
		break

func collide(i: int,old: Vector3) -> void:
	var desired: Vector3=positions[i]
	var query:=collision_query
	query.shape=particle_shapes[i]
	query.transform=Transform3D(Basis.IDENTITY,old);query.motion=positions[i]-old
	var space: PhysicsDirectSpaceState3D=actor.get_world_3d().direct_space_state
	var fractions:=space.cast_motion(query)
	var contact_probe: Vector3=positions[i]
	if fractions.size()==2 and fractions[0]<1:
		positions[i]=old+query.motion*fractions[0]
		# Rest info requires an intersection, not the safe (nonintersecting)
		# sweep endpoint. Query the unsafe endpoint with a tiny inward probe.
		contact_probe=old+query.motion*fractions[1]+query.motion.normalized()*.0005
	query.motion=Vector3.ZERO;query.transform.origin=contact_probe
	var hit:=space.get_rest_info(query)
	if not hit.is_empty():
		var normal: Vector3=hit.normal
		if normal.y<.5:frame_wall_contact=true
		if normal.y>.5:frame_floor_contact=true
		landing_speed=maxf(landing_speed,maxf(0,-((positions[i]-previous[i])*SOLVER_HZ).dot(normal)))
		positions[i]=hit.point+normal*(radii[i]+.003)
		# Retain tangential/outward motion at every contact, including floors.
		# Otherwise a zero-fraction sweep pins fingers to posts or toes to the
		# floor while joint constraints pull the rest of the body away.
		var tail: Vector3=desired-positions[i]
		if tail.dot(normal)<0:tail=tail.slide(normal)
		if tail.length_squared()>.000001:
			query.transform.origin=positions[i];query.motion=tail
			var slide_fractions:=space.cast_motion(query)
			positions[i]+=tail*(float(slide_fractions[0]) if slide_fractions.size()==2 else 1.0)
		if normal.y<.5 and positions[i].y<old.y:
			# At a wall/floor corner nearest-contact info may describe only the
			# wall. Preserve crossed floor support during the slide/depenetration.
			# This is a real local surface ray, not a hardcoded floor height.
			var above:=Vector3(positions[i].x,old.y+radii[i]+.02,positions[i].z)
			var below:=positions[i]-Vector3.UP*(radii[i]+.01)
			var support:=space.intersect_ray(PhysicsRayQueryParameters3D.create(above,below,1))
			actor.game.profiler.count("corpse_corner_rays")
			if not support.is_empty() and support.normal.y>.5:
				positions[i].y=maxf(positions[i].y,support.position.y+radii[i]+.003)
		var velocity: Vector3=positions[i]-previous[i]
		if velocity.dot(normal)<0:velocity=velocity.slide(normal)
		# Friction belongs to supporting floors. Applying it to every vertical
		# contact let a corpse hang by its fingers against a thin post.
		previous[i]=positions[i]-velocity*(.65 if normal.y>.5 else 1.0);contacts+=1;frame_contacts+=1

func advance(dt: float) -> void:
	if not active or sleeping:return
	if not sleeping and dt>0:
		launch_remaining=maxf(0,launch_remaining-dt)
		var cap:=speed_limit()
		var frame_before: Array[Vector3]=positions.duplicate()
		age+=dt;var h:=dt;frame_contacts=0;frame_wall_contact=false;frame_floor_contact=false;landing_speed=0;landing_cooldown=maxf(0,landing_cooldown-dt)
		# One swept step at the game's 60 Hz, retaining all eight joint passes.
		# Initial velocities/impulses use the same step size; no slow-motion bodies.
		for substep in 1:
			var before: Array[Vector3]=positions.duplicate()
			for i in positions.size():
				var drag: float=float(actor.game.firearms.feedback_data.shotgun.air_drag) if launch_remaining>0 and launch_kind.begins_with("shotgun") else 1.7
				var motion: Vector3=(positions[i]-previous[i]).limit_length(cap*h)*exp(-h*drag)
				previous[i]=positions[i];positions[i]+=motion+Vector3.DOWN*12*h*h
				collide(i,before[i])
			for iteration in 8:
				# Project anatomy before the distance pass, so the same pass
				# resolves its residual length error. Two stronger anatomical
				# projections retain the shape without four expensive fits.
				if iteration in [3,7]:anatomy.solve()
				for c in links:
					var delta: Vector3=positions[c.b]-positions[c.a];var length:=delta.length()
					if length<.00001:continue
					var error: float=length-clampf(length,c.min,c.max)
					var correction: Vector3=delta*(error/length)
					var mass_sum: float=inverse_masses[c.a]+inverse_masses[c.b]
					positions[c.a]+=correction*inverse_masses[c.a]/mass_sum;positions[c.b]-=correction*inverse_masses[c.b]/mass_sum
				if iteration in [3,7]:
					# A small fixed set of sphere separations stops extremities
					# passing through the chest; no per-mesh self-collision scan.
					for pair in separation_pairs:
						var a: int=pair[0];var b: int=pair[1]
						var delta: Vector3=positions[b]-positions[a];var distance:=delta.length()
						var minimum: float=(radii[a]+radii[b])*.9
						if distance>.00001 and distance<minimum:
							var correction: Vector3=delta*((minimum-distance)/distance)
							var mass: float=inverse_masses[a]+inverse_masses[b]
							positions[a]-=correction*inverse_masses[a]/mass;positions[b]+=correction*inverse_masses[b]/mass
					for i in positions.size():collide(i,before[i])
		collide_living(frame_before,h)
		max_error=0
		for c in links:
			var distance: float=positions[c.a].distance_to(positions[c.b])
			max_error=maxf(max_error,absf(distance-clampf(distance,c.min,c.max)))
		if max_error>.06 and frame_contacts>0:
			# Wall contacts can invalidate a just-projected limb. Resolve length
			# constraints after contact, allowing the torso to yield away from the
			# wall instead of stretching the calf/forearm through it.
			# Tight wall/floor corners need more than one correction block. Stop
			# once feasible; the extra work is restricted to strained contacts.
			for correction_pass in 24:
				if correction_pass in [0,8,16]:anatomy.solve()
				for c in links:
					var delta: Vector3=positions[c.b]-positions[c.a];var length:=delta.length()
					if length<.00001:continue
					var error: float=length-clampf(length,c.min,c.max)
					var correction: Vector3=delta*(error/length)
					var mass: float=inverse_masses[c.a]+inverse_masses[c.b]
					positions[c.a]+=correction*inverse_masses[c.a]/mass;positions[c.b]-=correction*inverse_masses[c.b]/mass
				if correction_pass%4==3:
					for i in positions.size():collide(i,frame_before[i])
					var residual:=0.0
					for c in links:
						var length: float=positions[c.a].distance_to(positions[c.b])
						residual=maxf(residual,absf(length-clampf(length,c.min,c.max)))
					if residual<.035:break
			max_error=0
			for c in links:
				var length: float=positions[c.a].distance_to(positions[c.b]);max_error=maxf(max_error,absf(length-clampf(length,c.min,c.max)))
		max_speed=0
		# Wall/ceiling impact spends the launch energy. Retaining the airborne
		# speed allowance while a body is pinned in a door causes solver jitter.
		if frame_wall_contact:launch_remaining=0;cap=MAX_SPEED
		for i in positions.size():
			var velocity: Vector3=((positions[i]-frame_before[i])/h).limit_length(cap)
			if frame_floor_contact:velocity*=.94 if launch_remaining>0 else .82
			previous[i]=positions[i]-velocity*h;max_speed=maxf(max_speed,velocity.length())
		if frame_contacts>0 and max_speed<.18 and max_error<.04 and age>.45:quiet_time+=dt
		else:quiet_time=0
		if quiet_time>.65 or (age>6 and frame_contacts>0 and max_speed<.6 and max_error<.06):
			sleeping=true;sleep_reason="settled" if quiet_time>.65 else "low_energy_contact";previous=positions.duplicate();max_speed=0
		if landing_speed>1.3 and landing_cooldown<=0:
			actor.game.firearms.corpse_landing(positions[ids.Pelvis],landing_speed);landing_cooldown=.25
	apply_pose();update_hitboxes()

func apply_pose() -> void:
	anatomy.update_basis()
	var inverse:=rig.global_transform.affine_inverse()
	var torso_rotation:=torso_frame()*source_frame.inverse()
	for n in bones:
		var direction: Vector3=(positions[ids[ends[n]]]-positions[ids[n]]).normalized()
		if direction.length_squared()<.1:continue
		var rotation: Basis=anatomy.bone_rotation(n) if anatomy.frames.has(n) else Basis(Quaternion(torso_rotation*directions[n],direction))*torso_rotation
		rig.set_bone_global_pose(bones[n],inverse*Transform3D(rotation*bases[n],positions[ids[n]]))
	actor.head_hitbox.global_position=point("Head1")+Vector3.UP*.075*actor.model.scale.y

func reset() -> void:
	head_destroyed=false;launch_remaining=0;launch_velocity=Vector3.ZERO;launch_cap=MAX_SPEED
	launch_kind="";death_variant="";launch_serial=0;body_contacts.clear();body_contact_events.clear()
	active=false;sleeping=false;age=0;positions.clear();previous.clear();radii.clear();particle_shapes.clear();names.clear();ids.clear();bones.clear();bases.clear();directions.clear();ends.clear();links.clear();detached.clear();contacts=0;max_error=0
	inverse_masses.clear();separation_pairs.clear();quiet_time=0;max_speed=0;sleep_reason="";wake_count=0;impact_count=0;last_impact.clear();landing_cooldown=0;landing_speed=0;frame_contacts=0
	for mesh in parts.values():mesh.visible=intact_skin==null
	if intact_skin!=null:intact_skin.visible=true;intact_skin.mesh=intact_mesh
	for mesh in sever_parts.values():mesh.visible=false
	if body_mesh!=null:
		parts.Body.mesh=body_mesh
		for surface in body_mesh.get_surface_count():
			if body_mesh.surface_get_material(surface).resource_name.begins_with("Cut_interior"):
				var hidden:=StandardMaterial3D.new();hidden.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;hidden.albedo_color=Color(0,0,0,0);parts.Body.set_surface_override_material(surface,hidden)

func observe() -> Dictionary:
	var points: Dictionary={}
	var targets: Dictionary={}
	for key in hitboxes:
		var p: Vector3=hitboxes[key].global_position;targets[key]=[p.x,p.y,p.z]
	for n in ["Pelvis","Head1","L_Hand","R_Hand","L_Foot","R_Foot"]:
		if ids.has(n):
			var p: Vector3=positions[ids[n]];points[n]=[p.x,p.y,p.z]
	return {"launch_kind":launch_kind,"death_variant":death_variant,"body_contacts":body_contact_events.duplicate(true),"dismemberment_enabled":false,"head_burst_enabled":true,"head_destroyed":head_destroyed,"head_hitbox_enabled":actor.head_hitbox.collision_layer!=0,"launch_remaining":launch_remaining,"launch_velocity":[launch_velocity.x,launch_velocity.y,launch_velocity.z],"intact_skin_visible":intact_skin.visible if intact_skin!=null else false,"active":active,"solver":"fixed_step_position_based_joints","sleeping":sleeping,"sleep_reason":sleep_reason,"quiet_time":quiet_time,"max_speed":max_speed,"speed_cap":speed_limit(),"wake_count":wake_count,"impact_count":impact_count,"last_impact":last_impact.duplicate(true),"age":age,"points":points,"targets":targets,"joint_count":links.size(),"anatomy":anatomy.observe() if active else {},"detached":detached.duplicate(),"contacts":contacts,"max_joint_error":max_error}
