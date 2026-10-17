extends RefCounted
## A fixed-step, bounded swing. Cosmetic bones do not bypass world collision.
var weapon
var combo := -1
var serial := 0
var idle_time := 0.0
var buffered := false
var hitstop := 0.0
var hit_ids: Dictionary={}
var history: Array=[]
var last_hits: Array=[]
var blocked := false
var total_hits := 0
var peak_rays := 0
var wall_feedback := false
var rebound := 0.0

func reset() -> void:
	combo=-1;serial=0;idle_time=0;buffered=false;hitstop=0;hit_ids.clear();history.clear();last_hits.clear();blocked=false;total_hits=0;peak_rays=0;wall_feedback=false;rebound=0

func cancel() -> void:
	buffered=false;hitstop=0;combo=-1;idle_time=0;hit_ids.clear();rebound=0

func swinging() -> bool:
	return weapon.selected=="baton" and weapon.phase.begins_with("swing_")

func advance(dt: float) -> void:
	var spec: Dictionary=weapon.data.weapons.baton
	rebound=move_toward(rebound,0,dt*5)
	if swinging():
		if weapon.trigger_edge:buffered=true
		# Only the viewmodel clock pauses briefly. Actors/physics keep advancing.
		var frozen:=minf(hitstop,dt);hitstop-=frozen;weapon.phase_time-=frozen
		var window: Array=spec.active_windows[combo]
		var start: float=maxf(float(window[0]),weapon.phase_time-(dt-frozen))
		var end: float=minf(float(window[1]),weapon.phase_time)
		if end>=start and frozen<dt and not wall_feedback:sweep(start,end,window,spec)
		if weapon.phase_time>=weapon.duration:
			weapon.begin("idle",1);idle_time=0
			if buffered or weapon.trigger:start_swing(spec)
	else:
		idle_time+=dt
		if idle_time>float(spec.combo_reset):combo=-1
		if weapon.phase in ["deploy","shove"] and weapon.phase_time>=weapon.duration:weapon.begin("idle",1)
		if weapon.phase=="idle" and weapon.cooldown<=0 and weapon.world.strike_cooldown<=0 and (weapon.trigger_edge or weapon.trigger):start_swing(spec)

func start_swing(spec: Dictionary) -> void:
	combo=(combo+1)%3;serial+=1;buffered=false;hitstop=0;hit_ids.clear();last_hits.clear();blocked=false;wall_feedback=false
	weapon.begin(spec.clips[combo],float(spec.durations[combo]))
	weapon.last_headshot=false;weapon.last_kill=false;weapon.hit_time=0;weapon.corpse_time=0
	weapon.play_sound("baton_swing")
	history.append(combo+1)
	if history.size()>24:history.pop_front()
	weapon.world.last_combat_event="baton:swing_"+str(combo+1)

func sweep(start: float, end: float, window: Array, spec: Dictionary) -> void:
	var world=weapon.world
	var from: Vector3=world.camera.global_position
	var basis: Basis=world.camera.global_basis
	var a:=clampf((start-float(window[0]))/(float(window[1])-float(window[0])),0,1)
	var b:=clampf((end-float(window[0]))/(float(window[1])-float(window[0])),0,1)
	var rays:=0
	# Three temporal samples x three thickness samples, never an unbounded
	# actor scan. Each ray stops at its first wall/door/body-part obstruction.
	for step in range(3):
		var t:=lerpf(a,b,float(step)/2)
		var yaw:=lerpf(.52,-.52,t) if combo==0 else lerpf(-.52,.52,t) if combo==1 else lerpf(.25,-.25,t)
		var pitch:=lerpf(.28,-.25,t) if combo==2 else 0.0
		for thickness in [-.07,0.0,.07]:
			var direction: Vector3=(basis*Vector3(sin(yaw),sin(pitch+thickness),-cos(yaw)*cos(pitch+thickness))).normalized()
			var query:=PhysicsRayQueryParameters3D.create(from,from+direction*float(spec.range),49,[world.player.get_rid()]);query.collide_with_areas=true
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query);rays+=1
			if hit.is_empty():continue
			var collider: Node=hit.collider
			var part: String=collider.get_meta("hit_part","Body")
			var target: Node=collider.get_meta("shot_owner",collider)
			if not target.has_method("receive_hit"):
				blocked=true
				if not wall_feedback:
					wall_feedback=true;hitstop=.045;rebound=1;weapon.play_sound("baton_wall");weapon.impact(hit.position,hit.normal,false)
					world.feedback.melee_impact(combo,false)
				# A solid object arrests the stroke. Do not continue the arc
				# around a door frame after visibly striking it.
				peak_rays=maxi(peak_rays,rays);return
			if not target.active or hit_ids.has(target.get_instance_id()) or hit_ids.size()>=3:continue
			hit_ids[target.get_instance_id()]=true
			var living: bool=target.mode!="dead"
			var head:=part=="Head"
			var damage: float=float(spec.damage[combo])*(1.5 if head else 1.0)
			var push: Vector3=(-basis.z*.8+basis.x*(-.65 if combo==0 else .65 if combo==1 else -.08)).normalized()*(.6 if combo==2 else .3);push.y=0
			target.receive_hit(damage,push,{"weapon":"baton","head":head,"part":part,"point":hit.position,"finisher":combo==2,"direction":(-basis.z*.8+basis.x*(-.65 if combo==0 else .65 if combo==1 else -.08)).normalized()})
			last_hits.append({"id":str(target.definition.id),"damage":damage if living else 0,"part":part,"time":weapon.phase_time,"distance":from.distance_to(hit.position),"hp":target.hp,"living":living})
			if living:total_hits+=1;weapon.confirm_hit(head,target.mode=="dead")
			else:weapon.confirm_corpse(hit.position,"baton",part)
			if not weapon.simulation_only:weapon.blood_fx.blood(hit.position,hit.normal,-basis.z,"baton",head,living and target.mode=="dead",1,living)
			if living:weapon.play_sound("baton_hit")
			hitstop=.035;rebound=.65
			world.feedback.melee_impact(combo,living)
			world.last_combat_event="baton:hit:"+str(target.definition.id)
	peak_rays=maxi(peak_rays,rays)

func observe() -> Dictionary:
	return {"combo":combo+1,"serial":serial,"history":history.duplicate(),"buffered":buffered,"hitstop":hitstop,"hits":last_hits.duplicate(true),"total_hits":total_hits,"blocked":blocked,"peak_rays":peak_rays,"rebound":rebound}
