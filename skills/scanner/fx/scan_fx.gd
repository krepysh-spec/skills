class_name ScanFx
extends RefCounted
## СПАЛАХ І ІСКРИ НАПРИКІНЦІ СКАНУ. Копія game.spawn_flash / game.spawn_sparks із
## core/world/directors/fx_director.gd гри: у грі їх дає `game`, а тут `game`
## немає, тож ті самі дві функції живуть статично й вішають ефект на переданий
## вузол. Меші й матеріали так само кешуються на клас.

static var _meshes := {}
static var _mats := {}


## Швидкий яскравий адитивний спалах: куля росте в 1.9 раза й тане за `dur`.
static func flash(host: Node, pos: Vector3, color: Color, sz: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("flash")
	mi.material_override = _mat("flash", color)
	host.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * sz
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * (sz * 1.9), dur)
	tw.tween_property(mi, "transparency", 1.0, dur)
	tw.finished.connect(mi.queue_free)


## Жменя світних скалок, що розлітаються від точки в площині польоту.
static func sparks(host: Node, pos: Vector3, color: Color, count := 6) -> void:
	var mesh := _mesh("spark")
	var mat := _mat("spark", color)
	for i in range(count):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		host.add_child(mi)
		mi.global_position = pos
		var ang := randf() * TAU
		var d := Vector3(cos(ang), 0.0, sin(ang))
		mi.look_at(pos + d, Vector3.UP)
		var dist := randf_range(0.9, 2.2)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", pos + d * dist, 0.28).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(0.3, 0.3, 0.3), 0.28)
		tw.tween_property(mi, "transparency", 1.0, 0.28)
		tw.finished.connect(mi.queue_free)


static func _mesh(kind: String) -> Mesh:
	var hit: Variant = _meshes.get(kind)
	if hit != null:
		return hit
	var mesh: Mesh
	if kind == "spark":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 0.45)
		mesh = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		mesh = sm
	_meshes[kind] = mesh
	return mesh


static func _mat(kind: String, color: Color) -> StandardMaterial3D:
	var key := "%s:%d" % [kind, color.to_rgba32()]
	var hit: Variant = _mats.get(key)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9) if kind == "flash" else color
	_mats[key] = mat
	return mat
