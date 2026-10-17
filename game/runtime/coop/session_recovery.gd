extends RefCounted
## In-memory recovery only. Opaque bearer token; never saved or logged.
## Reserved players cannot move/fire and retain HP/ammo, for at most 40 seconds.
const GRACE_MS := 40000
var game: Node
var tokens: Dictionary={}
var reservations: Dictionary={}
var voluntary: Dictionary={}
var token := ""
var endpoint: Dictionary={}
var retrying := false
var attempts := 0
var deadline := 0
var next_attempt := 0
var was_playing := true
var resumed := 0

func count() -> int:
	var unique: Dictionary={}
	for value in tokens.values():unique[value]=true
	for value in reservations:unique[value]=true
	return unique.size()

func slots() -> Array:
	var result: Array=[]
	for row in reservations.values():result.append(row.context.body.slot)
	return result

func active_id(value: String) -> int:
	for id in tokens:
		if tokens[id]==value and game.players.has(id):return id
	return 0

func reserve(id: int,request: Dictionary) -> String:
	expire()
	var value=request.get("resume","")
	if not value is String or value.length()>48:return "恢复凭证无效"
	if not value.is_empty():
		if not reservations.has(value) and active_id(value)==0:return "恢复会话已过期，请重新加入"
		for pending_id in game.pending:
			if tokens.get(pending_id,"")==value:return "恢复正在进行"
	else:
		if count()>=game.max_players:return "房间已满（包含临时保留的位置）"
		value=Crypto.new().generate_random_bytes(24).hex_encode()
	tokens[id]=value;game.pending[id]=request.name.strip_edges()
	return ""

func keep(id: int,context) -> bool:
	var value: String=tokens.get(id,"")
	tokens.erase(id)
	if voluntary.has(id):voluntary.erase(id);return false
	if value.is_empty():return false
	context.weapon.clear_input();context.actions.clear();context.body.commands.clear()
	context.body.axes=Vector2.ZERO;context.body.velocity=Vector3.ZERO
	context.body.collision_layer=0;context.body.collision_mask=0;context.body.hide()
	game.players.erase(id)
	reservations[value]={"context":context,"expires":Time.get_ticks_msec()+GRACE_MS,"round":game.round_id}
	return true

func take(id: int):
	var value: String=tokens.get(id,"")
	if not reservations.has(value):return null
	var row: Dictionary=reservations[value];reservations.erase(value)
	var context=row.context;var body=context.body
	body.peer_id=id;body.name="Player_%d" % id;body.last_sequence=-1;body.last_input_tick=game.tick
	body.commands.clear();body.axes=Vector2.ZERO;body.collision_layer=2;body.collision_mask=9;body.show()
	context.last_action=0;context.actions.clear();context.action_budget=40;context.weapon.clear_input()
	# If the remaining team restarted, a reservation cannot restore the old round.
	if int(row.round)!=game.round_id:
		context.hp=100;context.dead=false;context.feedback.reset();context.weapon.reset("pistol")
		body.position=Vector3(23-float(body.slot)*.7,.05,8.2)
	return context

func expire() -> void:
	for value in reservations.keys():
		if Time.get_ticks_msec()>int(reservations[value].expires):
			var context=reservations[value].context
			context.body.queue_free();context.weapon.queue_free();reservations.erase(value)

func clear_server() -> void:
	for row in reservations.values():row.context.body.queue_free();row.context.weapon.queue_free()
	reservations.clear();tokens.clear();voluntary.clear()

func lost(message: String) -> bool:
	if token.is_empty() or endpoint.is_empty():return false
	if not retrying:
		was_playing=game.input_enabled;attempts=0;deadline=Time.get_ticks_msec()+45000
	retrying=true
	game.disconnect_game("")
	next_attempt=Time.get_ticks_msec()+mini(8000,1000*(1<<mini(attempts,3)))
	game.set_status(message+" · 正在自动重连，可取消")
	if game.panel:game.panel.refresh()
	return true

func advance() -> void:
	if game.is_host:expire();return
	if not retrying:return
	var now:=Time.get_ticks_msec()
	if now>deadline:
		cancel();game.disconnect_game("重连超时，请重新加入服务器");return
	if game.peer==null and now>=next_attempt:
		attempts+=1;game.join_game(endpoint.address,endpoint.port,endpoint.label)
		game.set_status("正在自动重连（第 %d 次）…" % attempts)

func connected() -> void:
	if retrying:resumed+=1
	retrying=false;attempts=0

func cancel() -> void:
	retrying=false;token="";endpoint.clear()
