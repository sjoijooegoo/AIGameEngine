extends SceneTree
## Independent brute-force contract for the production spatial cache.
class Actor extends CharacterBody3D:
	var collision_radius := .34
	var active := true
	var mode := "idle"

func _initialize() -> void:call_deferred("run")

func expected(actors: Array, position: Vector3) -> Array:
	var result: Array=[]
	var origin:=Vector2i(floori(position.x/1.5),floori(position.z/1.5))
	for actor in actors:
		var c:=Vector2i(floori(actor.position.x/1.5),floori(actor.position.z/1.5))
		if actor.active and actor.mode!="dead" and absi(c.x-origin.x)<=1 and absi(c.y-origin.y)<=1:result.append(actor)
	return result

func reference_separation(actor: CharacterBody3D, actors: Array) -> Vector3:
	var result:=Vector3.ZERO
	for other in actors:
		if other==actor or not other.active or other.mode=="dead":continue
		var apart: Vector3=actor.global_position-other.global_position
		if absf(apart.y)>.65:continue
		apart.y=0
		var radius: float=actor.collision_radius+other.collision_radius+.10
		if apart.length_squared()>=radius*radius:continue
		var length:=apart.length()
		if length>.01 and length<radius:result+=apart/length*(1-length/radius)
	return result.limit_length(.65)

func run() -> void:
	var crowd=load("res://scripts/infected_crowd.gd").new()
	var actors: Array=[];var rng:=RandomNumberGenerator.new();rng.seed=43291
	for i in 84:
		var actor:=Actor.new();root.add_child(actor);actors.append(actor)
		actor.position=Vector3(rng.randf_range(-8,8),i%4*3.6,rng.randf_range(-8,8))
	var queries:=0
	for tick in 160:
		if tick==60:actors.reverse()
		if tick==80:
			var old=actors[17];actors[17]=Actor.new();root.add_child(actors[17]);old.free()
		crowd.rebuild(actors)
		for i in actors.size():
			var actor=actors[i]
			if i%4==tick%4:
				actor.position+=Vector3(rng.randf_range(-2,2),0,rng.randf_range(-2,2))
				crowd.update(actor)
			var reference:=expected(actors,actor.position)
			assert(crowd.neighbours(actor)==reference,"Neighbour cache changed stable actor order or omitted a cell")
			assert(crowd.near_position(actor.position)==reference,"Repeated cached query differs")
			assert(crowd.separation(actor,reference).is_equal_approx(reference_separation(actor,actors)),"Dense movement separation changed")
			queries+=2
		# Liveness changes are synchronized by the next rebuild, as in the game.
		actors[tick%84].active=tick%3!=0
		actors[(tick+11)%84].mode="dead" if tick%5==0 else "idle"
	print("CROWD_CACHE_PASS queries=",queries," moves/deaths/reactivation/reorder/replacement")
	quit()
