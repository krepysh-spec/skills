shader_type sky;

// Тло стенду: чорний космос із розсипом зірок і ледь помітною туманністю, щоб
// адитивна смуга сканера читалася так само, як у секторі, а не на сірому тлі
// редактора.

uniform vec3 base_color : source_color = vec3(0.004, 0.006, 0.014);
uniform vec3 nebula_color : source_color = vec3(0.05, 0.09, 0.2);
uniform float star_density = 220.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = base_color;

	float n = noise(d * 2.5) * 0.6 + noise(d * 6.0) * 0.3 + noise(d * 13.0) * 0.1;
	col += nebula_color * smoothstep(0.45, 0.85, n);

	vec3 cell = floor(d * star_density);
	float h = hash(cell);
	if (h > 0.994) {
		vec3 c = (cell + 0.5) / star_density;
		float dist = length(d - normalize(c)) * star_density;
		float star = smoothstep(0.6, 0.0, dist) * (h - 0.994) / 0.006;
		col += vec3(0.8, 0.9, 1.0) * star * 1.6;
	}
	COLOR = col;
}
