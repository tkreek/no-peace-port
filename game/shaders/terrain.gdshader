shader_type canvas_item;
// Composites the original terrain on the GPU.
// Each 32x32 map cell names an atlas tile; atlas pixels with palette index < GROUND_LAYERS
// are placeholders for ground texture <index>, sampled in world space so it tiles seamlessly.
// Other indices are literal colours (cliffs, shores, details).

const int CELL = 32;
const int GROUND_LAYERS = 40;

uniform sampler2D cells : filter_nearest;          // RG8: tile id low/high byte
uniform sampler2D atlas_index : filter_nearest;    // R8: palette index
uniform sampler2D atlas_palette : filter_nearest;  // 256x1
uniform sampler2DArray ground : filter_linear_mipmap, repeat_enable;
uniform int atlas_tiles_per_row = 20;
uniform vec2 map_size;
uniform float ground_period = 512.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	ivec2 p = clamp(ivec2(floor(world)), ivec2(0), ivec2(map_size) - 1);
	vec2 c = texelFetch(cells, p / CELL, 0).rg;
	int tile = int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
	ivec2 origin = ivec2(tile % atlas_tiles_per_row, tile / atlas_tiles_per_row) * CELL;
	int index = int(round(texelFetch(atlas_index, origin + p % CELL, 0).r * 255.0));
	if (index < GROUND_LAYERS) {
		COLOR = texture(ground, vec3(world / ground_period, float(index)));
	} else {
		COLOR = texelFetch(atlas_palette, ivec2(index, 0), 0);
	}
}
