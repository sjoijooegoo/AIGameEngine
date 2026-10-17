extends RefCounted
## Blend explicit fixed-clock samples, including restarts of the same clip.
## AnimationPlayer's wall-clock blending is intentionally not used by tests.
var rigs: Array=[]
var previous: Array=[]
var elapsed := 1.0
var duration := .1
var active := false
var max_position_step := 0.0

func setup(skeletons: Array) -> void:
	rigs=skeletons

func begin(seconds: float,source_poses: Array=[]) -> void:
	previous.clear();elapsed=0;duration=maxf(seconds,.001);active=true
	if not source_poses.is_empty():previous=source_poses.duplicate(true);return
	for rig in rigs:
		var poses: Array=[]
		for i in range(rig.get_bone_count()):poses.append(rig.get_bone_pose(i))
		previous.append(poses)

func apply(dt: float) -> void:
	if not active:return
	elapsed+=dt
	var t:=smoothstep(0,duration,elapsed)
	for r in range(rigs.size()):
		var rig: Skeleton3D=rigs[r]
		for i in range(rig.get_bone_count()):
			var target:=rig.get_bone_pose(i)
			var pose: Transform3D=previous[r][i].interpolate_with(target,t)
			rig.set_bone_pose(i,pose)
	if elapsed>=duration:active=false;previous.clear()

func reset() -> void:
	previous.clear();active=false;elapsed=1.0
