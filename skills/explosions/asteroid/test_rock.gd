class_name TestRock
extends Node3D
## БРИЛА СТЕНДА. Та сама модель і та сама мірка, що в грі (asteroid.gd):
## середній розмір моделі дорівнює діаметру тьєра, тож вибух, розміряний від
## `radius`, виходить рівно таким, як у секторі.
##
## Розкол («розколюється чи розсипається») у грі вирішує сервер: звичайна брила
## тьєра вище першого ділиться на дві меншого тьєра. Тут те саме правило, щоб
## стенд показував обидва вибухи — з тріском каменю і чистий.

const GLB_PATH := "res://skills/explosions/asteroid/mesh/base.glb"

## Ледь помітне дихання в невагомості, як `_animate_hover` у грі.
const HOVER_RISE := 0.06
const HOVER_TILT := 0.05
## Відліт уламка від точки розколу: частка радіуса і час.
const CALVE_REACH := 0.9
const CALVE_TIME := 0.8

@export_range(1, 3) var tier := 3:
	set(v):
		tier = v
		radius = radius_for(v)
var radius := radius_for(3)

static var _meshes: Array = []

var _mesh: MeshInstance3D
var _hover_t := randf() * 10.0
var _drift := Vector3.ZERO
var _drift_left := 0.0


static func radius_for(t: int) -> float:
	match t:
		3: return 2.2
		2: return 1.4
		_: return 0.8


## Чи лишить вона по собі два уламки (у грі це правило сервера).
func splits() -> bool:
	return tier > 1


func _ready() -> void:
	if _meshes.is_empty():
		var inst := (load(GLB_PATH) as PackedScene).instantiate()
		_collect(inst)
		inst.free()
	if _meshes.is_empty():
		return
	var mesh: Mesh = _meshes[0]
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	var sz := mesh.get_aabb().size
	var s := (radius * 2.0) / maxf((sz.x + sz.y + sz.z) / 3.0, 0.01)
	_mesh.scale = Vector3.ONE * s
	add_child(_mesh)


## Меш брили — ним сиплються осколки (`Booms.rock_debris`).
func mesh_resource() -> Mesh:
	return _mesh.mesh if _mesh != null else null


## Уламок щойно з'явився з розколу: відпливає від точки, де була ціла брила.
func calve_from(origin: Vector3) -> void:
	var away := global_position - origin
	away.y = 0.0
	if away.length() < 0.01:
		return
	_drift = away.normalized() * radius * CALVE_REACH / CALVE_TIME
	_drift_left = CALVE_TIME


func _process(delta: float) -> void:
	if _mesh == null:
		return
	_hover_t += delta
	_mesh.position = Vector3(0.0, sin(_hover_t * 0.55) * radius * HOVER_RISE, 0.0)
	_mesh.rotation = Vector3(sin(_hover_t * 0.41) * HOVER_TILT, 0.0,
		cos(_hover_t * 0.33) * HOVER_TILT)
	if _drift_left > 0.0:
		var k := _drift_left / CALVE_TIME          # гальмує до нуля
		global_position += _drift * k * 2.0 * delta
		rotate_y(delta * 0.6 * k)
		_drift_left -= delta


static func _collect(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		_meshes.append((n as MeshInstance3D).mesh)
	for c in n.get_children():
		_collect(c)
