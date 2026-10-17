extends RefCounted
## Several in-flight snapshots, with one XOR parity shard per snapshot.
## Bounds apply before allocation/decompression; no objects are deserialized.
const SHARD := 900
const MAX_WIRE := 115200
const MAX_RAW := 1048576
const MAX_FRAMES := 8
const MAX_BUFFER := 262144
const TTL_MS := 1500
var frames: Dictionary={}
var allocated := 0
var completed := 0
var recovered := 0
var expired := 0
var rejected := 0

func reset() -> void:
	frames.clear();allocated=0

static func shards(bytes: PackedByteArray) -> Array:
	var rows: Array=[];var parity:=PackedByteArray();parity.resize(SHARD)
	for offset in range(0,bytes.size(),SHARD):
		var part:=bytes.slice(offset,offset+SHARD);rows.append(part)
		for i in part.size():parity[i]=parity[i]^part[i]
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
	if raw_size<1 or raw_size>MAX_RAW or wire_size<1 or wire_size>MAX_WIRE or count!=ceili(float(wire_size)/SHARD) or index<0 or index>count:
		rejected+=1;return {}
	var expected:=SHARD if index==count or index<count-1 else wire_size-SHARD*(count-1)
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
	var missing: Array=[]
	for i in count:
		if not f.parts.has(i):missing.append(i)
	if missing.size()==1 and f.parts.has(count):
		var rebuilt: PackedByteArray=f.parts[count].duplicate()
		for i in count:
			if f.parts.has(i):
				for j in f.parts[i].size():rebuilt[j]=rebuilt[j]^f.parts[i][j]
		var lost: int=missing[0]
		if lost==count-1:rebuilt.resize(wire_size-SHARD*(count-1))
		f.parts[lost]=rebuilt;missing.clear();recovered+=1
	if not missing.is_empty():return {}
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
