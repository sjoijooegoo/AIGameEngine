extends RefCounted
## Every delta is relative to an acknowledged, immutable full snapshot, never
## the previous unreliable delta. Loss/reordering cannot erase a persistent edit.
const MAX_BASES := 4
const ROW_FIELDS := 22
var bases: Dictionary={}
var acknowledgements: Dictionary={}
var epoch := -1
var full_received := 0
var delta_received := 0
var missing_base := 0

func reset(round_number: int=-1) -> void:
	bases.clear();acknowledgements.clear();epoch=round_number

func remember(tick: int, packet: Dictionary) -> void:
	# Packets and their children are immutable after construction/decoding.
	bases[tick]=packet
	while bases.size()>MAX_BASES:bases.erase(bases.keys().min())

func acknowledge(peer_id: int, round_number: int, tick: int) -> void:
	if round_number==epoch and bases.has(tick) and tick>int(acknowledgements.get(peer_id,-1)):
		acknowledgements[peer_id]=tick

static func full(packet: Dictionary, keyframe: bool=false) -> Dictionary:
	return {"base":-1,"round":packet.round,"state":packet,"keyframe":keyframe}

static func fields(now: Dictionary, before: Dictionary) -> Dictionary:
	var changed: Dictionary={}
	for key in now:
		if not before.has(key) or now[key]!=before[key]:changed[key]=now[key]
	return changed

func encode(packet: Dictionary, base_tick: int) -> Dictionary:
	if not bases.has(base_tick):return full(packet)
	var base: Dictionary=bases[base_tick]
	if packet.round!=base.round or packet.enemies.size()!=base.enemies.size():return full(packet)
	var result: Dictionary={"base":base_tick,"round":packet.round,"fields":{},"enemies":[],"doors":fields(packet.doors,base.doors),"team":{},"removed":[]}
	for key in packet:
		if key not in ["enemies","doors","team"] and packet[key]!=base.get(key):result.fields[key]=packet[key]
	for id in packet.team:result.team[id]=fields(packet.team[id],base.team.get(id,{}))
	for id in base.team:
		if not packet.team.has(id):result.removed.append(id)
	for i in packet.enemies.size():
		var row: Array=packet.enemies[i];var old: Array=base.enemies[i]
		if row.size()!=ROW_FIELDS or old.size()!=ROW_FIELDS or row[0]!=old[0]:return full(packet)
		var values: Array=[i,0];var mask:=0
		for field in range(1,ROW_FIELDS):
			if row[field]!=old[field]:mask|=1<<field;values.append(row[field])
		if mask:values[1]=mask;result.enemies.append(values)
	return result

func decode(tick: int, wire: Dictionary, round_number: int) -> Dictionary:
	if wire.get("round",-1)!=round_number or not wire.get("base") is int:return {}
	if epoch!=round_number:reset(round_number)
	var base_tick: int=wire.base
	if base_tick==-1:
		var state=wire.get("state")
		if not state is Dictionary or state.get("round")!=round_number:return {}
		if not state.get("enemies") is Array or state.enemies.size()>256:return {}
		if not state.get("team") is Dictionary or state.team.size()>4 or not state.get("doors") is Dictionary:return {}
		for row in state.enemies:
			if not row is Array or row.size()!=ROW_FIELDS:return {}
		if wire.get("keyframe",false):remember(tick,state)
		full_received+=1;return state
	if not bases.has(base_tick):missing_base+=1;return {}
	if base_tick>=tick:return {}
	for key in ["fields","doors","team"]:
		if not wire.get(key) is Dictionary:return {}
	if not wire.get("enemies") is Array or not wire.get("removed") is Array:return {}
	if wire.enemies.size()>256 or wire.team.size()>4 or wire.removed.size()>4:return {}
	var base: Dictionary=bases[base_tick]
	var result: Dictionary=base.duplicate()
	for key in wire.fields:
		if key in ["team","doors","enemies","round"] or not base.has(key):return {}
	result.merge(wire.fields,true)
	result.doors=base.doors.duplicate();result.doors.merge(wire.doors,true)
	result.team=base.team.duplicate()
	for id in wire.removed:result.team.erase(id)
	for id in wire.team:
		if not wire.team[id] is Dictionary:return {}
		result.team[id]=base.team.get(id,{}).duplicate();result.team[id].merge(wire.team[id],true)
	if result.team.size()>4:return {}
	result.enemies=base.enemies.duplicate()
	var seen: Dictionary={}
	for entry in wire.enemies:
		if not entry is Array or entry.size()<3 or not entry[0] is int or not entry[1] is int:return {}
		var index: int=entry[0];var mask: int=entry[1]
		if index<0 or index>=result.enemies.size() or seen.has(index) or mask<=0 or mask>=(1<<ROW_FIELDS) or mask&1:return {}
		seen[index]=true
		var row: Array=base.enemies[index].duplicate();var cursor:=2
		for field in range(1,ROW_FIELDS):
			if mask&(1<<field):
				if cursor>=entry.size():return {}
				row[field]=entry[cursor];cursor+=1
		if cursor!=entry.size():return {}
		result.enemies[index]=row
	delta_received+=1;return result

func observe() -> Dictionary:
	return {"bases":bases.size(),"full":full_received,"delta":delta_received,"missing_base":missing_base}
