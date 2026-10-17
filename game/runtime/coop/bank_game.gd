extends "res://scripts/exploration.gd"
## Multiplayer entry around the unchanged bank builder (including baked lighting).
var coop: Node3D

func _ready() -> void:
	super._ready()
	coop=preload("res://coop/bank_session.gd").new();coop.world=self;add_child(coop)
	AppFlow.bank_ready.call_deferred(self)

func advance(dt: float) -> void:
	if coop!=null and coop.active:coop.advance(dt)
	else:super.advance(dt)

func update_camera() -> void:
	if coop!=null and coop.active and coop.is_host:
		camera.global_position=player.global_position+Vector3.UP*1.62
		camera.global_rotation=Vector3(pitch,player.rotation.y,0)
	else:super.update_camera()

func _process(dt: float) -> void:
	if coop!=null and coop.active and coop.is_host:return
	super._process(dt)

func _input(event: InputEvent) -> void:
	if coop!=null and coop.active:
		if testing and not event.get_meta("ai_bridge_input",false):return
		coop.handle_event(event)
	else:super._input(event)

func _notification(what: int) -> void:
	if coop!=null and coop.active:return
	super._notification(what)

func ensure_infected() -> void:
	if not infected_ready:
		navigation.build(self)
		for source in infected_data.enemies:
			var actor=preload("res://scripts/infected.gd").new()
			add_child(actor)
			actor.setup(self,source,infected_data.types[source.type],infected_data.pins[source.model])
			var nearest: int=navigation.nearest(actor.home,true)
			assert(nearest>=0,"No supported infected spawn: "+str(source.id))
			var supported: Vector3=navigation.graph.get_point_position(nearest)
			actor.spawn_adjustment=supported-actor.home
			actor.home=supported;actor.position=supported+Vector3.UP*.04
			infected.append(actor)
		infected_ready=true
		reset_infected(current_fixture)

func is_coop_active() -> bool:
	return coop!=null and coop.active

func return_to_main(multiplayer_page: bool=false) -> void:
	AppFlow.bank=self
	AppFlow.return_menu("multiplayer" if multiplayer_page else "home")

func reset_infected(fixture: String) -> void:
	super.reset_infected(fixture)
	# Only normal solo entry/restart changes population. Combat fixtures and the
	# authoritative multiplayer map keep their original actors and identifiers.
	if fixture!="default" or is_coop_active() or AppFlow.intent.get("mode") in ["multiplayer","server"]:return
	for arg in OS.get_cmdline_user_args():
		if arg=="--server" or arg=="--coop" or arg.begins_with("--connect="):return
	var origin:=Vector3(23,0.04,8.2)
	for enemy in infected:
		if absf(enemy.home.y-origin.y)<1.5 and Vector2(enemy.home.x-origin.x,enemy.home.z-origin.z).length()<8.0:
			enemy.active=false;enemy.visible=false;enemy.collision_layer=0;enemy.collision_mask=0;enemy.head_hitbox.collision_layer=0
