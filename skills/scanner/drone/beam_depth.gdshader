shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// КАРТА ТІНЕЙ ПРОМЕНЯ ДРОНА. Повноекранний квад перед камерою, що стоїть у носі
// дрона й дивиться вздовж віяла (recon_drone.gd, SubViewport "BeamShadow"). Він
// читає буфер глибини того, що бачить ця камера, і пише в колір ЛІНІЙНУ
// відстань до першої поверхні, у юнітах світу. Порожнеча дає дальню площину
// камери: там промінь ні в що не влучає.
//
// Кольоровий буфер в'юпорта — 16-бітний float (use_hdr_2d), без тонмапу й
// глоу (своє Environment у камери), тож число доходить до scan_beam.gdshader
// як є.
//
// Квад сидить на окремому шарі візуалізації, якого не бачить головна камера.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	// квад 2x2 розтягується на весь екран незалежно від камери
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	ALBEDO = vec3(-v.z / v.w);
	ALPHA = 1.0;
}
