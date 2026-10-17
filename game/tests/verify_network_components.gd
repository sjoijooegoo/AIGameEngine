extends SceneTree
const Buffer=preload("res://coop/snapshot_buffer.gd")

func _initialize() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=7319
	var blob:=PackedByteArray();blob.resize(4400)
	for i in blob.size():blob[i]=rng.randi_range(0,255)
	var packet:={"round":7,"blob":blob,"team":{1:{"hp":73}}}
	var raw:=var_to_bytes(packet);var wire:=raw.compress(FileAccess.COMPRESSION_ZSTD);var shards:=Buffer.shards(wire);var count:=shards.size()-1
	assert(count>=4)
	for lost in shards.size():
		var buffer:=Buffer.new();var decoded: Dictionary={}
		# A later tick starts first; it must not evict the still recoverable older frame.
		buffer.receive(12,0,count,raw.size(),wire.size(),shards[0],10,-1)
		for i in range(shards.size()-1,-1,-1):
			if i==lost:continue
			var value: Dictionary=buffer.receive(6,i,count,raw.size(),wire.size(),shards[i],20,-1)
			if not value.is_empty():decoded=value
		assert(decoded==packet,"out of order/parity reconstruction failed")
		assert(buffer.frames.has(12),"interleaved frame was lost")
		assert(buffer.receive(6,0,count,raw.size(),wire.size(),shards[0],30,6).is_empty())
	var bounded:=Buffer.new()
	for t in 50:bounded.receive(t,0,count,raw.size(),wire.size(),shards[0],t,-1)
	assert(bounded.frames.size()<=8 and bounded.allocated<=262144)
	bounded.prune(2000,-1);assert(bounded.frames.is_empty() and bounded.allocated==0)
	assert(bounded.receive(100,128,129,1048577,115201,shards[0],2001,-1).is_empty())
	assert(bounded.allocated==0 and bounded.rejected==1)
	bounded.receive(101,0,count,raw.size(),wire.size(),shards[0],2100,-1)
	bounded.receive(101,1,count+1,raw.size(),wire.size()+900,shards[1],2101,-1)
	assert(not bounded.frames.has(101),"conflicting frame metadata retained")
	print("BANK_NETWORK_COMPONENTS_PASS bounds / out-of-order / parity / stale / expiry / conflicts")
	quit()
