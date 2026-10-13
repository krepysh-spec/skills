class_name ReconDrone
extends Node3D
## ДРОН-РОЗВІДНИК LRR5. Висить біля корабля; за командою deploy() злітає до
## купи, виходить на коло над нею і, кружляючи, веде промінь аналізу на смугу
## сканера, поки та повзе по уламках. Скан кінчився (спалах купи) — дрон
## вертається на своє місце біля корабля.
##
## СКАН ВЕДЕ КУПА, А НЕ ДРОН. Смуга по уламках, звук, спалах і іскри — це
## debris/scan_site.gd, той самий такт, що в грі. Дрон лише запускає його,
## коли долетів, задає йому довжину (scan_s, бо одне коло за три ігрові секунди
## — це вже не політ, а вихор) і щокадру питає, де смуга, щоб навести на неї
## віяло променя.
##
## Модель із паку ReconnaissanceDroneLRR5 (OBJ), розмір підганяється під SIZE
## так само, як у куба гри (_fit): пак приходить у своїх одиницях.

signal survey_finished

## Довжина дрона в юнітах світу. Корабель ZR4 має 3.82, дрон помітно менший.
@export var size := 2.0
## Де дрон висить біля корабля, у координатах корабля (корабель дивиться в -Z).
@export var dock_offset := Vector3(3.3, 0.9, 0.6)
## Скільки триває скан із дроном, у секундах: стільки ж і одне коло.
@export var scan_s := 7.0
@export var launch_s := 2.0
@export var return_s := 2.0
## Наскільки коло ширше за купу і наскільки вище за її верхівку.
@export var orbit_margin := 6.0
@export var orbit_air := 3.0
## Поворот моделі навколо Y, щоб її ніс дивився в -Z (так дивиться вузол).
## У паку довга штанга лежить у -Z, але це хвіст: ніс і сенсор дрона — кільце
## з крилами, тож модель розвернуто.
@export var model_yaw_deg := 180.0

## Віяло: півширина на цілі в частках радіуса купи і півтовщина в юнітах.
## Навмисно на всю купу: що видно, вирішує карта тіней (світло лише там, де
## промінь влучає в метал), тож ширше за силует моделі віяло не буде.
const FAN_SPREAD := 1.05
const FAN_THICK := 0.35
## У скільки разів віяло довше за відстань до осі купи. Край конуса має лежати
## ЗА металом: тоді те, де віяло кінчається, вирішує сама модель (шейдер
## обриває кожен промінь на першому уламку, а ті, що ні в що не влучають, не
## малює взагалі), а не пряма риска конуса.
const FAN_REACH := 1.5
const BEAM_COLOR := Color(0.35, 0.8, 1.0)

## КАРТА ТІНЕЙ ПРОМЕНЯ (див. шапку scan_beam.gdshader): камера в носі дрона,
## що дивиться вздовж віяла. Віяло широке й тонке, тож і карта така сама:
## 1024 променя впоперек, 128 рядків по товщині.
const SHADOW_SIZE := Vector2i(1024, 128)
const SHADOW_FAR := 250.0
## Шар візуалізації квада, що пише карту: його бачить лише камера дрона.
const SHADOW_LAYER := 20
const BEAM_DEPTH_SHADER := "res://skills/scanner/drone/beam_depth.gdshader"

enum State { DOCKED, LAUNCH, ORBIT, RETURN }

var ship: Node3D

var _state := State.DOCKED
var _site: ScanSite
var _t := 0.0
var _clock := 0.0
var _from := Vector3.ZERO
var _ctrl := Vector3.ZERO
var _angle := 0.0
var _beam_fade := 0.0
var _beam_mat: ShaderMaterial
var _prev := Vector3.ZERO
var _shadow_vp: SubViewport
var _shadow_cam: Camera3D
var _main_cam_masked := false

@onready var _model: Node3D = $Model
@onready var _beam: MeshInstance3D = $Beam
@onready var _eye: OmniLight3D = $Eye


