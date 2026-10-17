extends RefCounted
## Original co-located core/skirt plus a faint camera-aligned peripheral fill.
## No source follows surface hits, so crossing foreground/background
## silhouettes cannot move a secondary emitter or switch reflected energy.
var world: Node3D
var spill: SpotLight3D
var peripheral: SpotLight3D
var peripheral_enabled := true
var peripheral_projection := Vector4.ZERO
var enabled := true
var blocked_by_wall := false
# Kept empty for existing inspection routes; no reflected lights are created.
var patches: Array[AreaLight3D]=[]
const BEAM=preload("res://scripts/flashlight_beam.gd")
const SPILL_ENERGY := .5
const SPILL_RANGE := 8.0
const SPILL_HALF_ANGLE := 56.0
const PERIPHERAL_ENERGY := .1
const PERIPHERAL_RANGE := 8.0
# Keep all four viewport corners inside the projector's soft outer shoulder.
const PERIPHERAL_CORNER_RADIUS := .8

func setup(game: Node3D) -> void:
	world=game
	world.flashlight.light_projector=BEAM.projector()
	world.flashlight.light_energy=BEAM.ENERGY
	world.flashlight.spot_range=BEAM.RANGE
	world.flashlight.spot_angle=BEAM.HALF_ANGLE
	world.flashlight.spot_angle_attenuation=.01
	world.flashlight.shadow_bias=.03
	world.flashlight.shadow_normal_bias=.2
	spill=SpotLight3D.new();spill.name="FlashlightSpill"
	spill.spot_angle=SPILL_HALF_ANGLE;spill.spot_angle_attenuation=.01
	spill.spot_range=SPILL_RANGE;spill.spot_attenuation=1.1
	spill.light_energy=SPILL_ENERGY;spill.light_color=world.flashlight.light_color
	spill.light_projector=BEAM.projector(true)
	spill.light_specular=.15
	spill.shadow_enabled=true;spill.shadow_bias=.03;spill.shadow_normal_bias=.03
	spill.light_bake_mode=Light3D.BAKE_DISABLED
	spill.light_cull_mask=31
	world.flashlight.add_child(spill)
	peripheral=SpotLight3D.new();peripheral.name="FlashlightPeripheral"
	peripheral.spot_angle_attenuation=.01
	peripheral.spot_range=PERIPHERAL_RANGE;peripheral.spot_attenuation=1.1
	peripheral.light_energy=PERIPHERAL_ENERGY;peripheral.light_color=world.flashlight.light_color
	peripheral.light_projector=BEAM.projector(false,true)
	peripheral.light_specular=0.0
	peripheral.shadow_enabled=true;peripheral.shadow_bias=.03;peripheral.shadow_normal_bias=.03
	peripheral.light_bake_mode=Light3D.BAKE_DISABLED;peripheral.light_cull_mask=31
	# The weak fill starts at the eye, so nearby geometry and animated lamp
	# sway cannot leave one screen edge outside its cone. It remains a real
	# shadowed light and shares the flashlight's switch and wall safety guard.
	world.camera.add_child(peripheral)
	update_peripheral_coverage()

func update_peripheral_coverage() -> void:
	var size: Vector2=world.camera.get_viewport().get_visible_rect().size
	var signature:=Vector4(size.x,size.y,world.camera.fov,float(world.camera.keep_aspect))
	if signature==peripheral_projection:return
	peripheral_projection=signature
	var corner: Vector3=world.camera.project_local_ray_normal(size)
	var radius:=Vector2(corner.x,corner.y).length()/maxf(-corner.z,.00001)
	peripheral.spot_angle=clampf(rad_to_deg(atan(radius/PERIPHERAL_CORNER_RADIUS)),1.0,85.0)

func advance(_dt: float) -> void:
	var active: bool=enabled and world.flashlight.visible
	blocked_by_wall=false
	if active:
		var guard:=PhysicsRayQueryParameters3D.create(world.camera.global_position,world.flashlight.global_position,1)
		blocked_by_wall=not world.get_world_3d().direct_space_state.intersect_ray(guard).is_empty()
		active=not blocked_by_wall
	# Keep visible as the player's F-toggle state; guard every emission if
	# a weapon animation puts its lamp through a wall. No delayed fade/leak.
	world.flashlight.light_energy=BEAM.ENERGY if active else 0.0
	spill.visible=active
	peripheral.visible=active and peripheral_enabled
	update_peripheral_coverage()

func observe() -> Dictionary:
	return {"enabled":enabled,"spill":spill.visible and world.flashlight.visible,"active_patches":0,"hits":[],"mode":"layered_direct_projector","beam_profile":"continuous_radial_projector","beam_energy":world.flashlight.light_energy,"spill_energy":SPILL_ENERGY,"spill_range":SPILL_RANGE,"spill_half_angle":SPILL_HALF_ANGLE,"peripheral":peripheral.visible,"peripheral_energy":peripheral.light_energy,"peripheral_range":peripheral.spot_range,"peripheral_half_angle":peripheral.spot_angle,"peripheral_origin":"camera","blocked_by_wall":blocked_by_wall,"active_lights":(2 if spill.visible and world.flashlight.visible else 0)+(1 if peripheral.visible else 0)}
