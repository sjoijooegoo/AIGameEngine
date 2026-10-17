extends RefCounted
## Continuous lamp-space profiles, evaluated by the real spotlight shader.
const HALF_ANGLE := 42.0
const ENERGY := 4.5
const RANGE := 14.0
static func profile(radius: float) -> float:
	var r:=maxf(radius,0.0)
	var edge:=1.0-smoothstep(.78,1.0,r)
	return (.78*exp(-r*r*5.5)+.22*exp(-r*r*1.5))*edge

static func angular_weight(offset: Vector2) -> float:
	return profile(offset.length()/tan(deg_to_rad(HALF_ANGLE)))

static func spill_profile(radius: float) -> float:
	var r:=maxf(radius,0.0)
	# Reserve contrast for the original core. The skirt reaches its shoulder
	# inside the core's outer edge, avoiding a second ring outside that edge.
	return (.35+.65*smoothstep(.05,.32,r))*exp(-r*r*.7)*(1.0-smoothstep(.65,1.0,r))

static func peripheral_profile(radius: float) -> float:
	var r:=maxf(radius,0.0)
	# A low central contribution preserves the existing core's contrast.
	# The final fade lies beyond the visible corners (normalized radius .8).
	return (.35+.65*smoothstep(.05,.5,r))*(1.0-smoothstep(.86,1.0,r))

static func projector(is_spill := false, is_peripheral := false) -> ImageTexture:
	# Linear floating-point values avoid an unintended sRGB contrast curve in
	# a data texture. Generated once; no viewport or per-frame texture updates.
	var size:=256
	var picture:=Image.create(size,size,false,Image.FORMAT_RGBF)
	for y in size:
		for x in size:
			var uv:=(Vector2(x,y)+Vector2(.5,.5))/float(size)*2.0-Vector2.ONE
			var value:=spill_profile(uv.length()) if is_spill else profile(uv.length())
			if is_peripheral:value=peripheral_profile(uv.length())
			picture.set_pixel(x,y,Color(value,value,value))
	picture.generate_mipmaps()
	return ImageTexture.create_from_image(picture)
