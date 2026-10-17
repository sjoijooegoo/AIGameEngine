extends RefCounted
## Contact-aligned wind-up, strike and recovery over each native skin's base.
## Fixed simulation time only. Damage is dispatched by the gameplay state.
static func attack(actor: CharacterBody3D) -> void:
	var spec: Dictionary=actor.motion_profile
	var t: float=actor.state_time
	var contact: float=spec.contact
	var end: float=spec.duration
	var forward: Vector3=-actor.global_basis.z
	var right: Vector3=actor.global_basis.x
	var up:=Vector3.UP
	if spec.style=="grab":
		var reach:=smoothstep(.06,contact-.04,t)*(1-smoothstep(contact+.07,end-.09,t))
		actor.rotate_world("Spine2",right,-.12*reach)
		actor.skeleton.force_update_all_bone_transforms()
		for side in ["L","R"]:
			var sign_side: float=-1 if side=="L" else 1
			var target: Vector3=actor.game.player.global_position+up*(1.38 if side=="R" else 1.2)+right*sign_side*.20
			actor.reach_arm(side,target,reach)
		return
	var wind:=smoothstep(.02,contact*.64,t)
	var strike:=smoothstep(contact*.68,contact,t)
	var recovery:=1-smoothstep(contact+.09,end-.05,t)
	var pulse:=wind*recovery
	var fast: bool=spec.style=="swipe"
	var both: bool=spec.style=="double_slam"
	var sign_attack: float=-1 if fast and actor.attack_serial%2==0 else 1
	actor.rotate_world("Spine2",right,(.12*wind-(.32 if both else .24)*strike)*recovery)
	if not both:actor.rotate_world("Spine1",up,sign_attack*(.25 if fast else .14)*pulse*(1-2*strike))
	actor.skeleton.force_update_all_bone_transforms()
	for side in ["L","R"]:
		var side_sign: float=-1 if side=="L" else 1
		var primary: bool=both or side_sign==sign_attack
		var shoulder: Vector3=actor.bone_position(side+"_UpperArm")
		var ready: Vector3=shoulder+right*side_sign*(.40 if fast else .20)+up*(.02 if fast else .45)-forward*.14
		var impact: Vector3=actor.game.player.global_position+up*(1.30 if both else 1.38)+right*side_sign*.13
		if not primary:
			ready=shoulder+forward*.25-up*.30;impact=ready
		actor.reach_arm(side,ready.lerp(impact,strike),pulse*(1.0 if primary else .5))
