extends Node3D
## КОСМІЧНА МІНА: тримає модель живою (копія space_mine_skin.gd з гри).
##
## Три шари руху:
##
## - ПЕТЛЯ "idle" з моделі: двадцять шипів по черзі висуваються з кілець хвилею
##   по колу, циферблат на маківці обертається. Кожна міна стартує зі свого
##   місця петлі, щоб поле не дихало в такт.
## - ОБЕРТАННЯ І ГОЙДАННЯ кулі — тут, у _process.
## - НЕОН: маска світіння з моделі пульсує, як серцебиття. У грі тривогу вмикає
##   корабель пілота ближче за 38u; на стенді — `arm()` перед підривом.
##
## Матеріал копіюється на кожну міну: інакше пульс однієї світив би всі.

const LOOP_ANIM := "idle"
## Колір спокою і колір тривоги.
const CALM := Color(0.25, 0.9, 1.0)
const ALERT := Color(1.0, 0.16, 0.08)
## Удари серця на секунду: спокій і тривога.
const BEAT_CALM := 0.55
const BEAT_ALERT := 3.2
const SPIN := 0.35          # рад/с навколо вертикалі
const TUMBLE := 0.12        # ледь помітне похитування осі

## 0 — спокій, 1 — повна тривога. Стенд виставляє 1 через `arm()`.
var target_alert := 0.0

var _mats: Array[BaseMaterial3D] = []
var _yaw := randf() * TAU
var _t := randf() * 10.0
var _beat := randf()
var _alert := 0.0
var _spin_dir := 1.0 if randf() < 0.5 else -1.0


func _ready() -> void:
	_dress(self)
	var ap := _find_player(self)
	if ap != null and ap.has_animation(LOOP_ANIM):
		ap.get_animation(LOOP_ANIM).loop_mode = Animation.LOOP_LINEAR
		ap.play(LOOP_ANIM)
		ap.seek(randf() * ap.current_animation_length, true)
		ap.speed_scale = randf_range(0.85, 1.15)


## Міна «почула» корпус: червоніє і частішає, як у грі за мить до дотику.
func arm() -> void:
	target_alert = 1.0


func _process(delta: float) -> void:
	_t += delta
	_alert = move_toward(_alert, target_alert, delta * 2.5)
	# ОБЕРТАННЯ: при тривозі куля крутиться вдвічі швидше
	_yaw = wrapf(_yaw + SPIN * _spin_dir * (1.0 + _alert) * delta, 0.0, TAU)
	rotation = Vector3(sin(_t * 0.7) * TUMBLE, _yaw, cos(_t * 0.53) * TUMBLE)
	position.y = sin(_t * 1.3) * 0.18
	# СЕРЦЕБИТТЯ: два удари поспіль (тук-тук), потім пауза
	_beat = fmod(_beat + delta * lerpf(BEAT_CALM, BEAT_ALERT, _alert), 1.0)
	var pulse := _thump(_beat) + 0.6 * _thump(_beat - 0.18)
	var energy := lerpf(1.2, 2.2, _alert) + pulse * lerpf(2.5, 5.0, _alert)
	var col := CALM.lerp(ALERT, _alert)
	for m in _mats:
		m.emission = col
		m.emission_energy_multiplier = energy


## Один удар: швидкий спалах і плавне згасання. `x` — фаза в межах удару.
func _thump(x: float) -> float:
	if x < 0.0 or x > 0.3:
		return 0.0
	return exp(-x * 18.0) * clampf(x * 60.0, 0.0, 1.0)


func _dress(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			# один матеріал на всю міну (усі частини моделі ділять його)
			var mine: BaseMaterial3D = null
			for m in _mats:
				if m.resource_name == src.resource_name:
					mine = m
			if mine == null:
				mine = src.duplicate() as BaseMaterial3D
				mine.emission_enabled = true
				mine.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				_mats.append(mine)
			mi.set_surface_override_material(s, mine)
	for c in n.get_children():
		_dress(c)


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var ap := _find_player(c)
		if ap != null:
			return ap
	return null
