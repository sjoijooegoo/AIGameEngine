extends RefCounted
## Camera forces and the source game's bounded grab/bite/escape interaction.
var world: Node3D
var rotation := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var impulse_position := Vector3.ZERO
var damage_direction := Vector2.ZERO
var damage_time := 0.0
var damage_strength := 0.0
var grabber: CharacterBody3D
var grab_time := 0.0
var grab_blend := 0.0
var grab_cooldown := 0.0
var struggles := 0
var last_struggle := 0
var struggle_cooldown := 0.0
var event := ""
var event_count := 0
var last_damage := 0.0
var last_release := ""
var clock := 0.0
var camera_rotation := Vector3.ZERO
var camera_offset := Vector3.ZERO
var death_blend := 0.0
var peak_angle := 0.0

func setup(game: Node3D) -> void:
	world=game

func reset() -> void:
	rotation=Vector3.ZERO;angular_velocity=Vector3.ZERO;impulse_position=Vector3.ZERO;damage_direction=Vector2.ZERO;damage_time=0;damage_strength=0
	grabber=null;grab_time=0;grab_blend=0;grab_cooldown=0;struggles=0;last_struggle=0;struggle_cooldown=0;event="";event_count=0;last_damage=0;last_release="";clock=0;death_blend=0;peak_angle=0;camera_rotation=Vector3.ZERO;camera_offset=Vector3.ZERO

func is_grabbed() -> bool:
	return is_instance_valid(grabber)

func hit(amount: float, source: Vector3) -> void:
	var direction: Vector3=world.player.global_basis.inverse()*(source-world.player.global_position)
	direction.y=0;direction=direction.normalized()
	damage_direction=Vector2(direction.x,-direction.z)
	damage_time=.45;damage_strength=clampf(amount/30,.25,1)
	var strength:=clampf(amount/22,.4,1.65)
	rotation+=Vector3(-.022,-direction.x*.025,-direction.x*.022)*strength
	angular_velocity+=Vector3(-.14,-direction.x*.13,-direction.x*.11)*strength
	impulse_position-=direction*.018*strength
	last_damage=amount;event="hurt";event_count+=1

func start_grab(enemy: CharacterBody3D) -> bool:
	if is_grabbed() or grab_cooldown>0 or world.player_dead or world.hurt_cooldown>0:return false
	if not enemy.active or enemy.mode=="dead" or not enemy.sees_player():return false
	var delta: Vector3=enemy.global_position-world.player.global_position
	if Vector2(delta.x,delta.z).length()>float(enemy.stats.reach)+.3 or absf(delta.y)>.8:return false
	grabber=enemy;grab_time=0;struggles=0;last_struggle=0;struggle_cooldown=0;event="grab_start";event_count+=1
	world.firearms.cancel_for_grab();world.strike_time=-1
	enemy.set_mode("grab");enemy.velocity.x=0;enemy.velocity.z=0
	rotation.x-=.016;angular_velocity.x-=.12
	return true

func struggle(code: int) -> void:
	if not is_grabbed() or code not in [KEY_A,KEY_D] or code==last_struggle or struggle_cooldown>0:return
	last_struggle=code;struggles+=1;struggle_cooldown=.075
	angular_velocity.z+=(.08 if code==KEY_A else -.08)
	if struggles>=6:release("struggle",true)

func release(reason: String, push := false) -> void:
	var enemy=grabber
	grabber=null;grab_cooldown=1.2;last_release=reason;event="grab_"+reason;event_count+=1
	world.hurt_cooldown=maxf(world.hurt_cooldown,1.2)
	world.firearms.end_grab()
	if is_instance_valid(enemy) and enemy.active and enemy.mode!="dead":
		if reason in ["struggle","shove"]:world.infected_audio.request(enemy,"hurt")
		enemy.stagger=maxf(enemy.stagger,.75);enemy.set_mode("hurt");enemy.cooldown=1.6
		if push:
			var away: Vector3=enemy.global_position-world.player.global_position;away.y=0
			enemy.velocity=away.normalized()*2.1

func advance(dt: float, moving: bool) -> void:
	clock+=dt;damage_time=maxf(0,damage_time-dt);grab_cooldown=maxf(0,grab_cooldown-dt);struggle_cooldown=maxf(0,struggle_cooldown-dt)
	if is_grabbed():
		var enemy=grabber
		var delta: Vector3=enemy.global_position-world.player.global_position
		if world.player_dead or not enemy.active or enemy.mode=="dead":release("cancelled")
		elif Vector2(delta.x,delta.z).length()>1.85 or absf(delta.y)>.8 or not enemy.sees_player():release("separated")
		else:
			grab_time+=dt
			if grab_time>=maxf(.55,1.15-float(struggles)*.05):
				var bite: float=float(enemy.stats.dmg)*(1-minf(.6,float(struggles)*.07))
				world.hurt_player(bite,str(enemy.definition.id),enemy.global_position)
				release("bite",true)
	# A critically damped spring replaces perpetual random camera shake.
	var omega:=17.0
	angular_velocity+=(-2*omega*angular_velocity-omega*omega*rotation)*dt
	rotation+=angular_velocity*dt
	rotation=rotation.clamp(Vector3(-.09,-.07,-.055),Vector3(.09,.07,.055))
	impulse_position=impulse_position.lerp(Vector3.ZERO,1-exp(-dt*14))
	grab_blend=move_toward(grab_blend,1.0 if is_grabbed() else 0.0,dt*7)
	death_blend=move_toward(death_blend,1.0 if world.player_dead else 0.0,dt*2)
	var tug:=Vector3.ZERO
	if is_grabbed():
		var local: Vector3=world.player.global_basis.inverse()*(grabber.global_position-world.player.global_position)
		# Small directional tug, preserving the player's base yaw and mouse input.
		tug=Vector3(.022+sin(grab_time*14)*.003,clampf(atan2(-local.x,-local.z)*.09,-.07,.07),sin(grab_time*11)*.008)*grab_blend
	camera_rotation=rotation+tug+Vector3(-.14,0,-.075)*death_blend
	peak_angle=maxf(peak_angle,camera_rotation.length())
	var bob:=Vector3(sin(clock*8)*.003,abs(sin(clock*8))*.005,0) if moving and not is_grabbed() and not world.player_dead else Vector3.ZERO
	camera_offset=impulse_position+bob+Vector3(0,-.055*grab_blend-.40*death_blend,.018*grab_blend)

func weapon_offset() -> Vector3:
	return Vector3(0,-.055,.035)*grab_blend+Vector3(0,0,damage_time*.025)

func melee_impact(combo: int, flesh: bool) -> void:
	angular_velocity+=Vector3(.055 if combo==2 else .02,.035 if combo==0 else -.035,.025 if combo==0 else -.025)
	impulse_position.z+=.006 if flesh else .009
	event="baton_hit" if flesh else "baton_wall";event_count+=1

func observe() -> Dictionary:
	return {"grabbed":is_grabbed(),"grabber":str(grabber.definition.id) if is_grabbed() else "","grab_time":grab_time,"struggles":struggles,"grab_cooldown":grab_cooldown,"last_release":last_release,"event":event,"event_count":event_count,"last_damage":last_damage,"rotation":[camera_rotation.x,camera_rotation.y,camera_rotation.z],"offset":[camera_offset.x,camera_offset.y,camera_offset.z],"peak_angle":peak_angle,"damage_direction":[damage_direction.x,damage_direction.y]}
