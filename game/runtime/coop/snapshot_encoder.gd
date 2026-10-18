extends RefCounted
## At most one immutable encoding job. Gameplay/RPCs stay on the main thread;
## the other core quantizes, compresses and makes parity from copied values.
const Wire=preload("res://coop/snapshot_wire.gd")
const Buffer=preload("res://coop/snapshot_buffer.gd")
var task := -1
var result: Dictionary={}
var worker_usec := 0

static func encode(wires: Dictionary,parity: bool) -> Dictionary:
	var encoded: Dictionary={}
	for key in wires:
		var raw:=var_to_bytes(Wire.encode(wires[key]))
		var compressed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
		encoded[key]={"size":raw.size(),"bytes":compressed,"parts":Buffer.shards(compressed,parity)}
	return encoded

func submit(wires: Dictionary,parity: bool) -> bool:
	if task>=0:return false
	# No caller-owned mutable containers cross the thread boundary.
	var owned:=wires.duplicate(true)
	task=WorkerThreadPool.add_task(func():
		var start:=Time.get_ticks_usec()
		result=encode(owned,parity);worker_usec=Time.get_ticks_usec()-start
	,false,"Bank snapshot encoding")
	return true

func take() -> Dictionary:
	if task<0 or not WorkerThreadPool.is_task_completed(task):return {}
	WorkerThreadPool.wait_for_task_completion(task);task=-1
	var value:=result;result={}
	return value

func reset() -> void:
	if task>=0:WorkerThreadPool.wait_for_task_completion(task)
	task=-1;result={};worker_usec=0
