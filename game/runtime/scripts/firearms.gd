extends Node
## Fixed-step weapon state. Input requests use the same path in play and tests.
var simulation_only := false
var world: Node3D
var view: SubViewportContainer
var hud: Control
var data: Dictionary
var feedback_data: Dictionary
var selected := "pistol"
var ammo: Dictionary={}
var phase := "idle"
var phase_time := 0.0
var duration := 1.0
var cooldown := 0.0
var trigger := false
var trigger_edge := false
var queued_shot := false
var bloom := 0.0
var recoil := Vector2.ZERO
var recoil_velocity := Vector2.ZERO
var hit_time := 0.0
var flash_time := 0.0
var last_headshot := false
var last_kill := false
var corpse_time := 0.0
var corpse_hits := 0
var corpse_landing_cooldown := 0.0
var corpse_landing_events := 0
var last_corpse_hit: Dictionary={}
var shots := 0
var dry_clicks := 0
var last_shot: Dictionary={}
var rng:=RandomNumberGenerator.new()
var effect_rng:=RandomNumberGenerator.new()
var audio=preload("res://scripts/weapon_audio.gd").new()
var effects: Array=[]
var impact_mesh: QuadMesh
var event_flags: Dictionary={}
var world_flash: OmniLight3D
var melee=preload("res://scripts/baton_combat.gd").new()
var blood_fx=preload("res://scripts/impact_effects.gd").new()

func setup(game: Node3D, layer: CanvasLayer) -> void:
	world=game
	melee.weapon=self
	world.add_child(blood_fx);blood_fx.setup(world)
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/firearms.json"))
	feedback_data=JSON.parse_string(FileAccess.get_file_as_string("res://data/shooting_feedback.json"))
	blood_fx.tuning=feedback_data.get("blood",{})
	view=preload("res://scripts/firearm_view.gd").new();layer.add_child(view);view.setup(data.pins)
	hud=preload("res://scripts/firearm_hud.gd").new();hud.weapon=self;layer.add_child(hud)
	add_child(audio);audio.setup()
	world_flash=OmniLight3D.new();world_flash.light_bake_mode=Light3D.BAKE_DISABLED;world_flash.omni_range=4;world_flash.light_color=Color(1,.65,.3);world.camera.add_child(world_flash);world_flash.position=Vector3(.12,-.1,-.3);world_flash.visible=false
	# Prepare the shared bullet mark surface during loading. Otherwise the
	# first wall hit pays material/pipeline setup on the firing frame.
	impact_mesh=QuadMesh.new();impact_mesh.size=Vector2.ONE*.035
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/bullet_mark.gdshader");material.set_shader_parameter("mark_color",Color("292522"));impact_mesh.material=material
	var warmup:=MeshInstance3D.new();warmup.mesh=impact_mesh;warmup.visible=false;world.add_child(warmup)

func reset(weapon: String) -> void:
	selected=weapon;phase="idle";phase_time=0;duration=1;cooldown=0;trigger=false;trigger_edge=false;queued_shot=false
	melee.reset()
	last_kill=false;blood_fx.reset()
	corpse_time=0;corpse_hits=0;corpse_landing_cooldown=0;corpse_landing_events=0;last_corpse_hit.clear()
	bloom=0;recoil=Vector2.ZERO;recoil_velocity=Vector2.ZERO;hit_time=0;flash_time=0;shots=0;dry_clicks=0;last_shot={};last_headshot=false;rng.seed=52831;effect_rng.seed=48317;event_flags.clear()
	for key in data.weapons:ammo[key]={"clip":int(data.weapons[key].capacity),"reserve":int(data.weapons[key].reserve)}
	for e in effects:e.node.queue_free()
	effects.clear();view.reset();world_flash.visible=false
	audio.reset()
	update_view(false,10,0)

func select_weapon(key: String) -> void:
	if world.player_dead or world.feedback.is_grabbed() or key==selected:return
	clear_input();selected=key;bloom=0
	if key=="torch":begin("idle",1)
	else:begin("deploy",float(data.weapons[key].deploy));cooldown=maxf(cooldown,duration);play_sound("baton_swing" if key=="baton" else "slide")
	update_view(false,10,0)

