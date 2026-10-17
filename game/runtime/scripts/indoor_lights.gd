extends RefCounted
## Bank-specific conservative floor visibility. Opaque slabs separate rooms;
## both stair shafts (x<=7 and x>=33) stay lit independently. Near shafts keep
## neighbouring floors ready before their open landings enter the view.
## This only suppresses invisible room lights, never actors or world geometry.
var world: Node3D
var rooms: Array=[]
var enabled := true
var floor_mask := -1
var visible_rooms := 0

func setup(owner_world: Node3D) -> void:
	world=owner_world
	for light in world.get_children():
		# Runtime shadow sampling does not alter the baked irradiance. Keep
		# offsets small at the selected atlas resolution so thin partitions
		# still occlude neighbouring fixtures at a grazing view angle.
		if light is SpotLight3D:
			light.shadow_bias=.04
			light.shadow_normal_bias=.02
		if light is Light3D and light.has_meta("enclosed_floor"):
			rooms.append({"light":light,"floor":int(light.get_meta("enclosed_floor"))})

func update(camera: Camera3D) -> void:
	var mask:=15
	if enabled and camera!=null:
		var p:=camera.global_position
		# Exterior, doorway approach and unusual inspection cameras fail open.
		# This bank's exterior rectangle is x=[0,40], z=[0,24]. Five metres
		# inside each stair-wall plane is a conservative open-door sight margin.
		if p.x>1 and p.x<39 and p.z>1 and p.z<23 and p.y>0 and p.y<14:
			var level:=clampi(floori(p.y/3.6),0,3)
			mask=1 << level
			if p.x<12 or p.x>28:
				if level>0:mask|=1 << (level-1)
				if level<3:mask|=1 << (level+1)
	if mask==floor_mask:return
	floor_mask=mask;visible_rooms=0
	for entry in rooms:
		var show: bool=(mask & (1 << int(entry.floor)))!=0
		entry.light.visible=show
		if show:visible_rooms+=1

func observe() -> Dictionary:
	return {"enabled":enabled,"floor_mask":floor_mask,"visible_room_lights":visible_rooms,"total_room_lights":rooms.size()}
