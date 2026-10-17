extends RefCounted
## Shape matching for the thorax/pelvis and signed bend planes for limbs.
## Distance constraints alone cannot distinguish a knee from a ball joint.
var body_ref: WeakRef
var core: Array=[]
var offsets: Array[Vector3]=[]
var chains: Array=[]
var frames: Dictionary={}
var source_basis:=Basis.IDENTITY
var current_basis:=Basis.IDENTITY

func setup(owner_body) -> void:
	body_ref=weakref(owner_body);core.clear();offsets.clear();chains.clear();frames.clear()
	var body=owner_body
	source_basis=body.torso_frame();current_basis=source_basis
	for name in ["Pelvis","Spine","Spine1","Spine2","Spine4","Neck1","L_Clavicle","R_Clavicle","L_UpperArm","R_UpperArm","L_Thigh","R_Thigh"]:
		if body.ids.has(name):core.append(body.ids[name])
	var center:=Vector3.ZERO
	for id in core:center+=body.positions[id]
	center/=core.size()
	for id in core:offsets.append(source_basis.transposed()*(body.positions[id]-center))
	for side in ["L","R"]:
		for leg in [false,true]:
			var names: Array=[side+"_Thigh",side+"_Calf",side+"_Foot"] if leg else [side+"_UpperArm",side+"_Forearm",side+"_Hand"]
			var a: int=body.ids[names[0]];var b: int=body.ids[names[1]];var c: int=body.ids[names[2]]
			var u: Vector3=body.positions[b]-body.positions[a];var v: Vector3=body.positions[c]-body.positions[b]
			var direction: Vector3=(body.positions[c]-body.positions[a]).normalized()
			var pole: Vector3=u-direction*u.dot(direction)
			var fallback:=Vector3(0,0,-1) if leg else Vector3(-.8 if side=="L" else .8,0,-.35)
			pole=fallback if pole.length()<.025 else source_basis.transposed()*pole.normalized()
			if leg:pole=Vector3(0,0,-1)
			chains.append({"a":a,"b":b,"c":c,"upper":u.length(),"lower":v.length(),"pole":pole.normalized(),"leg":leg})
			var normal: Vector3=u.cross(v).normalized()
			if normal.length_squared()<.5:normal=u.normalized().cross(source_basis*pole).normalized()
			for n in [names[0],names[1]]:
				var delta: Vector3=body.directions[n]
				frames[n]={"chain":chains.size()-1,"basis":segment_frame(delta,normal)}

func segment_frame(direction: Vector3,normal: Vector3) -> Basis:
	var x:=direction.normalized()
	var z: Vector3=(normal-x*normal.dot(x)).normalized()
	if z.length_squared()<.5:z=x.cross(Vector3.UP if absf(x.y)<.8 else Vector3.RIGHT).normalized()
	return Basis(x,z.cross(x).normalized(),z)

func update_basis() -> void:
	var body=body_ref.get_ref()
	var positions: Array[Vector3]=body.positions
	# Fit all thorax/pelvis points. A frame taken only from clavicles/spine
	# ignores torque applied at the hips and can balance a corpse on its head.
	var center:=Vector3.ZERO
	for id in core:center+=positions[id]
	center/=core.size()
	var covariance:=Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
	for i in core.size():
		var delta: Vector3=positions[core[i]]-center
		covariance.x+=delta*offsets[i].x;covariance.y+=delta*offsets[i].y;covariance.z+=delta*offsets[i].z
	for iteration in 4:
		var torque: Vector3=current_basis.x.cross(covariance.x)+current_basis.y.cross(covariance.y)+current_basis.z.cross(covariance.z)
		var denominator: float=absf(current_basis.x.dot(covariance.x)+current_basis.y.dot(covariance.y)+current_basis.z.dot(covariance.z))+.000001
		var omega:=torque/denominator;var angle:=omega.length()
		if angle<.00001:break
		current_basis=(Basis(Quaternion(omega/angle,minf(angle,.35)))*current_basis).orthonormalized()

func move_point(id: int, target: Vector3, weight: float=1.0) -> void:
	var body=body_ref.get_ref()
	var correction: Vector3=(target-body.positions[id])*weight
	body.positions[id]+=correction
	# Anatomical projection must not create fresh Verlet velocity every pass.
	body.previous[id]+=correction