func _ready() -> void:
	_fit()
	# Віяло живе у СВІТОВИХ координатах: його кінці — дрон і купа, і повороти
	# самого дрона (він хилиться й крутиться на колі) його не стосуються.
	_beam.top_level = true
	_beam.visible = false
	if _beam.material_override is ShaderMaterial:
		_beam_mat = (_beam.material_override as ShaderMaterial).duplicate()
		_beam_mat.set_shader_parameter("tint", BEAM_COLOR)
		_beam.material_override = _beam_mat
	_build_shadow()
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("shadow_map", _shadow_vp.get_texture())
		_beam_mat.set_shader_parameter("shadow_far", SHADOW_FAR)
	_eye.light_energy = 0.0
	if ship != null:
		global_position = _dock_pos()
	_prev = global_position


## Підігнати модель під `size` і поставити її центр у початок координат вузла.
func _fit() -> void:
	var mi := _model as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var box := mi.mesh.get_aabb()
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest < 0.0001:
		return
	var s := size / longest
	var b := Basis(Vector3.UP, deg_to_rad(model_yaw_deg)).scaled(Vector3.ONE * s)
	_model.transform = Transform3D(b, -(b * box.get_center()))


## Камера карти тіней у власному SubViewport. В'юпорт ділить світ із головним
## (own_world_3d вимкнено), тож бачить ту саму купу, але має своє Environment:
## без неба, тонмапу й глоу, щоб у колір дійшло саме число відстані.
## Малює лише тоді, коли віяло горить (_tick_beam).
func _build_shadow() -> void:
	_shadow_vp = SubViewport.new()
	_shadow_vp.name = "BeamShadow"
	_shadow_vp.size = SHADOW_SIZE
	_shadow_vp.use_hdr_2d = true
	_shadow_vp.msaa_3d = Viewport.MSAA_DISABLED
	_shadow_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	_shadow_cam = Camera3D.new()
	_shadow_cam.keep_aspect = Camera3D.KEEP_WIDTH
	# ближня площина за кінчиком носа: інакше перед камерою стояв би сам дрон
	_shadow_cam.near = 1.0
	_shadow_cam.far = SHADOW_FAR
	_shadow_cam.environment = env
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	quad.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = load(BEAM_DEPTH_SHADER)
	quad.material_override = mat
	quad.layers = 1 << (SHADOW_LAYER - 1)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# квад розтягує на весь екран вершинний шейдер, тож його не можна відкидати
	# за межами огляду
	quad.extra_cull_margin = 16384.0
	_shadow_cam.add_child(quad)
	_shadow_vp.add_child(_shadow_cam)
	add_child(_shadow_vp)
	_shadow_cam.current = true


func busy() -> bool:
	return _state != State.DOCKED


## Злетіти до купи й обстежити її. Поки дрон не повернувся, нічого не робить.
func deploy(site: ScanSite) -> void:
	if busy() or site == null or site.searching():
		return
	_site = site
	# Вхід на коло — точка кола, найближча до корабля: дрон летить прямо, а не
	# огинає купу.
	var c := _site.center()
	var to_me := global_position - c
	_angle = atan2(to_me.z, to_me.x)
	_from = global_position
	var entry := _orbit_point(_angle)
	_ctrl = (_from + entry) * 0.5 + Vector3.UP * 5.0
	_go(State.LAUNCH)


func _go(s: State) -> void:
	_state = s
	_t = 0.0


func _process(delta: float) -> void:
	# З ПЕРШОГО Ж КАДРУ, а не з першого променя: квад карти тіней є в сцені
	# відразу, і поки головна камера його бачить, він заливає весь екран.
	_mask_main_camera()
	_clock += delta
	_t += delta
	var look := Vector3.ZERO           # куди повернути ніс, нуль — за рухом

	match _state:
		State.DOCKED:
			if ship != null:
				global_position = _dock_pos()
				look = -ship.global_basis.z
		State.LAUNCH:
			var k := smoothstep(0.0, 1.0, _t / launch_s)
			global_position = _bezier(_from, _ctrl, _orbit_point(_angle), k)
			if _t >= launch_s:
				_go(State.ORBIT)
				_site.search_s = scan_s
				_site.scan_finished.connect(_on_scan_finished, CONNECT_ONE_SHOT)
				_site.search()
		State.ORBIT:
			# Кутова швидкість росте з нуля: політ до кола закінчився зупинкою,
			# і рвонути з місця на коло виглядало б як телепорт.
			var w := TAU / scan_s * smoothstep(0.0, 0.8, _t)
			_angle += w * delta
			global_position = _orbit_point(_angle) + Vector3(0.0, sin(_clock * 2.3) * 0.25, 0.0)
			look = _beam_target() - global_position
		State.RETURN:
			var k := smoothstep(0.0, 1.0, _t / return_s)
			global_position = _bezier(_from, _ctrl, _dock_pos(), k)
			if k > 0.85 and ship != null:
				look = -ship.global_basis.z
			if _t >= return_s:
				_go(State.DOCKED)
				survey_finished.emit()

	if look == Vector3.ZERO:
		look = global_position - _prev
	_turn_to(look, delta)
	_prev = global_position
	_tick_beam(delta)


