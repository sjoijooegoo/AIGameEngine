extends SceneTree
const Buffer=preload("res://coop/snapshot_buffer.gd")

func _initialize() -> void:
	var codec=load("res://coop/rpc_codec.gd")
	var inputs: Array=[]
	for i in 12:inputs.append([12500+i,Vector2(1,0),1.234567890123,-.45,true,13500+i])
	var input_wire: PackedByteArray=codec.encode(inputs)
	assert(codec.decode(input_wire)==inputs,"Input codec must preserve every value exactly")
	assert(input_wire.size()<var_to_bytes(inputs).size()/3,"Repeated input history must compress substantially")
	assert(codec.decode(PackedByteArray()).is_empty())
	var invalid:=PackedByteArray();invalid.resize(8);invalid.encode_u32(0,codec.MAX_RAW+1)
	assert(codec.decode(invalid).is_empty(),"Oversized decompression must be rejected before allocation")
	invalid.resize(codec.MAX_WIRE+1);assert(codec.decode(invalid).is_empty())
	print("BANK_RPC_CODEC raw=",var_to_bytes(inputs).size()," wire=",input_wire.size())
	var rng:=RandomNumberGenerator.new();rng.seed=7319
	var blob:=PackedByteArray();blob.resize(4400)
	for i in blob.size():blob[i]=rng.randi_range(0,255)
	var packet:={"round":7,"blob":blob,"team":{1:{"hp":73}}}
	var raw:=var_to_bytes(packet);var wire:=raw.compress(FileAccess.COMPRESSION_ZSTD);var shards:=Buffer.shards(wire);var count:=ceili(float(wire.size())/Buffer.SHARD)
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
	for lost in range(count-1):
		var buffer:=Buffer.new();var decoded: Dictionary={}
		for i in shards.size():
			if i==lost or i==lost+1:continue
			var value: Dictionary=buffer.receive(20,i,count,raw.size(),wire.size(),shards[i],40,-1)
			if not value.is_empty():decoded=value
		assert(decoded==packet,"two adjacent lost data shards must recover")
	var bounded:=Buffer.new()
	for t in 50:bounded.receive(t,0,count,raw.size(),wire.size(),shards[0],t,-1)
	assert(bounded.frames.size()<=8 and bounded.allocated<=262144)
	bounded.prune(2000,-1);assert(bounded.frames.is_empty() and bounded.allocated==0)
	assert(bounded.receive(100,128,129,1048577,115201,shards[0],2001,-1).is_empty())
	assert(bounded.allocated==0 and bounded.rejected==1)
	bounded.receive(101,0,count,raw.size(),wire.size(),shards[0],2100,-1)
	bounded.receive(101,1,count+1,raw.size(),wire.size()+900,shards[1],2101,-1)
	assert(not bounded.frames.has(101),"conflicting frame metadata retained")
	var pacer=load("res://coop/snapshot_pacer.gd").new()
	var bytes_sent:=0
	for ms in range(0,1001,10):
		if pacer.take(1,ms,8000,50):bytes_sent+=8000
	assert(bytes_sent<=int(pacer.BURST+pacer.BYTES_PER_SECOND),"Frame pacing exceeded byte budget")
	assert(pacer.skipped>0)
	assert(pacer.take(2,0,1000,100))
	assert(not pacer.take(2,100,1000,600))
	assert(pacer.take(2,300,1000,600))
	assert(pacer.take(4,0,1000,600) and pacer.take(4,100,1000,600),"Stable long-distance RTT is not congestion")
	assert(not pacer.take(3,0,pacer.MAX_FRAME+1,50))
	print("BANK_NETWORK_COMPONENTS_PASS bounds / out-of-order / parity / stale / expiry / conflicts")
	quit()
