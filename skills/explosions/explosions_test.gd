extends Node3D
## СТЕНД ВИБУХІВ. Поле з брилами трьох тьєрів і космічними мінами, усі вибухи
## ті самі, що в грі (fx/booms.gd).
##
## - Брила тьєра 2-3 розколюється: вибух, осколки її каменю, тріск і два уламки
##   тьєром менше, що відпливають від точки розколу.
## - Брила тьєра 1 розсипається начисто: вибух, осколки, звичайний «destroy».
## - Міна спершу червоніє й частішає (у грі так вона «чує» корпус), потім
##   ядерний вибух.
## За кілька секунд порожнє місце заповнюється знову, як слот спавнера в грі.
##
## Керування:
##   ЛКМ по брилі / міні — підірвати
##   1 — випадкова брила,  2 — випадкова міна,  A — автопідрив,  R — нове поле
##   ЛКМ + рух — крутити камеру,  колесо — наблизити / віддалити

const RockScene := preload("res://skills/explosions/asteroid/test_rock.gd")
const MineScene := preload("res://skills/explosions/mine/space_mine.tscn")

## Слоти поля: позиція і що в ньому стоїть (тьєр брили або 0 — міна).
const SLOTS := [
	[Vector3(-12.0, 0.0, -5.0), 3],
	[Vector3(-5.0, 0.0, 5.0), 2],
	[Vector3(1.0, 0.0, -9.0), 1],
	[Vector3(7.0, 0.0, 2.0), 3],
	[Vector3(14.0, 0.0, -6.0), 2],
	[Vector3(-15.0, 0.0, 7.0), 1],
	[Vector3(-4.0, 0.0, -2.0), 0],
	[Vector3(3.0, 0.0, 11.0), 0],
	[Vector3(15.0, 0.0, 8.0), 0],
]

## Через скільки секунд порожній слот заповнюється знову.
const RESPAWN := 4.0
## Скільки міна «тривожиться» перед підривом.
const MINE_ARM := 0.8
const AUTO_GAP := 1.5
## Скільки пікселів курсор може не долетіти до цілі, щоб клік її зачепив.
const PICK_SLACK := 24.0

@onready var _booms: Booms = $Booms
@onready var _field: Node3D = $Field
@onready var _rig: Node3D = $CameraRig
@onready var _cam: Camera3D = $CameraRig/Camera3D
@onready var _hint: Label = $UI/Hint

## Живі ноди кожного слота: брила, а після розколу — її уламки.
var _alive: Array = []
var _auto := true
var _auto_wait := 1.0

var _yaw := 0.35
var _pitch := -0.8
var _dist := 42.0
var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	_reset_field()
	_update_hint()
	_place_camera()


func _process(delta: float) -> void:
	if not _dragging:
		_yaw += delta * 0.04
	_place_camera()
	if _auto:
		_auto_wait -= delta
		if _auto_wait <= 0.0:
			_auto_wait = AUTO_GAP
			var all := _targets()
			if not all.is_empty():
				_detonate(all.pick_random())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				var rocks := _targets().filter(func(n: Node3D) -> bool: return n is TestRock)
				if not rocks.is_empty():
					_detonate(rocks.pick_random())
			KEY_2:
				var mines := _targets().filter(func(n: Node3D) -> bool: return not (n is TestRock))
				if not mines.is_empty():
					_detonate(mines.pick_random())
			KEY_A:
				_auto = not _auto
				_auto_wait = 0.0
				_update_hint()
			KEY_R:
				_reset_field()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_moved = 0.0
				else:
					_dragging = false
					if _drag_moved < 6.0:
						var hit := _pick(event.position)
						if hit != null:
							_detonate(hit)
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(_dist * 0.9, 8.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(_dist * 1.1, 120.0)
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += event.relative.length()
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.45, 0.4)


## Підірвати брилу чи міну. Повторний підрив міни, що вже тривожиться, — ні.
func _detonate(n: Node3D) -> void:
	if not is_instance_valid(n) or n.has_meta("doomed"):
		return
	n.set_meta("doomed", true)
	var slot: int = n.get_meta("slot")
	if n is TestRock:
		var rock := n as TestRock
		var pos := rock.global_position
		var split := rock.splits()
		_booms.rock(pos, rock.radius, rock.mesh_resource(), split)
		if split:
			# два уламки тьєром менше, поперек погляду камери, щоб було видно обидва
			var side := _cam.global_transform.basis.x
			side.y = 0.0
			side = side.normalized() * rock.radius * 0.45
			for k in [-1.0, 1.0]:
				var frag := _spawn_rock(slot, pos + side * k, rock.tier - 1)
				frag.calve_from(pos)
		_remove(n)
	else:
		(n.get_node("Model") as Node).call("arm")
		get_tree().create_timer(MINE_ARM).timeout.connect(func() -> void:
			if is_instance_valid(n):
				_booms.mine(n.global_position)
				_remove(n)
		)


func _remove(n: Node3D) -> void:
	var slot: int = n.get_meta("slot")
	_alive[slot].erase(n)
	n.queue_free()
	if _alive[slot].is_empty():
		get_tree().create_timer(RESPAWN).timeout.connect(func() -> void:
			if _alive[slot].is_empty():
				_fill(slot)
		)


func _reset_field() -> void:
	for c in _field.get_children():
		c.queue_free()
	_alive.clear()
	for i in SLOTS.size():
		_alive.append([])
		_fill(i)


func _fill(slot: int) -> void:
	var pos: Vector3 = SLOTS[slot][0]
	var tier: int = SLOTS[slot][1]
	if tier > 0:
		_spawn_rock(slot, pos, tier)
	else:
		var m := MineScene.instantiate() as Node3D
		m.set_meta("slot", slot)
		_field.add_child(m)
		m.global_position = pos
		_alive[slot].append(m)


func _spawn_rock(slot: int, pos: Vector3, tier: int) -> TestRock:
	var r := RockScene.new() as TestRock
	r.tier = tier
	r.rotation.y = randf() * TAU
	r.set_meta("slot", slot)
	_field.add_child(r)
	r.global_position = pos
	_alive[slot].append(r)
	return r


func _targets() -> Array:
	var out: Array = []
	for list in _alive:
		for n in list:
			if is_instance_valid(n) and not n.has_meta("doomed"):
				out.append(n)
	return out


## Найближча до курсора ціль, якщо курсор лежить на її колі на екрані.
func _pick(at: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n: Node3D in _targets():
		if _cam.is_position_behind(n.global_position):
			continue
		var r := (n as TestRock).radius if n is TestRock else 2.0
		var c := _cam.unproject_position(n.global_position)
		var edge := _cam.unproject_position(n.global_position + _cam.global_transform.basis.x * r)
		var d := c.distance_to(at)
		if d <= c.distance_to(edge) + PICK_SLACK and d < best_d:
			best = n
			best_d = d
	return best


func _place_camera() -> void:
	_rig.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.position = Vector3(0.0, 0.0, _dist)


func _update_hint() -> void:
	_hint.text = "ЛКМ по цілі: підірвати    1: брила    2: міна    A: автопідрив %s    R: нове поле    ЛКМ+рух: камера    колесо: зум" \
		% ("увімк." if _auto else "вимк.")
