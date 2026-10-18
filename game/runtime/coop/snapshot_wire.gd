extends RefCounted
## Visual replication precision only. Authority, hitboxes, health and inputs
## keep their original values. Dyadic steps avoid transmitting float noise and
## make Zstd effective: position error <= 0.49 mm/axis; clock error <= 0.49 ms.
static func field(index: int,value):
	match index:
		1,3:return (value as Vector3).snapped(Vector3.ONE/1024.0)
		2:return snappedf(value,1.0/4096.0)
		6,7,12,13,15,16,20:return snappedf(value,1.0/1024.0)
		19:return (value as Vector3).snapped(Vector3.ONE/4096.0)
		9:
			var points: Array=[]
			for point: Vector3 in value:points.append(point.snapped(Vector3.ONE/1024.0))
			return points
	return value

static func encode(wire: Dictionary) -> Dictionary:
	var result:=wire.duplicate()
	if wire.base==-1:
		result.state=wire.state.duplicate();result.state.enemies=[]
		for source: Array in wire.state.enemies:
			var row:=source.duplicate()
			for index in [1,2,3,6,7,9,12,13,15,16,19,20]:row[index]=field(index,row[index])
			result.state.enemies.append(row)
	else:
		result.enemies=[]
		for source: Array in wire.enemies:
			var row:=source.duplicate();var cursor:=2
			for index in range(1,22):
				if int(row[1])&(1<<index):row[cursor]=field(index,row[cursor]);cursor+=1
			result.enemies.append(row)
	return result
