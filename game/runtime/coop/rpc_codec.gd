extends RefCounted
## Lossless, bounded compression for frequently repeated input/player arrays.
## Keep the existing validation after decoding; never enable object decoding.
const MAX_RAW := 16384
const MAX_WIRE := 8192

static func encode(rows: Array) -> PackedByteArray:
	var raw:=var_to_bytes(rows)
	if raw.size()>MAX_RAW:return PackedByteArray()
	var compressed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.size()+4>MAX_WIRE:return PackedByteArray()
	var wire:=PackedByteArray();wire.resize(4);wire.encode_u32(0,raw.size());wire.append_array(compressed)
	return wire

static func decode(wire: PackedByteArray) -> Array:
	if wire.size()<5 or wire.size()>MAX_WIRE:return []
	var size:=wire.decode_u32(0)
	if size<8 or size>MAX_RAW:return []
	var raw:=wire.slice(4).decompress(size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=size:return []
	var value=bytes_to_var(raw)
	return value if value is Array else []