func solve() -> void:
	var body=body_ref.get_ref()
	var positions: Array[Vector3]=body.positions
	update_basis()
	var center:=Vector3.ZERO
	for id in core:center+=positions[id]
	center/=core.size()
	# Keep the sampled ribcage/pelvis shape, rather than letting the spine fold
	# point by point. It remains free to translate, tip over and rotate.
	for i in core.size():
		var id: int=core[i];move_point(id,center+current_basis*offsets[i],.88)
	for chain in chains:
		var a: Vector3=positions[chain.a];var b: Vector3=positions[chain.b];var c: Vector3=positions[chain.c]
		if chain.leg:
			var thigh: Vector3=(b-a).normalized();var down: Vector3=-current_basis.y
			var angle:=acos(clampf(thigh.dot(down),-1,1))
			if angle>deg_to_rad(100):
				var axis:=down.cross(thigh).normalized()
				var corrected: Vector3=a+down.rotated(axis,deg_to_rad(100))*float(chain.upper)
				var correction: Vector3=(corrected-b)*.75;b+=correction;c+=correction;move_point(chain.c,c)
		if chain.leg:
			# The heel may fold behind the knee, but must remain on the leg side
			# of the pelvis rather than curling up beside the head/abdomen.
			var down: Vector3=-current_basis.y
			var minimum: float=(float(chain.upper)+float(chain.lower))*.40
			var projection: float=(c-a).dot(down)
			if projection<minimum:c+=down*(minimum-projection);move_point(chain.c,c)
		var span:=c-a;var length:=span.length()
		if length<.0001:continue
		var direction:=span/length
		var upper: float=chain.upper;var lower: float=chain.lower
		var maximum_bend: float=deg_to_rad(145 if chain.leg else 150)
		var minimum_span:=sqrt(upper*upper+lower*lower+2*upper*lower*cos(maximum_bend))
		var distance:=clampf(length,minimum_span,(upper+lower)*.998)
		if not is_equal_approx(distance,length):
			c=a+direction*distance;move_point(chain.c,c)
		var pole: Vector3=current_basis*Vector3(chain.pole)
		# A shoulder is a ball joint. Keeping its elbow plane glued to the
		# standing torso makes a dead arm prop the whole body up like a tripod.
		# Preserve the evolving physical plane while still limiting elbow flex.
		if not chain.leg:
			var free_pole: Vector3=b-a-direction*(b-a).dot(direction)
			if free_pole.length_squared()>.00001:pole=free_pole
		pole=(pole-direction*pole.dot(direction)).normalized()
		if pole.length_squared()<.5:continue
		var along: float=(upper*upper-lower*lower+distance*distance)/(2*distance)
		var bend:=sqrt(maxf(0,upper*upper-along*along))
		move_point(chain.b,a+direction*along+pole*bend,.70)

func bone_rotation(name: String) -> Basis:
	var body=body_ref.get_ref()
	var positions: Array[Vector3]=body.positions
	if not frames.has(name):return current_basis*source_basis.transposed()
	var entry: Dictionary=frames[name];var chain: Dictionary=chains[entry.chain]
	var u: Vector3=positions[chain.b]-positions[chain.a]
	var v: Vector3=positions[chain.c]-positions[chain.b]
	var normal:=u.cross(v).normalized()
	var reference: Vector3=current_basis*source_basis.transposed()*entry.basis.z
	if normal.length_squared()<.5:normal=reference
	elif chain.leg and normal.dot(reference)<0:normal=-normal
	var direction: Vector3=(positions[body.ids[body.ends[name]]]-positions[body.ids[name]]).normalized()
	return segment_frame(direction,normal)*Basis(entry.basis).transposed()

func observe() -> Dictionary:
	var body=body_ref.get_ref()
	var minimum_side:=INF;var maximum_bend:=0.0
	for chain in chains:
		var a: Vector3=body.positions[chain.a];var b: Vector3=body.positions[chain.b];var c: Vector3=body.positions[chain.c]
		var direction: Vector3=(c-a).normalized();var pole: Vector3=current_basis*Vector3(chain.pole)
		pole=(pole-direction*pole.dot(direction)).normalized()
		if chain.leg:minimum_side=minf(minimum_side,(b-a-direction*(b-a).dot(direction)).dot(pole))
		maximum_bend=maxf(maximum_bend,rad_to_deg(acos(clampf((b-a).normalized().dot((c-b).normalized()),-1,1))))
	return {"hinges":chains.size(),"minimum_knee_bend_side_m":minimum_side if not chains.is_empty() else 0.0,"maximum_bend_degrees":maximum_bend,"rigid_core_points":core.size(),"shoulder_swivel":true}
