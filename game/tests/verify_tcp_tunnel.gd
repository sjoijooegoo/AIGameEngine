extends SceneTree
## Real loopback TCP framing + UDP datagrams, independent of bank gameplay.
var server: Node
var client: Node
var echo:=PacketPeerUDP.new()
var source:=PacketPeerUDP.new()

func _initialize() -> void:
	Engine.max_fps=120;run.call_deferred()

func step() -> void:
	await process_frame
	for packet in echo.get_available_packet_count():
		var bytes:=echo.get_packet();echo.set_dest_address(echo.get_packet_ip(),echo.get_packet_port());echo.put_packet(bytes)

func run() -> void:
	var port:=26000+int(randi()%1000)
	while echo.bind(port,"127.0.0.1")!=OK:port+=1
	server=load("res://coop/tcp_tunnel.gd").new();root.add_child(server);assert(server.serve(port)==OK)
	client=load("res://coop/tcp_tunnel.gd").new();root.add_child(client)
	var local_port: int=client.connect_game("127.0.0.1",port);assert(local_port>0)
	assert(source.bind(0,"127.0.0.1")==OK);source.set_dest_address("127.0.0.1",local_port)
	var expected: Dictionary={};var received: Dictionary={}
	for frame in 300:
		if frame<60:
			var bytes:=PackedByteArray();bytes.resize([24,60,900,1392][frame%4]);bytes.fill(frame)
			expected[frame]=bytes;source.put_packet(bytes)
		await step()
		for packet in source.get_available_packet_count():
			var bytes:=source.get_packet();assert(expected.get(int(bytes[0]))==bytes)
			received[int(bytes[0])]=true
		if received.size()==60:break
	assert(received.size()==60,"TCP framing lost or truncated datagrams")
	# Malformed input cannot reach the fixed bank UDP destination.
	var malformed:=StreamPeerTCP.new();assert(malformed.connect_to_host("127.0.0.1",port)==OK)
	for frame in 120:
		await step();malformed.poll()
		if malformed.get_status()==StreamPeerTCP.STATUS_CONNECTED:break
	malformed.put_data(PackedByteArray([66,75]));await step()
	malformed.put_data(PackedByteArray([84,49,255,255]))
	for frame in 30:await step();malformed.poll()
	assert(server.links.size()==1,"Oversized frame was retained")
	assert(echo.get_available_packet_count()==0)
	malformed.disconnect_from_host();source.close();echo.close();client.close();server.close()
	print("BANK_TCP_TUNNEL_PASS 60 exact datagrams / split header / oversized rejection / bounded buffers")
	quit()
