extends SceneTree
## Inspect the actual native VERIFY_CONNECT bytes, independent of our wrapper.
## This catches engine argument-forwarding regressions before deployment.
func _initialize() -> void:run.call_deferred()

func run() -> void:
	var server=load("res://coop/session.gd").new();server.visual=false;server.testing=true;root.add_child(server)
	var port:=24700+int(randi()%1000)
	while server.start_server(port,2)!=OK:port+=1
	assert(server.peer.host.get_max_channels()==8)
	var socket:=PacketPeerUDP.new();assert(socket.bind(0,"127.0.0.1")==OK)
	assert(socket.set_dest_address("127.0.0.1",port)==OK)
	var wire:=StreamPeerBuffer.new();wire.big_endian=true
	wire.put_u16(0x8fff);wire.put_u16(Time.get_ticks_msec()&65535)
	wire.put_u8(0x82);wire.put_u8(255);wire.put_u16(1)
	wire.put_u16(0);wire.put_u8(255);wire.put_u8(255)
	for value in [1400,65536,8,0,0,5000,2,2,731942,42]:wire.put_u32(value)
	assert(wire.data_array.size()==52);socket.put_packet(wire.data_array)
	var response:=PackedByteArray()
	for step in 120:
		await process_frame
		if socket.get_available_packet_count()>0:response=socket.get_packet();break
	assert(response.size()>=48 and response[4]&15==3,"No native VERIFY_CONNECT")
	var decoded:=StreamPeerBuffer.new();decoded.big_endian=true;decoded.data_array=response;decoded.seek(12)
	var mtu:=decoded.get_u32();var window:=decoded.get_u32();var channels:=decoded.get_u32();var incoming:=decoded.get_u32();var outgoing:=decoded.get_u32()
	assert(incoming==0 and outgoing==0,"Native server advertised an accidental bandwidth limit")
	assert(window==65536 and channels==8 and mtu<=1400)
	print("BANK_ENET_HANDSHAKE_PASS ",JSON.stringify({"mtu":mtu,"window":window,"channels":channels,"incoming_bandwidth":incoming,"outgoing_bandwidth":outgoing}))
	socket.close();server.disconnect_game("")
	var receiver:=PacketPeerUDP.new();assert(receiver.bind(0,"127.0.0.1")==OK)
	assert(server.join_game("127.0.0.1",receiver.get_local_port(),"Handshake")==OK)
	response=PackedByteArray()
	for step in 120:
		await process_frame
		if receiver.get_available_packet_count()>0:response=receiver.get_packet();break
	assert(response.size()>=52 and response[4]&15==2,"No native CONNECT")
	decoded.data_array=response;decoded.seek(12)
	mtu=decoded.get_u32();window=decoded.get_u32();channels=decoded.get_u32();incoming=decoded.get_u32();outgoing=decoded.get_u32()
	assert(incoming==0 and outgoing==0 and window==65536 and channels==8,"Client advertised accidental bandwidth/window limits")
	print("BANK_ENET_CLIENT_HANDSHAKE_PASS ",JSON.stringify({"mtu":mtu,"window":window,"channels":channels,"incoming_bandwidth":incoming,"outgoing_bandwidth":outgoing}))
	server.disconnect_game("");receiver.close();quit()
