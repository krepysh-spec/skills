@tool
extends Node3D
## КУПА УЛАМКІВ: ШКУРА Й ДРЕЙФ. Вішається на КОРІНЬ купи і робить дві справи
## на всі її деталі одразу, одним проходом по дітях.
##
## ПЕРША: ВДЯГАЄ. Вузли з імпорту FBX належать імпортерові, і material_override,
## прописаний на них у сцені, зникає при першому ж переекспорті. Тому матеріал
## ставиться кодом, як в omega_hull.gd, terraformer_hull.gd і freighter_hull.gd.
## Колір читається З ІМЕНІ ВУЗЛА, до першого підкреслення: "Grey_A01" ->
## wreck_grey.tres. Ідіому взято з worker_hull.gd, де шлях до карт так само
## будувався з `name`, і вона тут доречніша за окремий скрипт на кожну деталь:
## півтори сотні копій того самого коду під купами нічого не пояснюють.
##
## ДРУГА: ВОРУШИТЬ. Кожен шматок поволі перевертається довкола своєї осі й
## гойдається на місці, бо нерухома купа в невагомості читається намальованою
## на тлі. Осі й швидкості в усіх різні, інакше купа обертається як одне ціле.
##
## ЧОМУ ОДИН СКРИПТ НА КУПУ, А НЕ НА КОЖЕН ШМАТОК. У полі сто сім деталей.
## Сто сім скриптів це сто сім окремих _process на кадр; тут один, і він іде
## пласким масивом, де все вже пораховано в _ready.
##
## ЧОМУ НЕ ЯК idle_hover.gd. Той рухає СЕБЕ, а модель висить під ним окремим
## вузлом, бо запис у `rotation` затер би авторський транспонент моделі. Тут
## завести по порожньому вузлу на кожен уламок означало б подвоїти дерево, тож
## авторський транспонент зберігається НЕ вузлом, а полем `rest`: поворот
## щокадру накладається на нього, а не на те, що вийшло минулого кадру. Так
## само не накопичується похибка, і масштаб деталі лишається цілим.

const MATERIALS := "res://skills/scanner/debris/meshes"

## Колір за замовчуванням для деталі, чиє ім'я не називає жодного з відомих.
## Сірий, бо це єдиний варіант пака без власного відтінку: неназвана деталь
## має виглядати як уламок, а не як помилка.
const FALLBACK := "grey"

## У грі їх чотири (blue/green/grey/orange); сюди перенесено лише ті два, якими
## пофарбована купа «ПЛИТА» (debris_slab.tscn).
const KNOWN := ["grey", "orange"]

## Скільки радіан за секунду вибирає найдрібніший уламок і найбільша секція.
## Зверху 0.075 це повний оберт за півтори хвилини, знизу 0.012 за вісім з
## половиною. Перший підбір був утричі швидший (0.03..0.22), і це виявилося
## забагато: купа не дрейфувала, а крутилася. Обертається уламок тим
## повільніше, чим він більший (див. _spin_rate) — однакова кутова швидкість на
## всіх читається як спільний механізм, а не як невагомість.
@export var spin_min := 0.012
@export var spin_max := 0.075

## НАЙБІЛЬШИЙ відхід від авторської точки, в одиницях, і період гойдання в
## секундах. Розмах навмисно дрібний: деталі в купі складені майже впритул, і
## хитавиця, більша за їхній поперечник, просовувала б їх крізь сусідів.
##
## Число означає саме довжину відходу, а не розмах по кожній осі окремо. Осей
## три, вони гойдаються незалежно, і в піку складаються: без поправки нижче
## деталь відходила б на sway * sqrt(3), тобто мало не вдвічі далі, ніж тут
## написано. Перша перевірка дрейфу зловила рівно це — 0.54 при заявлених 0.35.
@export var sway := 0.16
@export var sway_period := 22.0

## Рух вимикається цілком. Тримати купу нерухомою буває треба для знімка на
## стенді, де змазаний кадр ні з чим не звіряється.
@export var drifting := true

## Не ворушити купу, поки її не видно. Сто сім записів transform на кадр не
## варто робити заради того, чого немає на екрані, а купа це декорація: пропуск
## ніде не відгукнеться, бо ні сервер, ні колізії її не читають. Вимикати є
## сенс хіба для знімка збоку в редакторі.
@export var cull_when_offscreen := true

var _t := 0.0
var _pieces: Array[Dictionary] = []


func _ready() -> void:
	for child in get_children():
		var node := child as Node3D
		if node == null:
			continue
		var mat := _material_for(node.name)
		if mat != null:
			for mi in _meshes(node):
				mi.material_override = mat
		_pieces.append(_drift_plan(node))

	# КУПА ВЕДЕ СЕБЕ САМА, тож рушій не має згладжувати її вдруге. Під
	# common/physics_interpolation=true (воно тут увімкнене на весь проєкт)
	# транспонент, записаний поза фізичним тіком, береться за значення ТОГО
	# тіку й малюється між ним і попереднім. Для купи, яку пишуть щокадру, це
	# рівно та сама смиканина, що описана в asteroid.gd і bullet.gd. Діти
	# успадковують режим, тож одного запису на корені досить на всі сто сім.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	if cull_when_offscreen and not Engine.is_editor_hint():
		_watch_visibility()

	# У редакторі процес не потрібен: шкура вже стоїть, а купа, що ворушиться
	# під курсором, це купа, яку неможливо поставити (той самий висновок, що
	# в шапці idle_hover.gd, тільки там його вирішили не робити @tool взагалі
	# — тут сама шкура в редакторі потрібна, тож вимикається саме рух).
	set_process(drifting and not Engine.is_editor_hint())


