class_name MCPScreenshotAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("screenshot.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"screenshot.capture", "screenshot.viewport":
			var img := _capture()
			if img == null or img.is_empty():
				return B.err("capture failed")
			var png := img.save_png_to_buffer()
			return {
				"format": "png",
				"data": Marshalls.raw_to_base64(png),
				"width": img.get_width(),
				"height": img.get_height(),
			}
	return B.err("unsupported: %s" % method)


static func _capture() -> Image:
	# Capture the editor window, not an inactive 2D subviewport (often 2x2).
	# The running game is a separate process and needs its own capture harness.
	var viewport := EditorInterface.get_base_control().get_viewport()
	var texture := viewport.get_texture()
	if texture:
		return texture.get_image()
	return null
