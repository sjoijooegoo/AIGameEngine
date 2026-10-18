extends RefCounted
## Congestion control skips complete replaceable worlds, never individual RPC
## shards. No obsolete transmission queue is retained.
const BYTES_PER_SECOND := 16384.0
const BURST := 8192.0
const MAX_FRAME := 196608
var peers: Dictionary={}
var skipped := 0
var sent := 0

func take(id: int,now: int,cost: int,rtt: float) -> bool:
	if cost<1 or cost>MAX_FRAME:return false
	var capacity:=maxf(BURST,cost)
	var row: Dictionary=peers.get(id,{"time":now,"credit":capacity,"sent":-1000000,"base_rtt":rtt})
	row.base_rtt=minf(float(row.base_rtt),rtt)
	row.credit=minf(capacity,float(row.credit)+maxi(0,now-int(row.time))*.001*BYTES_PER_SECOND);row.time=now
	peers[id]=row
	# A distant but uncongested 300–500 ms path still receives full-rate state.
	# Back off only when RTT grows above this connection's observed baseline.
	var queued_rtt:=rtt-float(row.base_rtt)
	var spacing:=500 if queued_rtt>750 else 300 if queued_rtt>300 else 200 if queued_rtt>150 else 0
	if now-int(row.sent)<spacing or float(row.credit)<cost:skipped+=1;return false
	row.credit-=cost;row.sent=now;sent+=1;return true

func reset() -> void:peers.clear();skipped=0;sent=0
