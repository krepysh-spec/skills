extends Node3D
## СТЕНД СКАНЕРА. Купа уламків, корабель ZR4 і дрон-розвідник LRR5 біля нього.
## Дрон злітає до купи, кружляє над нею й веде промінь аналізу, а сама смуга по
## уламках іде тим самим тактом, що в грі (debris/scan_site.gd).
##
## Керування:
##   Space / E   — випустити дрона на скан
##   S           — скан без дрона, як у грі (3 с)
##   A           — автоскан по колу (увімкнено на старті)
##   ЛКМ + рух   — крутити камеру,  колесо — наблизити / віддалити

## Пауза між автосканами, у секундах.
const AUTO_GAP := 1.6

## Дросель сопел у спокої і під час скану (jet_thrust.gd: 0 — вимкнено, 1 — повна тяга).
const JET_IDLE := 0.35
const JET_SCAN := 0.6

@onready var _site: ScanSite = $ScanSite
@onready var _ship: Node3D = $Ship
@onready var _drone: ReconDrone = $Drone
@onready var _rig: Node3D = $CameraRig
@onready var _cam: Camera3D = $CameraRig/Camera3D
@onready var _hint: Label = $UI/Hint
@onready var _bar: ProgressBar = $UI/Progress

var _auto := true
var _auto_wait := 0.8
var _t := 0.0
var _ship_rest := Vector3.ZERO
var _jets: Array[Node] = []

var _yaw := 0.6
var _pitch := -0.55
var _dist := 46.0
var _dragging := false


func _ready() -> void:
	_ship_rest = _ship.position
	_ship.look_at(_site.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_jets = _ship.find_children("Jet", "MeshInstance3D", true, false)
	_set_jets(JET_IDLE)
	_site.scan_started.connect(func() -> void: _set_jets(JET_SCAN))
	_site.scan_finished.connect(_on_scan_finished)
	_drone.ship = _ship
	_drone.survey_finished.connect(func() -> void: _auto_wait = AUTO_GAP)
	_update_hint()
	_place_camera()


func _process(delta: float) -> void:
	_t += delta
	# корабель висить на місці й ледь гойдається, як у секторі на холостому ходу
	_ship.position = _ship_rest + Vector3(0.0, sin(_t * 1.3) * 0.12, 0.0)

	if not _dragging:
		_yaw += delta * 0.05
	_place_camera()

	_bar.value = _site.progress() * 100.0 if _site.searching() else 0.0

	if _auto and not _site.searching() and not _drone.busy():
		_auto_wait -= delta
		if _auto_wait <= 0.0:
			_drone.deploy(_site)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_E:
				_drone.deploy(_site)
			KEY_S:
				if not _drone.busy():
					_site.search_s = 3.0
					_site.search()
			KEY_A:
				_auto = not _auto
				_auto_wait = 0.0
				_update_hint()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(_dist * 0.9, 8.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(_dist * 1.1, 120.0)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.45, 0.4)


func _on_scan_finished() -> void:
	_set_jets(JET_IDLE)
	_auto_wait = AUTO_GAP


func _set_jets(p: float) -> void:
	for j in _jets:
		if j.has_method("set_power"):
			j.set_power(p)


func _place_camera() -> void:
	_rig.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.position = Vector3(0.0, 0.0, _dist)


func _update_hint() -> void:
	_hint.text = "Space / E: дрон на скан    S: скан без дрона    A: автоскан %s    ЛКМ: камера    колесо: зум" \
		% ("увімк." if _auto else "вимк.")