## Сторож видимості на всю купу. Рахує вигляд рушій, а не ми: жодного
## порівняння відстаней щокадру, і вимикається купа і за кадром, і за спиною.
##
## Час НЕ біжить, поки купа не видно, і це навмисно. Якби _t ріс далі, купа за
## спиною встигала б перевернутися, і поворот голови ловив би стрибок. Пауза ж
## непомітна за означенням: її не видно рівно тоді, коли вона триває.
func _watch_visibility() -> void:
	var eye := VisibleOnScreenNotifier3D.new()
	eye.name = "DriftWatch"
	eye.aabb = _span()
	eye.screen_entered.connect(func() -> void: set_process(drifting))
	eye.screen_exited.connect(func() -> void: set_process(false))
	add_child(eye)


## Габарит купи в її власних координатах, з запасом на гойдання й на те, що
## поворот деталі виносить її кути за межі авторської пози.
func _span() -> AABB:
	var out := AABB()
	var first := true
	for p in _pieces:
		var node: Node3D = p["node"]
		for mi in _meshes(node):
			var box: AABB = node.transform * mi.get_aabb()
			out = box if first else out.merge(box)
			first = false
	if first:
		return AABB(Vector3.ZERO, Vector3.ONE)
	return out.grow(sway + out.size.length() * 0.15)


## Постійні однієї деталі, пораховані раз. Зерно береться З ІМЕНІ ВУЗЛА, а не
## з годинника: купа має виглядати однаково щоразу, як повз неї пролітають, і
## додана в сцену деталь не повинна перетасувати рух усіх решти.
func _drift_plan(node: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node.name)
	var axis := Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
	)
	# Нульовий вектор нормалізувати не можна, а випасти він може.
	if axis.length_squared() < 0.0001:
		axis = Vector3.UP
	return {
		"node": node,
		"rest": node.transform,
		"axis": axis.normalized(),
		"rate": _spin_rate(node, rng) * (1.0 if rng.randf() < 0.5 else -1.0),
		# Три різні періоди на три осі, щоб гойдання не збиралося в один
		# видимий такт, і свої фази, щоб сусіди не хиталися в ногу.
		"phase": Vector3(
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU),
		),
		"beat": Vector3(0.82, 1.0, 1.31) * (TAU / maxf(sway_period, 0.1))
				* rng.randf_range(0.8, 1.25),
	}


## Велика секція корпусу мусить повертатися помітно повільніше за відірвану
## пластину, інакше вся купа крутиться в один темп і важкого в ній нічого
## немає. Розмір береться з меша, а не з масштабу вузла: масштаб у деталей
## різниться разів у два, а самі деталі різняться в п'ять.
func _spin_rate(node: Node3D, rng: RandomNumberGenerator) -> float:
	var meshes := _meshes(node)
	if meshes.is_empty():
		return rng.randf_range(spin_min, spin_max)
	var span := 0.0
	for mi in meshes:
		span = maxf(span, (mi.get_aabb().size * node.scale).length())
	# Уламки лягають десь між однією одиницею й дванадцятьма.
	var heft := clampf(inverse_lerp(1.0, 12.0, span), 0.0, 1.0)
	# Не рівно по прямій: інакше однакові за розміром деталі крутяться в такт.
	return lerpf(spin_max, spin_min, heft) * rng.randf_range(0.75, 1.25)


func _process(delta: float) -> void:
	# Фаза тримається в межах оберту, а не росте від початку сеансу. На
	# годиннику юнікса (1.7e9) множення на швидкість уже не має чим виразити
	# дрібний крок, і кут смикається замість того, щоб їхати; тут до такого
	# далеко, але й приводу вирощувати лічильник немає.
	_t = fposmod(_t + delta, TAU * 1000.0)
	for p in _pieces:
		var node: Node3D = p["node"]
		if not is_instance_valid(node):
			continue
		var rest: Transform3D = p["rest"]
		var beat: Vector3 = p["beat"]
		var phase: Vector3 = p["phase"]
		node.transform = Transform3D(
			# rotated() домножує ПОВОРОТОМ ЗЛІВА, тож масштаб, запечений у
			# авторський базис, лишається цілим.
			rest.basis.rotated(p["axis"], _t * p["rate"]),
			rest.origin + Vector3(
				sin(_t * beat.x + phase.x),
				sin(_t * beat.y + phase.y),
				sin(_t * beat.z + phase.z),
			) * (sway / sqrt(3.0)),
		)


## ResourceLoader кешує, тож сто сім деталей поля ділять рівно чотири
## матеріали на всіх. Нічого їх не анімує, тому спільний ресурс тут безпечний,
## на відміну від .tres під контролером ефекту.
func _material_for(node_name: String) -> Material:
	var prefix := String(node_name).split("_")[0].to_lower()
	if not KNOWN.has(prefix):
		prefix = FALLBACK
	return load("%s/wreck_%s.tres" % [MATERIALS, prefix]) as Material


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
