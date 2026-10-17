extends Node3D
## Fixed-clock particles batched into three draw submissions. No TIME shader,
## particle physics callbacks or per-pellet emitter allocations.
const DROP_CAP := 224
const CLOUD_CAP := 48
const MARK_CAP := 48
var world: Node3D
var rng:=RandomNumberGenerator.new()
var drops: Array=[]
var clouds: Array=[]
var marks: Array=[]
var batches: Dictionary={}
var clock := 0.0
var bursts := 0
var head_bursts := 0
var emitted := 0
var peak_particles := 0
var peak_marks := 0
var surface_rays := 0
var last_event: Dictionary={}
var tuning: Dictionary={}

func setup(game: Node3D) -> void:
	world=game
	for kind in ["drops","clouds","marks"]:
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.use_custom_data=true
		var mesh:=QuadMesh.new();mesh.size=Vector2.ONE
		var material:=ShaderMaterial.new();material.shader=preload("res://shaders/blood_stain.gdshader") if kind=="marks" else preload("res://shaders/blood_particle.gdshader")
		if kind!="marks":material.set_shader_parameter("cloud",kind=="clouds")
		mesh.material=material;mm.mesh=mesh;mm.instance_count=MARK_CAP if kind=="marks" else CLOUD_CAP if kind=="clouds" else DROP_CAP;mm.visible_instance_count=0
		var node:=MultiMeshInstance3D.new();node.name="Blood_"+kind;node.multimesh=mm;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node);batches[kind]=mm
	reset()

func reset() -> void:
	drops.clear();clouds.clear();marks.clear();clock=0;bursts=0;head_bursts=0;emitted=0;peak_particles=0;peak_marks=0;surface_rays=0;last_event.clear();rng.seed=71359
	for mm in batches.values():mm.visible_instance_count=0