func clear_input() -> void:
	trigger=false;trigger_edge=false;queued_shot=false
	audio.cancel_mechanical()
	if melee.swinging():begin("idle",1)
	melee.cancel()

func cancel_for_grab() -> void:
	clear_input();begin("grab_hold",1);flash_time=0

func end_grab() -> void:
	clear_input()
	if phase=="grab_hold":begin("idle",1)

func press_trigger(down: bool) -> void:
	if down and not trigger:trigger_edge=true
	trigger=down

func reload() -> void:
	if selected in ["torch","baton"] or world.player_dead or world.feedback.is_grabbed() or phase.begins_with("reload") or phase=="insert_shell" or phase in ["deploy","shove"] or cooldown>0:return
	var spec: Dictionary=data.weapons[selected]
	if ammo[selected].clip>=int(spec.capacity) or ammo[selected].reserve==0:return
	queued_shot=false
	if selected=="pistol":begin("reload_empty" if ammo.pistol.clip==0 else "reload",float(spec.reload_empty if ammo.pistol.clip==0 else spec.reload))
	else:begin("reload_start",float(spec.reload_start))

func shove() -> bool:
	if world.player_dead or world.strike_cooldown>0 or phase=="deploy":return false
	audio.cancel_mechanical()
	queued_shot=false
	melee.cancel()
	if selected!="torch":begin("shove",.52)
	cooldown=maxf(cooldown,.52)
	return true

func begin(next: String, seconds: float) -> void:
	phase=next;phase_time=0;duration=seconds;event_flags.clear()

func play_sound(key: String, gain: float=0) -> void:
	if simulation_only:return
	# Bank-specific room boundary: the rear yard is outside z=0. This is a
	# restrained room return, not propagation, portals or acoustic ray tracing.
	var p: Vector3=world.player.global_position
	audio.play_event(key,gain,p.z>=0 and p.z<=24 and p.x>=0 and p.x<=40)

func timed_sound(key: String, when: float, eject_shell: bool=false) -> void:
	if phase_time>=when and not event_flags.has(key):
		event_flags[key]=true;play_sound(key)
		if eject_shell and not simulation_only:view.eject(selected)

func advance(dt: float, moving: bool, wall: float) -> void:
	audio.advance(dt)
	corpse_time=maxf(0,corpse_time-dt);corpse_landing_cooldown=maxf(0,corpse_landing_cooldown-dt)
	hit_time=maxf(0,hit_time-dt);flash_time=maxf(0,flash_time-dt);cooldown=maxf(0,cooldown-dt)
	bloom=move_toward(bloom,0,dt*5)
	recoil_velocity+=(-34*recoil_velocity-289*recoil)*dt
	recoil+=recoil_velocity*dt
	world.update_camera()
	blood_fx.advance(dt)
	for e in effects.duplicate():
		e.age+=dt
		if e.has("velocity"):
			e.velocity.y-=6*dt;e.node.position+=e.velocity*dt
			e.node.scale=Vector3.ONE*maxf(.05,1-e.age/e.life)
		if e.age>=e.life:e.node.queue_free();effects.erase(e)
	if world.player_dead:
		clear_input();flash_time=0;world_flash.visible=false;view.visible=false;hud.queue_redraw();return
	phase_time+=dt
	if selected=="baton" and not world.feedback.is_grabbed():melee.advance(dt)
	elif selected!="torch" and not world.feedback.is_grabbed():
		var spec: Dictionary=data.weapons[selected]
		if phase in ["reload","reload_empty"] and selected=="pistol":
			timed_sound("mag_out",duration*.23);timed_sound("mag_in",duration*.68)
			if phase=="reload_empty":timed_sound("slide",duration*.89)
		if phase=="insert_shell":timed_sound("shell",duration*.75)
		if phase=="fire" and selected=="shotgun":timed_sound("pump",duration*.46,true)
		if phase=="reload_end":timed_sound("pump",duration*.35)
		if phase_time+0.000001>=duration:
			match phase:
				"reload","reload_empty":
					ammo[selected].clip=int(spec.capacity);begin("idle",1)
				"reload_start":begin("insert_shell",float(spec.reload_loop))
				"insert_shell":
					ammo.shotgun.clip+=1;ammo.shotgun.reserve-=1
					if ammo.shotgun.clip>=int(spec.capacity) or ammo.shotgun.reserve<=0:begin("reload_end",float(spec.reload_end))
					else:begin("insert_shell",float(spec.reload_loop))
				"fire_last":begin("empty",1)
				"fire","deploy","shove","reload_end":begin("idle",1)
		var request: bool=trigger_edge or queued_shot or selected=="shotgun" and trigger
		if request and selected=="shotgun" and phase in ["reload_start","insert_shell"] and ammo.shotgun.clip>0:
			queued_shot=true;begin("reload_end",float(spec.reload_end))
		elif request and phase in ["idle","fire","fire_last","empty"] and cooldown<=0 and world.strike_cooldown<=0:
			queued_shot=false
			if ammo[selected].clip>0:fire(moving)
			elif trigger_edge:dry_clicks+=1;play_sound("dry");cooldown=.2
	trigger_edge=false
	update_view(moving,wall,dt)

