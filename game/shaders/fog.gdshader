shader_type canvas_item;
// Fog of war: the L8 cell texture (0 = visible, ~0.55 = explored, 1 = unexplored) is
// stretched over the map with linear filtering; a smoothstep and some value noise turn
// the blocky cell edges into a soft, uneven boundary.

uniform vec2 map_cells;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float fog = texture(TEXTURE, UV).r;
	vec2 cell = UV * map_cells;
	float n = noise(cell * 1.7) * 0.6 + noise(cell * 4.3) * 0.4;
	fog = clamp(fog + (n - 0.5) * 0.35, 0.0, 1.0);
	// Explored areas are dimmed, unexplored ones black.
	float alpha = smoothstep(0.05, 0.5, fog) * 0.55 + smoothstep(0.6, 0.95, fog) * 0.45;
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
