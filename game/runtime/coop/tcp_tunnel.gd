extends Node
## Optional framed TCP carrier for ENet datagrams. The server always forwards
## only to its own bank UDP port; ENet authentication/capacity remain unchanged.
const MAGIC := [66,75,84,49] # BKT1
const MAX_DATAGRAM := 1400
const MAX_BUFFER := 262144
const MAX_LINKS := 12
class Link:
	var tcp: StreamPeerTCP
	var udp: PacketPeerUDP
	var incoming:=PackedByteArray()
	var outgoing:=PackedByteArray()
	var offset := 0
	var local_port := 0
	var authenticated := false
	var created := 0
	var activity := 0
	var packets := 0
	var closed := false
var listener: TCPServer
var links: Array[Link]=[]
var target_port := 0
var client_mode := false
var stopped := false
signal failed

func serve(port: int) -> Error:
	listener=TCPServer.new();target_port=port
	return listener.listen(port)

func connect_game(address: String,port: int) -> int:
	client_mode=true
	var link:=Link.new();link.udp=PacketPeerUDP.new();link.tcp=StreamPeerTCP.new()
	if link.udp.bind(0,"127.0.0.1",MAX_BUFFER*4)!=OK:return -1
	if link.tcp.connect_to_host(address,port)!=OK:link.udp.close();return -1
	link.created=Time.get_ticks_msec();link.activity=link.created
	link.authenticated=true;link.outgoing=PackedByteArray(MAGIC);links.append(link)
	return link.udp.get_local_port()

func close_link(link: Link) -> void:
	link.closed=true
	link.tcp.disconnect_from_host()
	if link.udp:link.udp.close()

func close() -> void:
	stopped=true
	if listener:listener.stop()
	for link in links:close_link(link)
	links.clear()

func owns_udp_port(port: int) -> bool:
	for link in links:
		if not link.closed and link.udp and link.udp.get_local_port()==port:return true
	return false

func append_packet(link: Link,bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes.size()>MAX_DATAGRAM or link.outgoing.size()-link.offset+bytes.size()+2>MAX_BUFFER:
		close_link(link);return
	link.outgoing.append(bytes.size()>>8);link.outgoing.append(bytes.size()&255)
	link.outgoing.append_array(bytes)

func poll_link(link: Link,now: int) -> void:
	link.tcp.poll()
	var state:=link.tcp.get_status()
	if state==StreamPeerTCP.STATUS_CONNECTING:
		if now-link.created>10000:close_link(link)
		return
	if state!=StreamPeerTCP.STATUS_CONNECTED:close_link(link);return
	link.tcp.set_no_delay(true)
	var available:=link.tcp.get_available_bytes()
	if available>0:
		if available+link.incoming.size()>MAX_BUFFER:close_link(link);return
		var received:=link.tcp.get_partial_data(mini(available,65536))
		if received[0]!=OK:close_link(link);return
		link.incoming.append_array(received[1]);link.activity=now
	if not link.authenticated:
		if link.incoming.size()<4:
			if now-link.created>5000:close_link(link)
			return
		if link.incoming.slice(0,4)!=PackedByteArray(MAGIC):close_link(link);return
		link.incoming=link.incoming.slice(4);link.authenticated=true
		link.udp=PacketPeerUDP.new()
		if link.udp.bind(0,"127.0.0.1",MAX_BUFFER*4)!=OK or link.udp.connect_to_host("127.0.0.1",target_port)!=OK:close_link(link);return
	var cursor:=0
	for packet in 128:
		if link.incoming.size()-cursor<2:break
		var size: int=(int(link.incoming[cursor])<<8)|int(link.incoming[cursor+1])
		if size<1 or size>MAX_DATAGRAM:close_link(link);return
		if link.incoming.size()-cursor<size+2:break
		var bytes:=link.incoming.slice(cursor+2,cursor+2+size);cursor+=size+2
		if client_mode:
			if link.local_port>0:
				link.udp.set_dest_address("127.0.0.1",link.local_port);link.udp.put_packet(bytes)
		else:link.udp.put_packet(bytes)
		link.packets+=1
	if cursor>0:link.incoming=link.incoming.slice(cursor)
	for packet in mini(link.udp.get_available_packet_count(),128):
		var bytes:=link.udp.get_packet()
		if client_mode:
			if link.udp.get_packet_ip()!="127.0.0.1":continue
			var source:=link.udp.get_packet_port()
			if link.local_port!=0 and source!=link.local_port:continue
			link.local_port=source
		append_packet(link,bytes)
		if link.closed:return
		link.activity=now
	if link.outgoing.size()>link.offset:
		var sent:=link.tcp.put_partial_data(link.outgoing.slice(link.offset,mini(link.outgoing.size(),link.offset+65536)))
		if sent[0]!=OK:close_link(link);return
		link.offset+=int(sent[1])
		if link.offset==link.outgoing.size():link.outgoing.clear();link.offset=0
		elif link.offset>65536:link.outgoing=link.outgoing.slice(link.offset);link.offset=0
	if now-link.activity>15000:close_link(link)

func _process(_dt: float) -> void:
	pump()

func pump() -> void:
	if stopped:return
	var now:=Time.get_ticks_msec()
	if listener:
		for pending in 8:
			if not listener.is_connection_available():break
			var tcp:=listener.take_connection()
			if links.size()>=MAX_LINKS:tcp.disconnect_from_host();continue
			var link:=Link.new();link.tcp=tcp;link.created=now;link.activity=now;links.append(link)
	for link in links:
		poll_link(link,now)
	for index in range(links.size()-1,-1,-1):
		if links[index].closed:links.remove_at(index)
	if client_mode and links.is_empty():stopped=true;failed.emit()

func _exit_tree() -> void:close()
