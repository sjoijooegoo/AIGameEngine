extends SceneTree
const Encoder=preload("res://coop/snapshot_encoder.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var encoder:=Encoder.new()
	for parity in [false,true]:
		var row: Array=["a",Vector3(12.3456,.12345,5.6789),.1234,Vector3.ZERO,73.123,"dead",12.345,.123,true,[Vector3(12.123,.456,7.89)],false,"idle",.45,.5,3,.12,.4,"chest","front",Vector3.BACK,.8,false]
		var wires: Dictionary={-2:{"base":-1,"round":1,"state":{"enemies":[row],"team":{},"doors":{},"round":1},"keyframe":true}}
		var expected:=Encoder.encode(wires,parity)
		assert(encoder.submit(wires,parity));assert(not encoder.submit(wires,parity))
		wires[-2].state.enemies[0][1]=Vector3.ZERO
		var result: Dictionary={}
		for frame in 120:
			await process_frame;result=encoder.take()
			if not result.is_empty():break
		assert(result==expected,"Worker results diverged or shared caller-owned state")
		assert(encoder.task==-1 and encoder.take().is_empty())
		assert(encoder.submit(wires,parity));encoder.reset()
		assert(encoder.task==-1 and encoder.take().is_empty(),"Reset retained stale world work")
	print("BANK_SNAPSHOT_ENCODER_PASS exact bytes / parity / ownership / one job / reset join")
	quit()
