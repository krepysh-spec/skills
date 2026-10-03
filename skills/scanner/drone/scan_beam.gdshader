shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// ПРОМІНЬ АНАЛІЗУ ВІД ДРОНА ДО КУПИ. Малюється на розплющеному конусі
// (recon_drone.gd ставить його вершиною в дрон, а широким краєм на смугу
// сканера), тож це віяло: вузьке біля дрона, широке й тонке там, де воно
// лягає на уламки. По віялу від дрона до цілі біжать імпульси, а дальній край
// горить ниткою, яка збігається зі смугою scan_pass на самій купі.
//
// `along` іде вздовж конуса: 0 біля вершини (дрон), 1 на широкому краї (ціль).
// Береться з вершини, а не з UV: CylinderMesh кладе бік лише в половину UV.

uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 0.8;
// Загальна сила, нею промінь запалюється й гасне.
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_count = 7.0;
uniform float pulse_speed = 2.2;

varying float along;

void vertex() {
	// конус висотою 1: вершина на y = +0.5, широкий край на y = -0.5
	along = 0.5 - VERTEX.y;
}

void fragment() {
	float v = clamp(along, 0.0, 1.0);

	// тіло віяла: тьмяне біля дрона, густіше до цілі
	float body = mix(0.02, 0.08, v);
	// імпульси, що біжать від дрона до цілі
	float p = fract(v * pulse_count - TIME * pulse_speed);
	float pulse = smoothstep(0.8, 1.0, p) * 0.35 * v;
	// гаряча нитка на дальньому краї, там, де віяло лягає на смугу
	float lip = smoothstep(0.93, 1.0, v);
	// ядро біля самого дрона: звідси промінь виходить
	float core = (1.0 - smoothstep(0.0, 0.12, v)) * 0.6;
	// краї віяла яскравіші за середину, щоб воно читалося об'ємом
	float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);

	vec3 col = tint.rgb * (body + pulse + rim * 0.12 * v + core);
	col += edge_color.rgb * lip * 0.7;
	ALBEDO = col * intensity * fade;
	ALPHA = 1.0;
}
