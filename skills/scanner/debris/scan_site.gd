class_name ScanSite
extends Node3D
## КУПА УЛАМКІВ, ЯКУ СКАНУЮТЬ. Ігрова частина props/wreck_site/wreck_site.gd
## гри, зведена до самого такту скану: смуга vfx/scan_pass повзе по уламках
## знизу вгору SEARCH_S секунд під гудіння scan_loop, наприкінці спалах і іскри.
## Довжина такту, кольори й розміри спалаху ті самі, що в грі.
##
## ЩО ВИКИНУТО І ЧОМУ: мітка над купою, картка HUD, серверна закладка, повтор
## чужого скану й здобич. Усе це розмова з сервером і з HUD, а стенд показує
## рівно те, що бачить пілот під час скану.
##
## Купа — дитина "Pile" (debris_slab.tscn), як у wreck_site.tscn.

signal scan_started
signal scan_finished

## Скільки триває обшук, у секундах. У грі це дзеркало серверного SCAN_SECS.
@export var search_s := 3.0

const SEARCH_COLOR := Color(0.35, 0.8, 1.0)
const CORE_COLOR := Color(0.0, 0.831, 1.0)
const SEARCH_SFX_PATH := "res://skills/scanner/audio/scan_loop.mp3"

var _pile: Node3D
var _span := AABB()
var _pass: ScanPass
var _searching := false
var _search_t := 0.0
var _sfx: AudioStreamPlayer


func _ready() -> void:
	_pile = get_node_or_null("Pile") as Node3D
	if _pile != null:
		_span = _merged_aabb(_pile)
	else:
		push_warning("scan_site: немає дитини \"Pile\", сканувати нічого")


func searching() -> bool:
	return _searching


## Хід поточного скану, 0..1.
func progress() -> float:
	return _search_t


## Висота смуги сканера У СВІТІ просто зараз: туди дрон наводить промінь. Поза
## сканом це середина купи.
func band_y() -> float:
	if _pass != null and _pass.running():
		return _pass.point_y()
	return center().y


## Центр купи у світі.
func center() -> Vector3:
	return global_position + _span.get_center()


## Верхівка купи у світі.
func top_y() -> float:
	return _high_y()


## Півширина купи в площині польоту: з неї дрон рахує радіус кола.
func radius_xz() -> float:
	return maxf(_span.size.x, _span.size.z) * 0.5


## Почати скан. Повторний виклик, поки триває попередній, нічого не робить.
func search() -> void:
	if _searching or _pile == null:
		return
	_searching = true
	_start_sfx()
	_search_t = 0.0
	# Смуга йде по САМИХ УЛАМКАХ: одягається купа, тобто всі її шматки одразу.
	_pass = ScanPass.new()
	_pass.tint = SEARCH_COLOR
	_pass.begin(_pile, _low_y(), _high_y())
	var tw := create_tween()
	tw.tween_interval(search_s)
	tw.tween_callback(_finish)
	scan_started.emit()


func _process(delta: float) -> void:
	if _searching:
		_search_t = minf(_search_t + delta / search_s, 1.0)
		if _pass != null:
			_pass.set_progress(_search_t)


func _finish() -> void:
	_searching = false
	if _pass != null:
		_pass.finish()               # уламкам повертається їхній власний вигляд
	_pass = null
	if _sfx != null:
		_sfx.stop()
	var host := get_parent() if get_parent() != null else self
	ScanFx.flash(host, global_position, CORE_COLOR, 6.5, 0.32)
	ScanFx.sparks(host, global_position, CORE_COLOR, 16)
	scan_finished.emit()


## Підошва і верхівка купи У СВІТІ: межі, між якими їде смуга. Запас на вхід і
## вихід у порожнє додає вже сам ефект (scan_pass.gd::OVERSHOOT).
func _low_y() -> float:
	return global_position.y + _span.position.y


func _high_y() -> float:
	return global_position.y + _span.position.y + _span.size.y


## Гудіння сканера на весь прохід, зациклене на випадок, якщо такт переживе семпл.
func _start_sfx() -> void:
	if _sfx == null:
		var s := load(SEARCH_SFX_PATH) as AudioStreamMP3
		if s == null:
			return
		s.loop = true
		_sfx = AudioStreamPlayer.new()
		_sfx.stream = s
		_sfx.volume_db = -6.0
		add_child(_sfx)
	_sfx.play()


## Габарит піддерева в координатах батька переданого вузла. Модель приносить
## масштаб і на корені, і на вузлах усередині, тож питати можна тільки про
## добуток, а не про меш.
static func _merged_aabb(n: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_boxes(n, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 8.0, 16.0))
	var merged: AABB = boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	return merged


static func _collect_boxes(n: Node, tf: Transform3D, out: Array[AABB]) -> void:
	var t := tf
	if n is Node3D:
		t = tf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(t * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children():
		_collect_boxes(c, t, out)