func update_view(moving: bool, wall: float, dt: float) -> void:
	if simulation_only:return
	world.held_weapon.visible=selected=="torch" and not world.player_dead
	var clip:=phase
	if phase=="reload_start":clip="reload"
	if phase=="empty":clip="fire_last"
	if phase=="grab_hold":clip="shove"
	view.feedback_rotation=world.feedback.camera_rotation;view.feedback_offset=world.feedback.weapon_offset()
	if selected=="baton":view.feedback_offset+=Vector3(0,-.008,.012)*melee.rebound
	view.sample(selected,clip,duration if phase=="empty" else duration*(.18+.015*sin(world.feedback.grab_time*8)) if phase=="grab_hold" else phase_time,duration,moving,wall,flash_time,dt)
	world_flash.visible=flash_time>0;world_flash.light_energy=flash_time*35
	if selected!="torch":world.flashlight.transform=Transform3D(Basis.IDENTITY,Vector3(.12,-.08,-.25))
	hud.queue_redraw()

func fire(moving: bool) -> void:
	var spec: Dictionary=data.weapons[selected]
	ammo[selected].clip-=1;shots+=1;cooldown=float(spec.cycle);flash_time=.05;play_sound(selected)
	begin("fire_last" if selected=="pistol" and ammo.pistol.clip==0 else "fire",float(spec.cycle) if selected=="shotgun" else float(data.pins.pistol.clips.fire))
	var from: Vector3=world.camera.global_position
	var basis: Basis=world.camera.global_basis
	var spread: float=float(spec.moving_spread if moving else spec.standing_spread)+bloom
	var hits: Dictionary={};var impacts: Array=[];last_headshot=false;last_kill=false;hit_time=0;corpse_time=0
	# All shots start at the camera and stop at the FIRST physics obstruction.
	# The viewmodel is cosmetic; barrel reach cannot bypass walls or closed doors.
	for pellet in range(int(spec.pellets)):
		var sx:=rng.randf_range(-.5,.5)+rng.randf_range(-.5,.5)
		var sy:=rng.randf_range(-.5,.5)+rng.randf_range(-.5,.5)
		var horizontal: float=spread+float(spec.get("scatter_yaw",0))
		var vertical: float=spread+float(spec.get("scatter_pitch",0))
		var direction: Vector3=(basis*Vector3(tan(deg_to_rad(sx*horizontal)),tan(deg_to_rad(sy*vertical)),-1)).normalized()
		# Actor movement capsules (layer 8) are wider than the mesh and would
		# intercept arm/leg hits before the animated body-part areas.
		var query:=PhysicsRayQueryParameters3D.create(from,from+direction*float(spec.range),49,[world.player.get_rid()]);query.collide_with_areas=true
		var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():continue
		var target: Node=hit.collider
		var part: String=target.get_meta("hit_part","Body")
		var is_head: bool=part=="Head"
		if target.has_meta("shot_owner"):target=target.get_meta("shot_owner")
		var living: bool=target.has_method("receive_hit") and target.active and target.mode!="dead"
		var damageable: bool=target.has_method("receive_hit") and target.active
		var distance: float=from.distance_to(hit.position)
		if damageable:
			var falloff: float=maxf(0,distance-float(spec.get("falloff_start",0)))
			var damage: float=float(spec.damage)*pow(float(spec.range_modifier),falloff/12.7)*(float(spec.head_multiplier) if is_head else 1.0)
			if selected=="pistol" and is_head:
				damage=float(spec.head_damage_near if distance<=float(spec.head_near_distance) else spec.head_damage_far)
			if not hits.has(target):hits[target]={"damage":0.0,"pellets":0,"head":false,"point":hit.position,"normal":hit.normal,"parts":{},"contacts":[],"living":living,"distance":distance,"head_distance":INF}
			hits[target].contacts.append({"part":part,"point":hit.position,"direction":direction})
			hits[target].distance=minf(hits[target].distance,distance)
			if is_head:hits[target].head_distance=minf(hits[target].head_distance,distance)
			if is_head:hits[target].point=hit.position;hits[target].normal=hit.normal
			hits[target].damage+=damage;hits[target].pellets+=1;hits[target].head=hits[target].head or is_head
			hits[target].parts[part]=int(hits[target].parts.get(part,0))+1
			last_headshot=last_headshot or (is_head and living)
		else:impact(hit.position,hit.normal,false)
		impacts.append({"position":[hit.position.x,hit.position.y,hit.position.z],"enemy":str(target.name) if damageable else "","head":is_head,"part":part,"distance":distance})
	var damaged: Array=[]
	for enemy in hits:
		var push: Vector3=-basis.z;push.y=0
		var hit_part: String="Head" if hits[enemy].head else "Body"
		if not hits[enemy].head:
			var most:=0
			for part in hits[enemy].parts:
				if hits[enemy].parts[part]>most:most=hits[enemy].parts[part];hit_part=part
		var info: Dictionary={"weapon":selected,"head":hits[enemy].head,"part":hit_part,"point":hits[enemy].point,"pellets":int(hits[enemy].parts.get(hit_part,0)),"total_pellets":hits[enemy].pellets,"direction":-basis.z,"contacts":hits[enemy].contacts,"distance":hits[enemy].distance}
		if selected=="shotgun":
			var tuning: Dictionary=feedback_data.shotgun
			info.blast=clampf((float(tuning.falloff_distance)-float(hits[enemy].distance))/(float(tuning.falloff_distance)-float(tuning.full_force_distance)),0,1)*clampf(float(hits[enemy].pellets)/float(tuning.full_force_pellets),0,1)
			info.head_burst=hits[enemy].head_distance<=float(tuning.head_burst_distance) and int(hits[enemy].parts.get("Head",0))>=int(tuning.head_burst_pellets)
		var had_head: bool=not enemy.ragdoll.head_destroyed
		enemy.receive_hit(hits[enemy].damage,push.normalized()*(1.0 if selected=="shotgun" else .25),info)
		var killed: bool=hits[enemy].living and enemy.mode=="dead"
		var head_burst: bool=had_head and enemy.ragdoll.head_destroyed
		if not simulation_only:blood_fx.blood(hits[enemy].point,hits[enemy].normal,-basis.z,selected,hits[enemy].head,killed,hits[enemy].pellets,hits[enemy].living,head_burst)
		if hits[enemy].living:confirm_hit(hits[enemy].head,killed)
		else:confirm_corpse(hits[enemy].point,selected,hit_part)
		damaged.append({"id":str(enemy.definition.id),"damage":hits[enemy].damage if hits[enemy].living else 0,"pellets":hits[enemy].pellets,"head":hits[enemy].head,"head_pellets":int(hits[enemy].parts.get("Head",0)),"distance":hits[enemy].distance,"blast":info.get("blast",0),"head_burst":head_burst,"remaining_hp":enemy.hp,"living":hits[enemy].living})
	if hit_time>0 and not hits.is_empty():play_sound("hit_head" if last_headshot else "hit_flesh")
	last_shot={"tick":world.tick_count,"weapon":selected,"pellets":int(spec.pellets),"spread":spread,"hits":damaged,"impacts":impacts}
	world.last_combat_event="shot:"+selected+":"+str(hits.size())
	bloom=minf(float(spec.max_bloom),bloom+1)
	recoil.x=minf(.18,recoil.x+deg_to_rad(float(spec.punch)));recoil.y+=deg_to_rad(rng.randf_range(-.25,.25))
	recoil_velocity.x+=deg_to_rad(float(spec.punch))*3
	if selected=="pistol":view.eject(selected)
	# Recoil participates in the next shot's aim; the first bullet follows the
	# pre-kick center. Mouse compensation changes base pitch normally.
	world.update_camera()

