extends RefCounted
## Incrementally maintained planar neighbourhood. Nearby results retain actor
## order so summation and the original sequential movement semantics stay stable.
const CELL := 1.5
var cells: Dictionary={}
var membership: Dictionary={}
var order: Dictionary={}
var roster: Array=[]
var queries: Dictionary={}

func cell(p: Vector3) -> Vector2i:return Vector2i(floori(p.x/CELL),floori(p.z/CELL))

func rebuild(actors: Array) -> void:
	# Keep membership across ticks; cells contain stable integer roster indices.
	# Replacing/reordering actors (including test fixtures) invalidates everything.
	if roster!=actors:
		cells.clear();membership.clear();order.clear();queries.clear()
		roster=actors.duplicate()
		for i in actors.size():order[actors[i]]=i
	for actor in actors:
		if actor.active and actor.mode!="dead":update(actor)
		else:remove(actor)

func invalidate(origin: Vector2i) -> void:
	for x in range(-1,2):
		for z in range(-1,2):queries.erase(origin+Vector2i(x,z))

func remove(actor: Node3D) -> void:
	if not membership.has(actor):return
	var old: Vector2i=membership[actor]
	cells[old].erase(order[actor]);membership.erase(actor)
	if cells[old].is_empty():cells.erase(old)
	invalidate(old)

func update(actor: Node3D) -> void:
	if not actor.active or actor.mode=="dead":remove(actor);return
	var next:=cell(actor.global_position)
	if membership.get(actor,null)==next:return
	remove(actor)
	if not cells.has(next):cells[next]=[]
	cells[next].append(order[actor]);membership[actor]=next
	invalidate(next)

func neighbours(actor: Node3D) -> Array:
	return near_position(actor.global_position)

func near_position(position: Vector3) -> Array:
	var origin:=cell(position)
	if queries.has(origin):return queries[origin]
	var indices: Array=[];var result: Array=[]
	# Largest combined radius is 1.06 m, smaller than one cell.
	for x in range(-1,2):
		for z in range(-1,2):indices.append_array(cells.get(origin+Vector2i(x,z),[]))
	indices.sort()
	for index in indices:result.append(roster[index])
	# Bound empty queries from moving corpses. Returned arrays are read-only to
	# callers; changes to neighbouring cells invalidate them before reuse.
	if queries.size()>=256:queries.clear()
	queries[origin]=result
	return result
