class_name Booms
extends Node3D
## ВИБУХИ З ГРИ, як їх кидає fx_director.gd.
##
## - БРИЛА: пакований vfx_air_explosion_01 (Binbun, CC0) у масштабі
##   `radius * VFX_SCALE` плюс осколки її ж каменю — спалах і дим самі по собі
##   читаються як пірат, а не як розбитий камінь.
## - МІНА: vfx_nuke_explosion_01 у масштабі 0.4 (0.9 займав увесь екран).
##
## Звуки ті самі, що в audio_director гри: брила з розколом — rock_break,
## розсипалася начисто — destroy, міна — death_model.

const AirFX := preload("res://skills/explosions/vfx/binbun/effects/vfx_air_explosion_01.tscn")
const NukeFX := preload("res://skills/explosions/vfx/binbun/effects/vfx_nuke_explosion_01.tscn")

const SFX := {
	"destroy": preload("res://skills/explosions/audio/destroy.mp3"),
	"rock_break": preload("res://skills/explosions/audio/rock_break.mp3"),
	"death": preload("res://skills/explosions/audio/death_model.mp3"),
}

const VFX_SCALE := 0.42         # пак розрахований на вибух ~5 м
const MINE_FX_SCALE := 0.4
const DEBRIS_LIFE := 0.72
const DEBRIS_CHUNK := 0.22      # частка ДІАМЕТРА брили: найбільша скалка


## Брила лопнула. `split` — чи лишила вона по собі уламки (від цього звук).
func rock(pos: Vector3, radius: float, mesh: Mesh, split: bool) -> void:
	_play_fx(AirFX.instantiate(), pos, radius * VFX_SCALE, 4.0)
	rock_debris(pos, radius, mesh)
	play_sfx("rock_break" if split else "destroy", -6.0)


func mine(pos: Vector3) -> void:
	_play_fx(NukeFX.instantiate(), pos, MINE_FX_SCALE, 5.0)
	play_sfx("death", -2.0)


## Осколки: сама модель брили, зменшена до скалок, розлітається по колу.
func rock_debris(pos: Vector3, radius: float, mesh: Mesh, count := 7) -> void:
	if mesh == null:
		return
	# Масштаб, за якого модель стає рівно юніт завширшки, тож скалка сказана в
	# юнітах світу, а не в модельних одиницях.
	var sz := mesh.get_aabb().size
	var unit := 1.0 / maxf((sz.x + sz.y + sz.z) / 3.0, 0.01)
	var span: float = maxf(radius, 0.4) * 2.0
	for i in range(count):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Рівномірно по колу плюс невеликий розкид: чистий поділ читається як
		# зірочка з феєрверка, а не як розбитий камінь.
		var ang := TAU * float(i) / float(count) + randf_range(-0.35, 0.35)
		var d := Vector3(cos(ang), 0.0, sin(ang))
		mi.global_position = pos + d * (span * 0.12)
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		mi.scale = Vector3.ONE * (unit * span * DEBRIS_CHUNK * randf_range(0.35, 1.0))

		var life := DEBRIS_LIFE * randf_range(0.75, 1.15)
		var away := pos + d * (span * randf_range(0.55, 1.2)) \
			+ Vector3(0.0, randf_range(-0.35, 0.35), 0.0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", away, life).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation", mi.rotation + Vector3(
			randf_range(-5.0, 5.0), randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)), life)
		tw.tween_property(mi, "scale", Vector3.ZERO, life).set_ease(Tween.EASE_IN)
		tw.finished.connect(mi.queue_free)


func play_sfx(key: String, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = SFX[key]
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# Пакований ефект один раз і прибрати за ним. Частина анімацій пака зациклена,
# і тоді його one_shot ніколи не шле "finished" — тож цикл знімається, а
# таймер страхує.
func _play_fx(fx: Node3D, pos: Vector3, s: float, fallback: float) -> void:
	add_child(fx)
	fx.global_position = pos
	fx.scale = Vector3(s, s, s)

	var anim: AnimationPlayer = fx.get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation("main"):
		anim.get_animation("main").loop_mode = Animation.LOOP_NONE

	fx.one_shot = true
	fx.finished.connect(fx.queue_free)
	fx.play()
	var fx_ref: WeakRef = weakref(fx)
	get_tree().create_timer(fallback).timeout.connect(func() -> void:
		var n: Node = fx_ref.get_ref()
		if is_instance_valid(n):
			n.queue_free()
	)