func _on_scan_finished() -> void:
	_from = global_position
	_ctrl = (_from + _dock_pos()) * 0.5 + Vector3.UP * 4.0
	_go(State.RETURN)


## Місце біля корабля: зміщення в його координатах плюс власне погойдування,
## не в такт кораблю.
func _dock_pos() -> Vector3:
	var p := ship.global_transform * dock_offset
	return p + Vector3(0.0, sin(_clock * 1.7 + 1.0) * 0.1, 0.0)


func _orbit_point(a: float) -> Vector3:
	var c := _site.center()
	var r := _site.radius_xz() + orbit_margin
	return Vector3(c.x + cos(a) * r, _site.top_y() + orbit_air, c.z + sin(a) * r)


## Куди б'є промінь: вісь купи на висоті смуги сканера.
func _beam_target() -> Vector3:
	var c := _site.center()
	return Vector3(c.x, _site.band_y(), c.z)


func _turn_to(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.000001:
		return
	var want := Basis.looking_at(dir.normalized(), Vector3.UP)
	global_basis = global_basis.orthonormalized().slerp(want, 1.0 - exp(-6.0 * delta))


static func _bezier(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


## Віяло горить, поки дрон на колі і купа сканується; запалюється й гасне
## плавно. Розплющений конус ставиться вершиною в дрон, широким краєм на смугу:
## вісь Y конуса — від цілі до дрона, X лежить горизонтально, Z — товщина.
func _tick_beam(delta: float) -> void:
	var on := _state == State.ORBIT and _site != null and _site.searching()
	_beam_fade = move_toward(_beam_fade, 1.0 if on else 0.0, delta * 3.0)
	_eye.light_energy = _beam_fade * 5.0
	_beam.visible = _beam_fade > 0.01 and _site != null
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _beam.visible \
		else SubViewport.UPDATE_DISABLED
	if not _beam.visible:
		return
	var from := global_position + global_basis * Vector3(0.0, 0.0, -size * 0.3)
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("fade", _beam_fade)
	var to := from + (_beam_target() - from) * FAN_REACH
	var d := from - to
	var length := d.length()
	if length < 0.01:
		return
	var y := d / length
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	var hw := _site.radius_xz() * FAN_SPREAD * FAN_REACH
	_beam.global_transform = Transform3D(Basis(x * hw, y * length, z * FAN_THICK), (from + to) * 0.5)

	# Камера тіней стоїть у вершині віяла й дивиться на його широкий край; кут
	# огляду рівно накриває віяло (з запасом), рядків вистачає на його товщину.
	_shadow_cam.global_transform = Transform3D(Basis.looking_at(-y, Vector3.UP), from)
	var half := atan(hw / length) * 1.1
	_shadow_cam.fov = rad_to_deg(half * 2.0)
	if _beam_mat != null:
		var tx := tan(half)
		_beam_mat.set_shader_parameter("shadow_inv", _shadow_cam.global_transform.affine_inverse())
		_beam_mat.set_shader_parameter("shadow_tan",
			Vector2(tx, tx * float(SHADOW_SIZE.y) / float(SHADOW_SIZE.x)))


## Головна камера не повинна бачити квад карти тіней: він розтягується на весь
## екран будь-якої камери, що його побачить.
func _mask_main_camera() -> void:
	if _main_cam_masked:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cam.set_cull_mask_value(SHADOW_LAYER, false)
		_main_cam_masked = true
