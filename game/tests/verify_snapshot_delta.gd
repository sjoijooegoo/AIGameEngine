extends SceneTree
const Codec=preload("res://coop/snapshot_delta.gd")

func packet() -> Dictionary:
	var enemies: Array=[]
	for i in 84:enemies.append([str(i),Vector3(i,0,0),0.0,Vector3.ZERO,65.0,"idle",0.0,0.0,true,{},false,"native/idle",0.0,0.0,0,10.0,.4,"chest","front",Vector3.BACK,0.0,false])
	return {"round":3,"enemies":enemies,"team":{12:{"hp":73,"ammo":14},19:{"hp":100,"ammo":10}},"doors":{"a":[0.0,0.0,1,false]},"kills":0,"wiped":false,"started":true,"leader":12,"reserved":0}

func _initialize() -> void:
	var sender:=Codec.new();var receiver:=Codec.new();sender.reset(3)
	var first:=packet();sender.remember(60,first)
	assert(receiver.decode(60,Codec.full(first,true),3)==first)
	sender.acknowledge(12,3,60);assert(sender.acknowledgements[12]==60)
	var edited:=first.duplicate(true)
	edited.enemies[7][4]=0.0;edited.enemies[7][5]="dead";edited.enemies[7][9]={"revision":1,"seed":{"points":[Vector3.ONE,Vector3.UP]},"impacts":[]}
	edited.enemies[7][10]=true;edited.enemies[21][8]=false
	edited.doors.a=[.7,1.0,-1,false];edited.kills=1;edited.team[12].ammo=13
	edited.team.erase(19);edited.team[25]={"hp":100,"ammo":17}
	var dropped:=sender.encode(edited,60) # Intentionally never delivered.
	var later:=edited.duplicate(true);later.enemies[4][1]+=Vector3(.2,0,0)
	var wire:=sender.encode(later,60)
	assert(receiver.decode(78,wire,3)==later,"A lost previous delta erased a persistent change")
	assert(receiver.decode(72,dropped,3)==edited,"Decoding is base-relative; session rejects tick rewind")
	assert(receiver.bases[60]==first,"Decode mutated the immutable baseline")
	# An ack can refer only to a known base in the current round.
	sender.acknowledge(12,2,60);sender.acknowledge(12,3,999);assert(sender.acknowledgements[12]==60)
	var empty:=Codec.new();assert(empty.decode(78,wire,3).is_empty())
	assert(empty.decode(60,Codec.full(first,true),3)==first)
	assert(empty.decode(84,wire,3)==later,"Late reliable baseline failed to recover")
	for tick in range(100,1000,6):empty.decode(tick,Codec.full(later),3)
	assert(empty.bases.size()==1,"Unacknowledgeable fallback full packets evicted the baseline")
	for tick in [120,180,240,300,360]:empty.decode(tick,Codec.full(later,true),3)
	assert(empty.bases.size()==4 and not empty.bases.has(60))
	assert(empty.decode(400,wire,3).is_empty())
	assert(sender.encode(later,999).base==-1)
	assert(receiver.decode(90,wire,4).is_empty());receiver.reset(4)
	assert(receiver.bases.is_empty() and receiver.acknowledgements.is_empty())
	var bad:=wire.duplicate(true);bad.enemies.append([999,2,Vector3.ZERO])
	var validation:=Codec.new();validation.decode(60,Codec.full(first,true),3)
	assert(validation.decode(400,bad,3).is_empty())
	bad=wire.duplicate(true);bad.enemies=[[0,1,"renamed"]]
	assert(validation.decode(400,bad,3).is_empty())
	bad=wire.duplicate(true);bad.enemies=[[0,2]]
	assert(validation.decode(400,bad,3).is_empty())
	assert(validation.bases[60]==first)
	var visual=load("res://coop/snapshot_wire.gd")
	var precise:=packet();precise.enemies[3][1]=Vector3(13.123456,.123456,21.123456);precise.enemies[3][6]=123.456789
	precise.enemies[3][4]=73.123456;precise.enemies[3][9]={"revision":1,"seed":{"points":[Vector3(13.123456,.123456,21.123456)]},"impacts":[]}
	var normalized: Dictionary=visual.encode(Codec.full(precise,true))
	assert(normalized.state.enemies[3][1].distance_to(precise.enemies[3][1])<.00085)
	assert(absf(normalized.state.enemies[3][6]-precise.enemies[3][6])<=1.0/2048)
	assert(normalized.state.enemies[3][4]==precise.enemies[3][4],"Health is lossless")
	assert(normalized.state.enemies[3][9]==precise.enemies[3][9],"One-time corpse seeds are lossless")
	assert(precise.enemies[3][1]==Vector3(13.123456,.123456,21.123456),"Wire conversion mutated authority state")
	var visual_sender:=Codec.new();visual_sender.reset(3);visual_sender.remember(60,precise)
	var visual_receiver:=Codec.new();visual_receiver.decode(60,normalized,3)
	var moved:=precise.duplicate(true);moved.enemies[3][1]+=Vector3(.23456,0,.12345);moved.enemies[3][9].revision=2;moved.enemies[3][9].impacts=[{"serial":1,"direction":Vector3.RIGHT}]
	var decoded:=visual_receiver.decode(66,visual.encode(visual_sender.encode(moved,60)),3)
	assert(decoded==visual.encode(Codec.full(moved)).state,"Quantized full and base-relative deltas disagree")
	print("BANK_DELTA_PASS loss / reorder / immutable / late base / bounded fallback / round / membership / death / doors")
	quit()