func trace(from: Vector3, to: Vector3) -> Dictionary:
	surface_rays+=1
	var query:=PhysicsRayQueryParameters3D.create(from,to,1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func blood(point: Vector3, normal: Vector3, direction: Vector3, weapon: String, head: bool, killed: bool, pellets: int, living: bool, head_burst: bool=false) -> void:
	bursts+=1
	var strength: float=(1.35 if weapon=="shotgun" else .9 if weapon=="baton" else 1.0)*(.55 if not living else 1.0)
	var count:=mini(36,int((26 if weapon=="shotgun" else 17 if weapon=="baton" else 20)*strength))
	var cloud_count:=4 if weapon=="shotgun" else 3
	if head:
		strength*=float(tuning.get("head_strength",1.35))
		count=mini(DROP_CAP,int(tuning.get("head_drops",34)*(.55 if not living else 1.0)))
		cloud_count=int(tuning.get("head_clouds",6))
	if head_burst:
		head_bursts+=1
		strength=float(tuning.get("head_burst_strength",2.8))*(.55 if not living else 1.0)
		count=mini(DROP_CAP,int(tuning.get("head_burst_drops",104)*(.55 if not living else 1.0)))
		cloud_count=int(tuning.get("head_burst_clouds",14))
	var origin:=point+normal*.035
	# Two rays per target burst. Stains stop at the first nearby solid surface.
	# Static planes also bound the cosmetic particles; no per-droplet ray storm.
	var back:=trace(origin,point+direction*2.2)
	var floor_hit:=trace(origin,origin+Vector3.DOWN*3.0)
	var mark_scale:=float(tuning.get("head_burst_mark_scale",1.35)) if head_burst else 1.0
	if not back.is_empty():add_mark(back,.23*strength*mark_scale,.04)
	if not floor_hit.is_empty() and floor_hit.normal.y>.65:add_mark(floor_hit,.15*strength*mark_scale,.18)
	var floor_y: float=floor_hit.position.y+.012 if not floor_hit.is_empty() and floor_hit.normal.y>.65 else -INF
	for i in count:
		var velocity: Vector3=(normal*.5+direction*.35+Vector3(rng.randf_range(-.65,.65),rng.randf_range(-.12,.65),rng.randf_range(-.65,.65))).normalized()*rng.randf_range(.75,2.5)*strength
		drops.append({"p":origin+Vector3(rng.randf_range(-.025,.025),rng.randf_range(-.025,.025),rng.randf_range(-.025,.025)),"v":velocity,"age":0.0,"life":rng.randf_range(.25,.72 if head_burst else .58),"size":rng.randf_range(.018,.040)*strength*(.58 if head_burst else 1.0),"seed":rng.randf(),"roll":rng.randf_range(-PI,PI),"floor":floor_y,"back":back,"head":head,"burst":head_burst})
	for i in cloud_count:
		clouds.append({"p":origin+Vector3(rng.randf_range(-.045,.045),rng.randf_range(-.035,.055),rng.randf_range(-.045,.045)),"v":normal*rng.randf_range(.20,.55)+direction*.1,"age":0.0,"life":rng.randf_range(.16,.42 if head_burst else .29),"size":rng.randf_range(.12,.20)*strength*(.35 if head_burst else 1.0),"seed":rng.randf(),"roll":rng.randf_range(-PI,PI),"floor":floor_y,"back":back,"head":head,"burst":head_burst})
	while drops.size()>DROP_CAP:drops.pop_front()
	while clouds.size()>CLOUD_CAP:clouds.pop_front()
	emitted+=count;peak_particles=maxi(peak_particles,drops.size()+clouds.size());peak_marks=maxi(peak_marks,marks.size())
	last_event={"weapon":weapon,"head":head,"head_burst":head_burst,"killed":killed,"living":living,"pellets":pellets,"drops":count,"point":[point.x,point.y,point.z],"tick":world.tick_count}
	flush()

func add_mark(hit: Dictionary, size: float, delay: float) -> void:
	var z: Vector3=hit.normal.normalized()
	var helper:=Vector3.FORWARD if absf(z.dot(Vector3.UP))>.95 else Vector3.UP
	var x:=helper.cross(z).normalized();var basis:=Basis(x,z.cross(x).normalized(),z).rotated(z,rng.randf_range(-PI,PI))
	var transform:=Transform3D(basis.scaled(Vector3.ONE*size*2),hit.position+z*.008)
	var owner_node: Node3D=hit.collider as Node3D
	if owner_node==null:return
	marks.append({"owner":weakref(owner_node),"local":owner_node.global_transform.affine_inverse()*transform,"transform":transform,"age":-delay,"life":16.0,"seed":rng.randf()})
	while marks.size()>MARK_CAP:marks.pop_front()

func advance(dt: float) -> void:
	clock+=dt
	var started: int=world.profiler.mark()
	for kind in 2:
		var group: Array=drops if kind==0 else clouds
		for i in range(group.size()-1,-1,-1):
			var p: Dictionary=group[i];p.age+=dt
			if kind==0:p.v.y-=7.5*dt;p.v*=exp(-dt*1.5)
			p.p+=p.v*dt
			var blocked: bool=not p.back.is_empty() and (p.p-p.back.position).dot(p.back.normal)<.003
			if p.age>=p.life or p.p.y<=p.floor or blocked:group.remove_at(i)
	for i in range(marks.size()-1,-1,-1):
		var mark: Dictionary=marks[i];mark.age+=dt
		var owner_node=mark.owner.get_ref()
		if mark.age>=mark.life or not is_instance_valid(owner_node):marks.remove_at(i)
		else:mark.transform=owner_node.global_transform*mark.local
	flush();world.profiler.count("blood_particles",drops.size()+clouds.size());world.profiler.count("blood_marks",marks.size());world.profiler.end_scope("blood_fx",started)

func flush() -> void:
	var camera_basis: Basis=world.camera.global_basis.orthonormalized()
	for kind in ["drops","clouds"]:
		var group: Array=drops if kind=="drops" else clouds
		var mm: MultiMesh=batches[kind];mm.visible_instance_count=group.size()
		for i in group.size():
			var p: Dictionary=group[i];var t: float=p.age/p.life
			var size: float=p.size*(1+t*1.8 if kind=="clouds" else 1-t*.30)
			var basis:=camera_basis.rotated(camera_basis.z,p.roll)
			basis.x*=size;basis.y*=size*(1 if kind=="clouds" else 1.8)
			mm.set_instance_transform(i,Transform3D(basis,p.p))
			var color:=Color(.14+p.seed*.05,.006,.003,(.32 if kind=="clouds" else .92)*(1-smoothstep(.12,1,t)))
			var tint:=Color(.16,.004,.002,1.0) if p.get("head",false) else Color(.10,.003,.002,1.0)
			if p.get("burst",false):tint=Color(.22,.006,.002,1.0)
			mm.set_instance_color(i,Color(tint.r+p.seed*.04,tint.g,tint.b,(.42 if kind=="clouds" else .94)*(1-smoothstep(.08,1,t))))
			mm.set_instance_custom_data(i,Color(p.seed,1.0 if p.get("head",false) else 0.0,1.0 if p.get("burst",false) else 0.0,0))
	var mm: MultiMesh=batches.marks;mm.visible_instance_count=marks.size()
	for i in marks.size():
		var mark: Dictionary=marks[i];mm.set_instance_transform(i,mark.transform)
		mm.set_instance_color(i,Color(.095,.004,.002,.78*(1-smoothstep(.68,1,mark.age/mark.life)) if mark.age>=0 else 0))
		mm.set_instance_custom_data(i,Color(mark.seed,0,0,0))

func observe() -> Dictionary:
	var signature: Array=[]
	for p in drops:signature.append([p.p,p.age])
	for p in clouds:signature.append([p.p,p.age])
	for m in marks:signature.append([m.transform,m.age])
	var sample_marks: Array=[]
	for mark in marks.slice(0,3):
		var p: Vector3=mark.transform.origin
		sample_marks.append({"position":[p.x,p.y,p.z],"age":mark.age})
	return {"drops":drops.size(),"clouds":clouds.size(),"marks":marks.size(),"bursts":bursts,"head_bursts":head_bursts,"emitted":emitted,"peak_particles":peak_particles,"peak_marks":peak_marks,"caps":[DROP_CAP,CLOUD_CAP,MARK_CAP],"surface_rays":surface_rays,"clock":clock,"signature":hash(signature),"last_event":last_event.duplicate(true),"sample_marks":sample_marks}