func confirm_hit(head: bool, killed: bool) -> void:
	last_headshot=last_headshot or head;last_kill=last_kill or killed
	hit_time=maxf(hit_time,.26 if killed else .22 if head else .18)

func confirm_corpse(point: Vector3, weapon: String, part: String) -> void:
	corpse_time=.14;corpse_hits+=1
	last_corpse_hit={"weapon":weapon,"part":part,"point":[point.x,point.y,point.z],"tick":world.tick_count}
	var distance: float=world.camera.global_position.distance_to(point)
	if distance<18:play_sound("corpse_hit",-minf(14,distance*.7))

func corpse_landing(point: Vector3, speed: float) -> void:
	var distance: float=world.camera.global_position.distance_to(point)
	if corpse_landing_cooldown>0 or distance>10:return
	corpse_landing_cooldown=.12;corpse_landing_events+=1
	play_sound("corpse_land",clampf(speed-3,-4,1)-distance)

func impact(point: Vector3, normal: Vector3, flesh: bool) -> void:
	if simulation_only:return
	if flesh:
		blood_fx.blood(point,normal,-world.camera.global_basis.z,selected,false,false,1,true)
		return
	var node:=MeshInstance3D.new();node.mesh=impact_mesh
	world.add_child(node);node.global_position=point+normal*.008
	var up:=Vector3.FORWARD if absf(normal.dot(Vector3.UP))>.98 else Vector3.UP
	node.look_at(node.global_position+normal,up)
	effects.append({"node":node,"age":0.0,"life":10.0})
	while effects.size()>64:effects.pop_front().node.queue_free()

