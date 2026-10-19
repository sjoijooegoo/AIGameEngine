extends Node
## Separate bounded UDP status channel; discovery never occupies a player slot.
const MAGIC="BANK_STATUS_1"
const BUILD="bank-combat-v7"
var socket: PacketPeerUDP
var server: Node
var game_port := 24567
var server_name := "银行合作服务器"
var rows: Dictionary={}
var pending: Dictionary={}
var active := false
var next_probe := 0
var budget := 40.0
signal changed

static func query_port(port: int) -> int:return port+1 if port<65535 else 65534

func serve(owner_session: Node,port: int) -> Error:
	server=owner_session;game_port=port;socket=PacketPeerUDP.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server-name="):server_name=arg.trim_prefix("--server-name=").left(40)
	var error:=socket.bind(query_port(port))
	if error!=OK:socket=null;return error
	print("BANK_DISCOVERY UDP ",query_port(port));return OK

func browse() -> void:
	socket=PacketPeerUDP.new()
	if socket.bind(0)!=OK:socket=null;return
	socket.set_broadcast_enabled(true)
	add_target("localhost",24567,"本机 WSL / localhost")
	add_target("207.57.124.243",24567,"公网银行合作服务器")

func add_target(host: String,port: int,title: String="") -> void:
	host=host.strip_edges()
	if host=="127.0.0.1":host="localhost"
	if host.is_empty() or port<1024 or port>65535:return
	var id:=host+":"+str(port)
	if rows.has(id):return
	if rows.size()>=8:return
	rows[id]={"id":id,"address":host,"port":port,"name":title if not title.is_empty() else host,"online":false,"players":0,"occupied":0,"reserved":0,"capacity":4,"ping":0,"seen":0,"compatible":true}
	changed.emit()

func refresh() -> void:
	if socket==null or server!=null:return
	var now:=Time.get_ticks_msec();next_probe=now+2000
	for id in rows:probe(rows[id].address,int(rows[id].port),id,now)
	probe("255.255.255.255",24567,"lan",now)
	for nonce in pending.keys():
		if now-int(pending[nonce].sent)>5000:pending.erase(nonce)
	for id in rows:
		if now-int(rows[id].seen)>5000:rows[id].online=false
	changed.emit()

func probe(host: String,port: int,id: String,now: int) -> void:
	var nonce:=str(now)+"-"+str(randi())
	if socket.set_dest_address("127.0.0.1" if host.to_lower()=="localhost" else host,query_port(port))!=OK:return
	pending[nonce]={"id":id,"sent":now,"port":port}
	# Padding keeps the status response smaller than its request.
	var bytes:=JSON.stringify({"magic":MAGIC,"query":true,"nonce":nonce,"padding":" ".repeat(192)}).to_utf8_buffer()
	socket.put_packet(bytes)

func _process(dt: float) -> void:
	if socket==null:return
	budget=minf(40.0,budget+dt*20)
	if server==null and active and Time.get_ticks_msec()>=next_probe:refresh()
	for i in mini(socket.get_available_packet_count(),32):
		var bytes:=socket.get_packet();var address:=socket.get_packet_ip();var port:=socket.get_packet_port()
		if bytes.size()<10 or bytes.size()>512:continue
		var value=JSON.parse_string(bytes.get_string_from_utf8())
		if not value is Dictionary or value.get("magic")!=MAGIC or not value.get("nonce") is String:continue
		if server!=null:
			if value.get("query")!=true or bytes.size()<192 or value.nonce.length()>40 or budget<1:continue
			budget-=1
			var reply:={"magic":MAGIC,"nonce":value.nonce,"build":BUILD,"name":server_name,"port":game_port,"players":server.players.size(),"occupied":server.occupied_slots(),"reserved":server.recovery.reservations.size(),"capacity":server.max_players,"transport":"tcp" if server.prefer_tcp_advertise else "udp"}
			socket.set_dest_address(address,port);socket.put_packet(JSON.stringify(reply).to_utf8_buffer())
		else:receive(value,address,port)

func receive(value: Dictionary,address: String,port: int) -> void:
	if not pending.has(value.nonce):return
	var sent: Dictionary=pending[value.nonce]
	if port!=query_port(int(sent.port)) or not value.get("name") is String:return
	if not value.get("players") is float or not value.get("capacity") is float or not value.get("port") is float:return
	var count:=int(value.players);var capacity:=int(value.capacity)
	if value.has("occupied") and not value.occupied is float:return
	if value.has("reserved") and not value.reserved is float:return
	var occupied:=int(value.get("occupied",count));var reserved:=int(value.get("reserved",0))
	if occupied<count or occupied>capacity or reserved<0 or reserved>occupied-count:return
	if capacity<2 or capacity>4 or count<0 or count>capacity or int(value.get("port",0))!=int(sent.port):return
	var id: String=sent.id
	if id=="lan":
		id=address+":"+str(sent.port)
		if address=="127.0.0.1" and rows.has("localhost:"+str(sent.port)):return
		add_target(address,int(sent.port))
	if not rows.has(id):return
	var row: Dictionary=rows[id]
	row.online=true;row.seen=Time.get_ticks_msec();row.ping=maxi(0,int(row.seen)-int(sent.sent))
	row.players=count;row.capacity=capacity;row.name=value.name.left(40);row.compatible=value.get("build")==BUILD
	row.occupied=occupied;row.reserved=reserved
	row.transport="tcp" if value.get("transport")=="tcp" else "udp"
	if sent.id!="lan":pending.erase(value.nonce)
	changed.emit()

func _exit_tree() -> void:
	if socket:socket.close()
