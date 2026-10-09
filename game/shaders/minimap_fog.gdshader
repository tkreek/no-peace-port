shader_type canvas_item;
// The fog of war over the minimap: black, see-through where visible, dimmed where only
// explored. Same 0/1 cell textures as fog.gdshader (TEXTURE = visible).

uniform sampler2D explored_cells : filter_nearest;

void fragment() {
	float seen = clamp(texture(TEXTURE, UV).r * 255.0, 0.0, 1.0);
	float known = clamp(texture(explored_cells, UV).r * 255.0, 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, mix(1.0, mix(0.41, 0.0, seen), known));
}
