extends RefCounted
## Per-player authority state. The existing bank weapon/feedback rules are reused.
var body: CharacterBody3D
var weapon: Node
var feedback: RefCounted
var hp := 100.0
var dead := false
var hurt_cooldown := 0.0
var strike_cooldown := 0.0
var strike_time := -1.0
var strike_kind := "hit"
var strike_applied := false
var actions: Array=[]
var last_action := 0
var action_budget := 40.0
var shots_seen := 0
var death_age := 0.0

func setup(world: Node3D, player: CharacterBody3D) -> void:
	body=player;body.collision_mask=9
	feedback=preload("res://scripts/combat_feedback.gd").new();feedback.setup(world)
	weapon=preload("res://scripts/firearms.gd").new();world.add_child(weapon)
	weapon.audio.free();weapon.blood_fx.free()
	# Server presentation resources can be shared: weapon timers, ammo, RNG,
	# trigger, feedback and melee state are owned separately by each peer.
	for key in ["view","hud","data","feedback_data","audio","world_flash","impact_mesh","blood_fx"]:
		weapon.set(key,world.firearms.get(key))
	weapon.world=world;weapon.melee.weapon=weapon;weapon.simulation_only=true
	for key in weapon.data.weapons:
		weapon.ammo[key]={"clip":int(weapon.data.weapons[key].capacity),"reserve":int(weapon.data.weapons[key].reserve)}
	weapon.rng.seed=52831+player.slot

func bind(world: Node3D) -> void:
	world.player=body;world.firearms=weapon;world.feedback=feedback
	world.player_hp=hp;world.player_dead=dead;world.hurt_cooldown=hurt_cooldown
	world.strike_cooldown=strike_cooldown;world.strike_time=strike_time
	world.strike_kind=strike_kind;world.strike_applied=strike_applied
	world.pitch=body.aim_pitch;world.update_camera()

func save(world: Node3D) -> void:
	hp=world.player_hp;dead=world.player_dead;hurt_cooldown=world.hurt_cooldown
	strike_cooldown=world.strike_cooldown;strike_time=world.strike_time
	strike_kind=world.strike_kind;strike_applied=world.strike_applied

func state() -> Dictionary:
	return {"hp":hp,"dead":dead,"weapon":weapon.selected,"ammo":weapon.ammo.duplicate(true),
		"phase":weapon.phase,"time":weapon.phase_time,"duration":weapon.duration,"shots":weapon.shots,
		"hit":weapon.hit_time,"head":weapon.last_headshot,"kill":weapon.last_kill,
		"last_shot":weapon.last_shot,"grabbed":feedback.is_grabbed(),"struggles":feedback.struggles,
		"damage_time":feedback.damage_time,"damage_direction":feedback.damage_direction,
		"grabber":str(feedback.grabber.name) if feedback.is_grabbed() else ""}
