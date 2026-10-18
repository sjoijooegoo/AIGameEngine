extends RefCounted
## Several in-flight snapshots with interleaved XOR parity stripes.
## Bounds apply before allocation/decompression; no objects are deserialized.
const SHARD := 900
const MAX_WIRE := 115200
const MAX_RAW := 1048576
const MAX_FRAMES := 8
const MAX_BUFFER := 262144
const TTL_MS := 1500
const STRIPE_DATA := 3
var frames: Dictionary={}
var allocated := 0
var completed := 0
var recovered := 0
var expired := 0
var rejected := 0

func reset() -> void:
	frames.clear();allocated=0

static func parity_count(count: int) -> int:
	return mini(count,maxi(2,ceili(float(count)/STRIPE_DATA)))

static func shards(bytes: PackedByteArray,with_parity: bool=true) -> Array:
	var rows: Array=[]
	for offset in range(0,bytes.size(),SHARD):
		rows.append(bytes.slice(offset,offset+SHARD))
	if not with_parity:return rows
	var count:=rows.size();var stripes:=parity_count(count)
	for stripe in stripes:
		var parity:=PackedByteArray();parity.resize(SHARD)
		for i in range(stripe,count,stripes):
			for j in rows[i].size():parity[j]=parity[j]^rows[i][j]
		rows.append(parity)
	return rows

func discard(t: int) -> void:
	if frames.has(t):allocated-=int(frames[t].used);frames.erase(t)

func prune(now: int, accepted_tick: int) -> void:
	for t in frames.keys():
		if t<=accepted_tick or now-int(frames[t].created)>TTL_MS:
			expired+=1;discard(t)

func receive(t: int,index: int,count: int,raw_size: int,wire_size: int,part: PackedByteArray,now: int,accepted_tick: int) -> Dictionary:
	prune(now,accepted_tick)
	if t<=accepted_tick:return {}
	if raw_size<1 or raw_size>MAX_RAW or wire_size<1 or wire_size>MAX_WIRE or count!=ceili(float(wire_size)/SHARD) or index<0 or index>=count+parity_count(count):
		rejected+=1;return {}
	var expected:=SHARD if index>=count or index<count-1 else wire_size-SHARD*(count-1)
	if part.size()!=expected:rejected+=1;return {}
	if not frames.has(t):
		while frames.size()>=MAX_FRAMES or allocated+part.size()>MAX_BUFFER:
			var oldest: int=frames.keys().min();expired+=1;discard(oldest)
		frames[t]={"created":now,"count":count,"raw":raw_size,"wire":wire_size,"parts":{},"used":0}
	var f: Dictionary=frames[t]
	if f.count!=count or f.raw!=raw_size or f.wire!=wire_size:rejected+=1;discard(t);return {}
	if f.parts.has(index):
		if f.parts[index]!=part:rejected+=1;discard(t)
		return {}
	if allocated+part.size()>MAX_BUFFER:expired+=1;discard(t);return {}
	f.parts[index]=part;f.used+=part.size();allocated+=part.size()
	var missing: Dictionary={};var stripes:=parity_count(count)
	for stripe in stripes:
		var lost: Array=[]
		for i in range(stripe,count,stripes):
			if not f.parts.has(i):lost.append(i)
		if lost.size()>1 or (lost.size()==1 and not f.parts.has(count+stripe)):return {}
		if not lost.is_empty():missing[stripe]=lost[0]
	# Recover only when the entire frame can complete, keeping retained memory
	# bounded by allocated. Adjacent lost data shards land in different stripes.
	for stripe: int in missing:
		var rebuilt: PackedByteArray=f.parts[count+stripe].duplicate()
		for i in range(stripe,count,stripes):
			if f.parts.has(i):
				for j in f.parts[i].size():rebuilt[j]=rebuilt[j]^f.parts[i][j]
		var lost: int=missing[stripe]
		if lost==count-1:rebuilt.resize(wire_size-SHARD*(count-1))
		f.parts[lost]=rebuilt;recovered+=1
	var compressed:=PackedByteArray()
	for i in count:compressed.append_array(f.parts[i])
	discard(t)
	var raw:=compressed.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=raw_size:rejected+=1;return {}
	var value=bytes_to_var(raw)
	if not value is Dictionary:rejected+=1;return {}
	completed+=1
	return value

func observe() -> Dictionary:
	return {"frames":frames.size(),"bytes":allocated,"completed":completed,"recovered":recovered,"expired":expired,"rejected":rejected}
