@tool
extends MeshInstance3D
# ONE JET NOZZLE'S GAME DRIVER, worn by the jet cones authored inside each
# ship scene (assets/vfx/jet pack: jet.gdshader on an open-ended cone). The
# scene's own material IS the full-throttle look — colours, noise, intensity,
# all tunable per ship right in the editor — and this script only throttles
# it: set_power(0) pulls the flame into the nozzle and kills the glow,
# set_power(1) restores the authored burn, past 1 overdrives it for boost.
#
# @tool so the editor shows the burn at `preview_power` while the cone is
# being sized and seated against its hull.

## The throttle the editor preview idles at (runtime ignores this).
@export_range(0.0, 1.6, 0.05) var preview_power := 1.0:
	set(v):
		preview_power = v
		if Engine.is_editor_hint() and is_inside_tree():
			set_power(v)

const OFF_NOISE := 0.1

var _mat: ShaderMaterial
# the authored full-throttle pose, captured once
var _on_intensity := 3.0
var _on_uv_middle := 0.0
var _on_noise := 0.45
## Where the flame's midpoint retreats to at zero throttle — inside the nozzle,
## so shutdown reads as the jet being swallowed, not switched off.
##
## NOT A CONSTANT, because the distance the flame has to travel to be swallowed
## is a property of the cone. jet.gdshader lights the band where
## `(UV.y - uv_middle) * length_scale < 1`, so the tip sits at `1 / length_scale`
## past the midpoint and the cone runs empty the moment uv_middle passes
## `-1 / length_scale` — about -0.29 on the 3.5-scale cones every ship authors.
##
## This used to be a flat -1.5, five times further back than that, and the whole
## visible retraction was over by the time the throttle had fallen a fifth of the
## way. The remaining four fifths of the ease-out pulled on a flame that was
## already gone, which is why cutting the throttle read as the jet being switched
## off rather than dying down. Ending the travel exactly at the swallow point
## spends the entire ease-out on frames you can see.
var _off_uv_middle := -0.29


func _ready() -> void:
	if material_override is ShaderMaterial:
		var src := material_override as ShaderMaterial
		# THE AUTHORED POSE IS READ BEFORE ANYTHING IS TOUCHED — every nozzle on
		# a hull shares one SubResource in the .tscn, so a throttle written to it
		# is a throttle every other nozzle would then capture as its "full burn".
		_on_intensity = _param(src, "intensity", _on_intensity)
		_on_uv_middle = _param(src, "uv_middle", _on_uv_middle)
		_on_noise = _param(src, "noise_strength", _on_noise)
		# 0.5 is the shader's own floor for length_scale; guard the divide
		# against a cone that never set one.
		_off_uv_middle = -1.0 / maxf(_param(src, "length_scale", 4.0), 0.5)
		# IN GAME, a private copy: the shared SubResource must not be throttled,
		# or one ship's boost brightens every hull of that model on the screen.
		# IN THE EDITOR the shared one is driven directly and NOT replaced —
		# assigning a duplicate here would dirty the scene the moment it opens
		# and bake one material per nozzle into the next save.
		_mat = src if Engine.is_editor_hint() else src.duplicate()
		if not Engine.is_editor_hint():
			material_override = _mat
	set_power(preview_power if Engine.is_editor_hint() else 0.0)


# A shader parameter as authored, or the shader's own default when the material
# never overrode it — get_shader_parameter() returns null for those, and float(null)
# is a hard cast error, not a 0.
func _param(mat: ShaderMaterial, param: StringName, fallback: float) -> float:
	var v: Variant = mat.get_shader_parameter(param)
	return float(v) if v != null else fallback


func set_power(p: float) -> void:
	if _mat == null:
		return
	var t := clampf(p, 0.0, 1.0)
	var boost := 1.0 + maxf(p - 1.0, 0.0)        # past 1 runs the burn hotter
	_mat.set_shader_parameter("intensity", _on_intensity * t * boost)
	_mat.set_shader_parameter("uv_middle", lerpf(_off_uv_middle, _on_uv_middle, t))
	_mat.set_shader_parameter("noise_strength", lerpf(OFF_NOISE, _on_noise, t))
	visible = p > 0.02
