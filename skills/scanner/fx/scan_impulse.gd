class_name ScanImpulse
extends RefCounted
## ІМПУЛЬС НАПРИКІНЦІ СКАНУ: хвиля світла від центру предмета крізь саму модель
## (scan_impulse.gdshader) і іскри, що злітають із поверхні уламків у ту мить,
## коли до них доходить фронт. Стоїть замість кулі-спалаху ScanFx.flash.
##
## КОРИСТУВАННЯ:
##
##     _impulse = ScanImpulse.new()
##     _impulse.play(host, model_root, center, radius)
##     _impulse.running()      # поки хвиля йде, накладки моделі зайняті
##
## Накладка ставиться в `material_overlay`, як у ScanPass, і так само
## повертається наприкінці. Тому новий ScanPass на тому самому предметі не
## можна вдягати, поки імпульс running(): він записав би накладку імпульсу як
## «рідну» і повернув би її назавжди.

const SHADER := "res://skills/scanner/fx/scan_impulse.gdshader"

## Скільки фронт іде від центру до краю предмета і скільки після цього все гасне.
const WAVE_S := 0.65
const FADE_S := 0.35
## Наскільки далі за радіус предмета заходить фронт, щоб пройти його весь.
const REACH := 1.25

## Іскри: скільки, як далеко й як довго летять.
const SPARKS := 44
const SPARK_DIST := Vector2(2.5, 7.0)
const SPARK_LIFE := Vector2(0.45, 0.9)

var tint := Color(0.35, 0.8, 1.0)
var edge := Color(0.8, 0.97, 1.0)

var _mat: ShaderMaterial
var _worn: Array = []
var _running := false


func running() -> bool:
	return _running


## Запустити імпульс по моделі `root` з центру `center` (світ), радіус предмета
## `radius`. Ефекти й твіни висять на `host`, щоб жити незалежно від предмета.
func play(host: Node, root: Node3D, center: Vector3, radius: float) -> void:
	if host == null or root == null:
		return
	_restore()
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("wave_r", 0.0)
	_mat.set_shader_parameter("wave_w", maxf(radius * 0.12, 0.4))
	_mat.set_shader_parameter("strength", 1.0)
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("edge_color", edge)
	var meshes := _mesh_nodes(root)
	for mi in meshes:
		_worn.append([mi, mi.material_overlay])
		mi.material_overlay = _mat
	_running = true

	var reach := radius * REACH
	var mat := _mat
	var tw := host.create_tween()
	tw.tween_method(func(r: float) -> void: mat.set_shader_parameter("wave_r", r),
		0.0, reach, WAVE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(s: float) -> void: mat.set_shader_parameter("strength", s),
		1.0, 0.0, FADE_S).set_delay(WAVE_S - FADE_S * 0.5)
	tw.tween_callback(_restore)

	_surface_sparks(host, meshes, center, reach)


## Іскри з випадкових вершин моделі. Кожна чекає, поки фронт хвилі дійде до її
## точки (та сама відстань від центру, той самий закон руху), і летить назовні.
func _surface_sparks(host: Node, meshes: Array[MeshInstance3D], center: Vector3, reach: float) -> void:
	if meshes.is_empty():
		return
	var cache := {}
	for i in SPARKS:
		var mi: MeshInstance3D = meshes[randi() % meshes.size()]
		var verts: PackedVector3Array = cache.get(mi, PackedVector3Array())
		if verts.is_empty():
			if mi.mesh.get_surface_count() == 0:
				continue
			verts = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			cache[mi] = verts
		if verts.is_empty():
			continue
		var p: Vector3 = mi.global_transform * verts[randi() % verts.size()]
		var out := p - center
		var dir := (out.normalized() if out.length_squared() > 0.0001 else Vector3.UP)
		dir = (dir + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.6), randf_range(-0.5, 0.5))).normalized()
		# коли фронт дійде сюди: обернений EASE_OUT синуса
		var k := clampf(out.length() / reach, 0.0, 1.0)
		var delay := asin(k) / (PI * 0.5) * WAVE_S
		ScanFx.spark_streak(host, p, dir, randf_range(SPARK_DIST.x, SPARK_DIST.y),
			randf_range(SPARK_LIFE.x, SPARK_LIFE.y), delay, edge)


func _restore() -> void:
	for w in _worn:
		if is_instance_valid(w[0]):
			w[0].material_overlay = w[1]
	_worn.clear()
	_mat = null
	_running = false


static func _mesh_nodes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_mesh_nodes(c))
	return out
