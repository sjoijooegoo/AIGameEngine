extends RefCounted
## Deterministic sampled support graph. Static clearance is measured against
## the actual bank collision geometry; door portals are enabled dynamically.
const CELL := .5
var graph := AStar3D.new()
var game: Node3D
var columns: Dictionary = {}
var door_points: Dictionary = {}
var door_open: Dictionary = {}
var leaf_rids: Array[RID] = []
var capsule := CapsuleShape3D.new()
var ready := false
var revision := 0
var queries_this_frame := 0
var queries_total := 0
var peak_frame_queries := 0
const MAX_FRAME_QUERIES := 3

func begin_frame() -> void:
	queries_this_frame=0

func can_route() -> bool:
	return queries_this_frame<MAX_FRAME_QUERIES

func build(world: Node3D) -> void:
	game=world;capsule.radius=.31;capsule.height=1.55
	for door in game.doors.values():
		for leaf in door.leaves:leaf_rids.append(leaf.body.get_rid())
	var candidates: Dictionary={}
	for level in game.spec.levels:
		for r in level.floors:
			add_rectangle(candidates,r.x0,r.x1,r.z0,r.z1,float(level.base)+float(r.y))
		for r in level.boxes:
			if r.y1>0 and r.y1<3.1 and abs(r.x1-r.x0)>.6 and abs(r.z1-r.z0)>.6:
				add_rectangle(candidates,r.x0,r.x1,r.z0,r.z1,float(level.base)+float(r.y1))
		for f in level.stairs:
			for ix in range(ceili(f.xa/CELL),floori(f.xb/CELL)+1):
				for iz in range(ceili(minf(f.za,f.zb)/CELL),floori(maxf(f.za,f.zb)/CELL)+1):
					var y: float=level.base+lerpf(f.y0,f.y1,(iz*CELL-f.za)/(f.zb-f.za))
					candidates[Vector3i(ix,roundi(y*1000),iz)]=Vector3(ix*CELL,y,iz*CELL)
	for key in candidates:
		var p: Vector3=candidates[key]
		if not supported(p) or not clear(p):continue
		var id:=graph.get_available_point_id();graph.add_point(id,p)
		var column:=Vector2i(key.x,key.z)
		if not columns.has(column):columns[column]=[]
		columns[column].append(id)
	for cell in columns:
		for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)]:
			for a in columns[cell]:
				for b in columns.get(cell+offset,[]):
					var p:=graph.get_point_position(a);var q:=graph.get_point_position(b)
					if absf(p.y-q.y)>.42:continue
					if not clear((p+q)*.5):continue
					var query:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*.7,q+Vector3.UP*.7,1,leaf_rids)
					if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty():graph.connect_points(a,b)
	for id in game.doors:
		var door=game.doors[id];var def: Dictionary=door.definition
		var points: Array=[]
		for point_id in graph.get_point_ids():
			var p: Vector3=graph.get_point_position(point_id)-door.global_position
			var along: float=absf(p.x) if def.axis=="x" else absf(p.z)
			var normal: float=absf(p.z) if def.axis=="x" else absf(p.x)
			if absf(p.y)<.35 and along<float(def.w)*.5+.15 and normal<.42:points.append(point_id)
		door_points[id]=points
	ready=true;update_doors()

func add_rectangle(result: Dictionary,x0: float,x1: float,z0: float,z1: float,y: float) -> void:
	for ix in range(ceili(minf(x0,x1)/CELL),floori(maxf(x0,x1)/CELL)+1):
		for iz in range(ceili(minf(z0,z1)/CELL),floori(maxf(z0,z1)/CELL)+1):
			result[Vector3i(ix,roundi(y*1000),iz)]=Vector3(ix*CELL,y,iz*CELL)

func supported(p: Vector3) -> bool:
	var q:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*.10,p-Vector3.UP*.17,1,leaf_rids)
	var hit:=game.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.normal.y>.65

func clear(p: Vector3) -> bool:
	var q:=PhysicsShapeQueryParameters3D.new();q.shape=capsule
	q.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*.94);q.collision_mask=1;q.exclude=leaf_rids
	q.margin=.005
	return game.get_world_3d().direct_space_state.intersect_shape(q,1).is_empty()

func update_doors() -> void:
	if not ready:return
	for id in door_points:
		var open: bool=game.doors[id].progress>.82
		if door_open.get(id,null)==open:continue
		door_open[id]=open;revision+=1
		for point in door_points[id]:graph.set_point_disabled(point,not open)

func nearest(p: Vector3,include_closed := false) -> int:
	var best: int=-1;var distance:=INF
	var c:=Vector2i(roundi(p.x/CELL),roundi(p.z/CELL))
	# Expand rings and stop once every unvisited cell is provably farther than
	# the best supported point. Preserve the same 0.65 m height and 4-cell bounds.
	for ring in range(5):
		for x in range(-ring,ring+1):
			for z in range(-ring,ring+1):
				if maxi(absi(x),absi(z))!=ring:continue
				for id in columns.get(c+Vector2i(x,z),[]):
					if not include_closed and graph.is_point_disabled(id):continue
					var q:=graph.get_point_position(id)
					if absf(q.y-p.y)>.65:continue
					var d:=q.distance_squared_to(p)
					if d<distance:distance=d;best=id
		var next_min: float=(ring+1)*CELL-maxf(absf(p.x-c.x*CELL),absf(p.z-c.y*CELL))
		if distance<next_min*next_min:break
	return best

func route(a: Vector3,b: Vector3) -> PackedVector3Array:
	var started: int=game.profiler.mark()
	queries_this_frame+=1;queries_total+=1;peak_frame_queries=maxi(peak_frame_queries,queries_this_frame)
	var start:=nearest(a);var end:=nearest(b)
	var result:=graph.get_point_path(start,end) if start>=0 and end>=0 else PackedVector3Array()
	game.profiler.end_scope("pathfinding",started)
	return result
