shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// ІМПУЛЬС НАПРИКІНЦІ СКАНУ. Накладка поверх моделі (material_overlay, як і в
// scan_pass), по якій від центру предмета розходиться сферична хвиля світла:
// метал спалахує там, де фронт проходить, і коротко тліє позаду нього. Стоїть
// замість кулі-спалаху: результат скану читається як щось, що сталося з
// предметом, а не як вибух поруч із ним.
//
// Фронт ведеться у СВІТОВИХ координатах (відстань до `center`), тож по купі з
// сорока шматків іде ОДНА хвиля, а не сорок.

uniform vec3 center = vec3(0.0);
// Радіус фронту хвилі і його півтовщина, у юнітах світу.
uniform float wave_r = 0.0;
uniform float wave_w = 1.2;
// Загальна сила, нею імпульс гасне наприкінці.
uniform float strength : hint_range(0.0, 1.0) = 1.0;

uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.8, 0.97, 1.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(world_pos, center);
	float off = d - wave_r;
	// фронт хвилі
	float band = 1.0 - smoothstep(0.0, wave_w, abs(off));
	// тління позаду фронту: те, через що хвиля вже пройшла
	float trail = off < 0.0 ? exp(off / (wave_w * 2.5)) * 0.3 : 0.0;
	// силует спалахує сильніше за грані, що дивляться в камеру
	float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.5);

	vec3 col = tint.rgb * (band * (1.0 + rim * 1.5) + trail * (0.6 + rim));
	// найгарячіша нитка на самому фронті
	col += edge_color.rgb * pow(band, 4.0) * 1.6;
	ALBEDO = col * strength * 1.6;
	ALPHA = 1.0;
}