func label() -> String:
	if selected=="torch":return "手电 / 近战"
	if selected=="baton":return "警棍 · 左键连击 / 右键推开"+ (" · 第 %d 击" % (melee.combo+1) if melee.swinging() else "")
	var count: Dictionary=ammo[selected]
	return "%s  %02d / %s%s" % [data.weapons[selected].label,count.clip,"∞" if count.reserve<0 else str(count.reserve),"  装填中" if phase.begins_with("reload") or phase=="insert_shell" else ""]

func observe() -> Dictionary:
	return {"audio":audio.observe(),"selected":selected,"phase":phase,"phase_time":phase_time,"duration":duration,"cooldown":cooldown,"ammo":ammo.duplicate(true),"shots":shots,"dry_clicks":dry_clicks,"bloom":bloom,"recoil":[recoil.x,recoil.y],"last_shot":last_shot.duplicate(true),"view":view.observe(),"trigger":trigger,"queued_shot":queued_shot,"melee":melee.observe(),"blood":blood_fx.observe(),"hit_feedback":{"head":last_headshot,"kill":last_kill,"time":hit_time},"corpse_feedback":{"time":corpse_time,"hits":corpse_hits,"last_hit":last_corpse_hit.duplicate(true),"landing_events":corpse_landing_events}}
