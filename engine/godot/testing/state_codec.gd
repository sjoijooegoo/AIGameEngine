extends RefCounted
## Validate before mutating the world. JSON numbers may arrive as int or float.

static func validate(value: Variant, shape: Variant, path: String = "state") -> String:
	if shape is Dictionary:
		if not value is Dictionary:
			return path + " must be an object"
		for key in shape:
			if not value.has(key):
				return path + "." + str(key) + " is missing"
			var error := validate(value[key], shape[key], path + "." + str(key))
			if not error.is_empty():
				return error
	elif shape is Array:
		if not value is Array or (not shape.is_empty() and value.size() != shape.size()):
			return path + " has invalid array dimensions"
		for i in range(shape.size()):
			var error := validate(value[i], shape[i], path + "[%d]" % i)
			if not error.is_empty():
				return error
	elif typeof(shape) in [TYPE_FLOAT, TYPE_INT]:
		if not typeof(value) in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
			return path + " must be a finite number"
	elif typeof(value) != typeof(shape):
		return path + " has wrong type"
	return ""

static func vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
