shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// ПРОМІНЬ АНАЛІЗУ ВІД ДРОНА ДО КУПИ. Малюється на розплющеному конусі
// (recon_drone.gd ставить його вершиною в дрон, а широким краєм за купу), тож
// це віяло: вузьке біля дрона, широке й тонке там, де воно лягає на уламки.
//
// ВИГЛЯД — М'ЯКЕ ОБ'ЄМНЕ СВІТЛО, а не смуги. Рівне сяйво, що плавно
// розгоряється від дрона, ледь живе під повільним шумом і несе в собі рідкісні
// порошинки, як пил у промені прожектора. Біжучі смуги-імпульси тут були спершу
// і читалися хвилями по променю, тож їх знято.
//
// ПРОМІНЬ — ЦЕ СВІТЛО: ЗА МЕТАЛОМ ЙОГО НЕМАЄ. Конус має свій рівний широкий
// край, і, намальований як є, він висів би в повітрі прямою рискою та
// просвічував би крізь уламки. Тому віяло має власну КАРТУ ТІНЕЙ, як справжнє
// світло: камера в носі дрона дивиться вздовж віяла й записує для кожного
// променя відстань до першої поверхні (beam_depth.gdshader). Точка віяла, що
// лежить далі за цю відстань, не малюється. Так віяло обривається рівно там, де
// вперлося в уламки, а в місці удару горить нитка дотику по обрису моделі.
//
// І ЛИШЕ ПО МОДЕЛІ. Промінь, що ні в що не влучає (на карті тіней порожнеча),
// не малюється взагалі, тож по ширині віяло не більше за силует купи, яким його
// бачить дрон: у проміжках між уламками і повз них світла немає.
//
// Спершу тут була перевірка по буферу глибини ГОЛОВНОЇ камери (крокування
// відрізком дрон -> точка). Вона бачила лише поверхні, повернуті до гравця, і
// крокувала по 2-3 юніти: тонкі пластини й метал зі зворотного боку промінь
// проходив наскрізь. Карта тіней бачить те, що бачить сам дрон.
//
// `along` іде вздовж конуса: 0 біля вершини (дрон), 1 на широкому краї.
// Береться з вершини, а не з UV: CylinderMesh кладе бік лише в половину UV.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 6.0) = 1.8;
// Загальна сила, нею промінь запалюється й гасне.
uniform float fade : hint_range(0.0, 1.0) = 1.0;
// Повільне мерехтіння сяйва: розмір плям шуму у світі і його сила.
uniform float shimmer_scale = 0.35;
uniform float shimmer_amount : hint_range(0.0, 1.0) = 0.3;
// Порошинки: густота у світі, рідкість (вищий степінь — рідші) і яскравість.
uniform float mote_scale = 3.0;
uniform float mote_sharpness = 14.0;
uniform float mote_level = 2.5;

// Карта тіней променя і камера, якою її знято (recon_drone.gd щокадру):
// світ -> координати камери, тангенси половинних кутів огляду по x і y, і
// запас, на який точка може бути глибше за поверхню й ще світитися.
uniform sampler2D shadow_map : filter_nearest, repeat_disable;
uniform mat4 shadow_inv = mat4(1.0);
uniform vec2 shadow_tan = vec2(1.0);
uniform float shadow_bias = 0.35;
// Дальня площина камери тіней: таку відстань карта пише там, де порожньо.
uniform float shadow_far = 250.0;
// Товщина нитки дотику, у юнітах світу.
uniform float contact_width = 0.45;

varying float along;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Гладкий шум значень у 3D: спільний для сяйва й порошинок.
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
				   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
				   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Лінійна глибина сцени (відстань від камери, у юнітах) у точці екрана.
float scene_depth(sampler2D tex, vec2 uv, mat4 inv_proj) {
	float raw = texture(tex, uv).r;
	vec4 sv = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -sv.z / sv.w;
}

void vertex() {
	// конус висотою 1: вершина на y = +0.5, широкий край на y = -0.5
	along = 0.5 - VERTEX.y;
}

void fragment() {
	float v = clamp(along, 0.0, 1.0);

	// Чи дійшов би сюди промінь: ця точка в камері дрона і відстань до першої
	// поверхні на тому самому промені з карти тіней.
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 lp = (shadow_inv * vec4(wp, 1.0)).xyz;
	float dz = -lp.z;
	if (dz <= 0.01) {
		discard;
	}
	vec2 ndc = lp.xy / (dz * shadow_tan);
	if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0) {
		discard;
	}
	vec2 suv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
	float hit = texture(shadow_map, suv).r;
	// за першою поверхнею променя немає
	if (dz > hit + shadow_bias) {
		discard;
	}
	// Чи влучають у метал цей промінь і його сусіди впоперек віяла: так край
	// світла по силуету моделі виходить м'яким, а не сходинками пікселів карти.
	float px = 1.5 / float(textureSize(shadow_map, 0).x);
	float cover = 0.0;
	for (int k = -2; k <= 2; k++) {
		float h = texture(shadow_map, suv + vec2(float(k) * px, 0.0)).r;
		cover += step(h, shadow_far * 0.98);
	}
	cover /= 5.0;
	if (cover <= 0.0) {
		discard;
	}

	// Нитка дотику: точка віяла лежить просто на поверхні за нею.
	float gap = scene_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z;
	float contact = (1.0 - smoothstep(0.0, contact_width, gap)) * smoothstep(0.2, 0.5, v);
	float hug = cover;

	// СЯЙВО: плавно розгоряється від дрона й далі тримається рівним.
	float body = 0.16 * smoothstep(0.0, 0.25, v);
	// ...і ледь живе: повільні плями шуму, що дрейфують у світі. У світових
	// координатах, а не вздовж віяла, тож це не біжить смугами по променю.
	float shimmer = vnoise(wp * shimmer_scale + vec3(0.0, TIME * 0.25, TIME * 0.15));
	body *= 1.0 - shimmer_amount + shimmer_amount * 2.0 * shimmer;
	// ПОРОШИНКИ: дрібні рідкісні іскорки, що повільно пливуть у промені.
	float mote = pow(vnoise(wp * mote_scale + vec3(TIME * 0.2, TIME * 0.45, -TIME * 0.1)), mote_sharpness);
	// ядро біля самого дрона: звідси промінь виходить
	float core = (1.0 - smoothstep(0.0, 0.12, v)) * 1.4;
	// краї віяла яскравіші за середину, щоб воно читалося об'ємом
	float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);

	vec3 col = tint.rgb * ((body + rim * 0.2 * v) * hug + core);
	col += edge_color.rgb * mote * mote_level * hug * smoothstep(0.1, 0.3, v);
	col += edge_color.rgb * contact * 2.6 * cover;
	// Світіння: усе вище одиниці підхоплює глоу оточення, і промінь світиться
	// ореолом, а не лежить пласкою заливкою.
	// рівного краю конуса не видно ніколи
	col *= 1.0 - smoothstep(0.9, 1.0, v);
	ALBEDO = col * intensity * fade;
	ALPHA = 1.0;
}
