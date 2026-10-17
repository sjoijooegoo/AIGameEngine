extends "frontend_driver.gd"
## Debug-only fixed inspection views around normal menu entry.
var reference := ""
var inspection: Camera3D
const VIEWS={"cash":[16.0,.04,7.0,0.0,0.0],"lobby":[36.0,.04,16.0,-.55,0.0],"meeting":[24.0,3.64,21.0,0.0,0.0],"floor3":[20.0,7.24,7.0,0.0,0.0],"floor4":[10.0,10.84,7.2,0.0,0.0]}

func boot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lighting-reference="):reference=arg.trim_prefix("--lighting-reference=")
	if reference.is_empty():await super.boot();return
	var script=load("res://scripts/line_luminaire_preview.gd" if reference=="preview" else "res://scripts/exploration.gd")
	var world=script.new();world.name="ReferenceBank";root.add_child(world);current_scene=world
	world.testing=true;world.frozen_presentation=true
	await process_frame;write_json("ready.json",{"ready":true})

func inspect() -> Dictionary:
	var result: Dictionary=super.inspect() if reference.is_empty() else {"reference":reference,"lighting":current_scene.indirect_stats}
	if current_scene is Node3D:
		var profile=current_scene.get_meta("bank_hanging_lights") if current_scene.has_meta("bank_hanging_lights") else null
		result.room_lighting=profile.observe() if profile!=null else {}
		result.diffuse_nodes=current_scene.find_children("*_Diffuse","OmniLight3D",false,false).size()
		result.profile_copies=[]
		for copies in current_scene.viewmodel_lighting.targets:
			for i in current_scene.viewmodel_lighting.slots.size():
				var source=current_scene.viewmodel_lighting.slots[i].source
				if source is OmniLight3D:result.profile_copies.append(copies[i].omni.light_projector==source.light_projector)
	return result

func execute(request: Dictionary) -> void:
	if request.command=="lighting_play_fixture":
		assert(reference.is_empty() and not current_scene.coop.active)
		if is_instance_valid(inspection):inspection.free()
		current_scene.camera.current=true;current_scene.frozen_presentation=true
		current_scene.ui.show()
		current_scene.reset_fixture("review_G_cash")
		write_json("response.json",{"id":request.id,"result":{"state":inspect()}});busy=false;return
	if request.command=="lighting_view":
		assert(VIEWS.has(request.name))
		var world=current_scene;var view: Array=VIEWS[request.name]
		if not is_instance_valid(inspection):inspection=Camera3D.new();world.add_child(inspection)
		inspection.position=Vector3(view[0],view[1]+1.62,view[2]);inspection.rotation=Vector3(view[4],view[3],0)
		inspection.fov=world.camera.fov;inspection.current=true
		# Static inspection only: hide moving actors and first-person overlays.
		# Gameplay movement and entry are verified beforehand via normal input.
		world.held_weapon.hide();world.firearms.view.hide()
		world.ui.hide()
		if reference.is_empty() and world.coop.panel:world.coop.panel.hide()
		for actor in world.infected:actor.hide()
		world.flashlight.visible=false;world.flashlight_lighting.advance(0.0)
		world.indoor_lights.update(inspection)
		await process_frame;await process_frame
		write_json("response.json",{"id":request.id,"result":{"state":inspect()}});busy=false;return
	if request.command=="quit" and not reference.is_empty():
		write_json("response.json",{"id":request.id,"result":{}});quit();return
	await super.execute(request)
