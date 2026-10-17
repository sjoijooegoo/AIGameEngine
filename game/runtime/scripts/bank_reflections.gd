extends RefCounted
## Static-only reflections: no actors, animated doors or first-person weapons.
var pending: Array=[]
func build(world: Node3D) -> void:
	var groups: Array=[
		[Vector3(16,1.65,18),Vector3(18,3.1,10)],
		[Vector3(20,1.65,5),Vector3(22,3.1,8)],
		[Vector3(34,1.65,12),Vector3(10,3.1,11)],
		# Upper-floor probes follow actual partition rectangles. A cubemap from
		# the corridor must not be projected across unrelated closed rooms.
		[Vector3(21,5.25,6),Vector3(7.7,3.1,5.7)],
		[Vector3(8,5.25,16),Vector3(11.7,3.1,12.7)],
		[Vector3(24,5.25,15.5),Vector3(19.7,3.1,12.7)],
		[Vector3(11,8.85,6.25),Vector3(9.7,3.1,6.2)],
		[Vector3(8,8.85,18.75),Vector3(15.7,3.1,6.2)],
		[Vector3(27,8.85,12),Vector3(13.7,3.1,7.7)],
		[Vector3(20,12.45,4),Vector3(11.7,3.1,7.7)],
		[Vector3(30,12.45,4),Vector3(7.7,3.1,7.7)],
		[Vector3(30,12.45,15),Vector3(7.7,3.1,13.7)],
		[Vector3(20,12.45,15),Vector3(11.7,3.1,13.7)]
	]
	for floor_index in 4:groups.append([Vector3(38.5,floor_index*3.6+1.65,7.2),Vector3(2.65,3.1,3.1)])
	for i in groups.size():
		var probe:=ReflectionProbe.new()
		probe.name="BankReflection"+str(i)
		probe.position=groups[i][0];probe.size=groups[i][1]
		probe.box_projection=true;probe.interior=true
		probe.ambient_mode=ReflectionProbe.AMBIENT_DISABLED
		probe.intensity=.8;probe.blend_distance=.3
		probe.cull_mask=1 << 19
		probe.reflection_mask=31
		probe.enable_shadows=true
		probe.update_mode=ReflectionProbe.UPDATE_ONCE
		probe.visible=false
		world.add_child(probe)
		pending.append(probe)
	# Reflection capture stays independent of floor-dependent shadow layers.
	# Doors are deliberately excluded, to avoid frozen closed-door reflections.
	for visual in world.find_children("*","VisualInstance3D",true,false):
		if visual is not GeometryInstance3D:continue
		var parent: Node=visual;var moving:=false
		while parent!=null and parent!=world:
			if parent in world.doors.values():moving=true;break
			parent=parent.get_parent()
		if not moving:preload("res://scripts/render_layers.gd").assign(visual,visual.layers | (1 << 19))

func update(camera: Camera3D) -> void:
	if camera==null:return
	# Capture each room only after its floor lights are active. A visited probe
	# stays static; gameplay resets do not create periodic cubemap updates.
	for probe: ReflectionProbe in pending.duplicate():
		if absf(camera.global_position.y-probe.global_position.y)<1.65:
			probe.visible=true
			pending.erase(probe)
