class_name ScanPass
extends RefCounted
## ПРОХІД СКАНЕРА ПО КОРПУСУ. Одягає модель, яку сканують, і веде по ній смугу
## знизу вгору; наприкінці роздягає назад. Один ефект на все, що в цій грі
## сканується: скан-куб, вантажний контейнер, купа уламків на місці катастрофи.
##
## ЯК ЦЕ ВЛАШТОВАНО. Кожному видимому мешу під моделлю в `material_overlay`
## кладеться ОДИН спільний ShaderMaterial (vfx/scan_pass.gdshader), і далі
## щокадру пишеться рівно одне число — `band_y`, висота смуги у світі. Накладка
## малюється тією самою геометрією поверх власного матеріалу предмета, тож
## предмет під час скану лишається собою: нічого не підміняється, нічого не
## треба переносити й нема чого загубити при поверненні.
##
## ЧИМ ВІН ВІДРІЗНЯЄТЬСЯ ВІД materialise.gd, який робить схоже. Той ЗАМІНЯЄ
## матеріал поверхні (йому потрібен `discard`, тобто керувати самим корпусом), і
## тому мусить перенести на свій шейдер albedo, normal, metallic, emission —
## усе, що не перенесено, блимає при поверненні. Тут заміни немає взагалі, тож і
## контракту переносу немає: накладку можна вдягти на будь-що, включно з
## поверхнею на чужому шейдері, якої materialise не вміє вдягти й ховає.
##
## СПІЛЬНИЙ МАТЕРІАЛ НА ВСІ МЕШІ ОДНОГО ПРЕДМЕТА — саме тому, що смуга ведеться
## у СВІТОВИХ координатах: у сорока шматків купи уламків сорок різних локальних
## систем і жодної спільної, а світовий y один на всіх. Заразом це один запис
## уніформи на кадр замість сорока. Матеріал НОВИЙ на кожен ефект (а не
## спільний .tres на всю гру): два ящики, які сканують одночасно, мають різні
## смуги.
##
## КОРИСТУВАННЯ:
##
##     _pass = ScanPass.new()
##     _pass.tint = ...                       # до begin(), якщо треба свій колір
##     _pass.begin(model_root, low_y, high_y) # одягнути й поставити на старт
##     ...                                    # щокадру:
##     _pass.set_progress(t)                  # 0..1, знизу вгору
##     _pass.point()                          # куди зараз світити променем
##     _pass.finish()                         # роздягнути (безпечно будь-коли)

const SHADER := "res://skills/scanner/vfx/scan_pass.gdshader"

## Колір заливки і гарячої нитки на передньому краї. Той самий блакитний, яким
## говорить решта HUD; предмет, що вибивається, ставить свій до begin().
var tint := Color(0.22, 0.62, 1.0)
var edge := Color(0.75, 0.95, 1.0)

## Загальна сила ефекту. Її ж крутить згасання на кінцях ходу (див. set_progress).
var intensity := 1.15

## Перешкоди в смузі, 0..1. Тут нуль: збій — це стан приладу, а не його
## нормальна робота, і предмет, який щоразу сканується з перешкодами, читається
## зламаним. Вмикається тим, кому справді треба показати «сигнал поганий».
var glitch := 0.0

## ТОВЩИНА СМУГИ Й ДОВЖИНА СЛІДУ, частками від висоти предмета. Саме частками:
## смуга сталої товщини виглядає ниткою на купі уламків у двадцять юнітів і
## накриває скан-куб цілком.
const BAND_F := 0.085
const TRAIL_F := 0.30
## ...з підлогою у світових одиницях, щоб на дрібному предметі смуга не
## виродилась у лінію завтовшки в піксель.
const BAND_MIN := 0.12
const TRAIL_MIN := 0.35

## Скільки ліній укладається у висоту предмета. Знову частка, а не густина:
## двадцять ліній на куб і двадцять на купу читаються однаково, а стала густина
## дала б на купі суцільну сірість.
const LINES_OVER_SPAN := 22.0

## ЗАПАС ХОДУ ЗА МЕЖІ ГАБАРИТУ, частка висоти. Смуга має заходити на порожнє
## знизу і сходити на порожнє зверху, інакше вона вмикається й вимикається
## просто по корпусу.
const OVERSHOOT := 0.12

## Скільки з ходу займає запалення й скільки — згасання.
const FADE_IN := 0.08
const FADE_OUT := 0.12

var _mat: ShaderMaterial
## Меші, яким треба повернути їхню власну накладку: [mesh, її overlay до нас].
var _worn: Array = []
var _low := 0.0
var _high := 0.0
var _t := 0.0


## Одягнути `root` і поставити смугу на початок ходу. `low_y` і `high_y` — низ і
## верх предмета У СВІТІ; беруться з габариту, який той про себе вже знає.
##
## Повторний begin() спершу роздягає: ефект, запущений удруге на тому самому
## предметі, не має записати власну накладку як «те, що треба повернути».
func begin(root: Node, low_y: float, high_y: float) -> void:
	finish()
	if root == null or not is_instance_valid(root):
		return
	var span: float = maxf(high_y - low_y, 0.001)
	var over := span * OVERSHOOT
	_low = low_y - over
	_high = high_y + over
	_t = 0.0

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter("tint_color", tint)
	_mat.set_shader_parameter("edge_color", edge)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("glitch", glitch)
	_mat.set_shader_parameter("band_half", maxf(span * BAND_F, BAND_MIN))
	_mat.set_shader_parameter("trail_len", maxf(span * TRAIL_F, TRAIL_MIN))
	_mat.set_shader_parameter("lip_half", maxf(span * BAND_F * 0.28, BAND_MIN * 0.28))
	_mat.set_shader_parameter("line_density", LINES_OVER_SPAN / span)

	_dress(root)
	if _worn.is_empty():
		_mat = null
		return
	set_progress(0.0)


## Хід скану, 0..1. Нуль — смуга під предметом, одиниця — над ним.
func set_progress(t: float) -> void:
	if _mat == null:
		return
	_t = clampf(t, 0.0, 1.0)
	_mat.set_shader_parameter("band_y", point_y())
	# Запалення й згасання на кінцях: смуга, що вмикається на повну в кадрі
	# появи, читається як блимання, а не як прохід.
	var fade := 1.0
	if _t < FADE_IN:
		fade = _t / FADE_IN
	elif _t > 1.0 - FADE_OUT:
		fade = (1.0 - _t) / FADE_OUT
	_mat.set_shader_parameter("fade", fade)


## Висота смуги у світі просто зараз.
func point_y() -> float:
	return lerpf(_low, _high, _t)


## Чи вдягнений зараз хоч один меш — тобто чи є чим світити.
func running() -> bool:
	return _mat != null


## Роздягти все назад. Безпечно в будь-який момент і безпечно повторно.
func finish() -> void:
	for w in _worn:
		if is_instance_valid(w[0]):
			w[0].material_overlay = w[1]
	_worn.clear()
	_mat = null


## НЕВИДИМИЙ МЕШ НЕ СКАНУЄТЬСЯ. Частину моделі автор вимикає в сцені (у
## крафт-станції так вимкнені зовнішні модулі), і смуга, що проходить по тому,
## чого на екрані немає, — це світло в порожнечі. Те саме правило, що в
## експортера колізій і в mesh_collider.
func _dress(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.visible and mi.mesh != null:
		_worn.append([mi, mi.material_overlay])
		mi.material_overlay = _mat
	for c in n.get_children():
		_dress(c)
