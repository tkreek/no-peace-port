shader_type canvas_item;
// Composites the original terrain on the GPU.
// Each 32x32 map cell names an atlas tile; atlas pixels with palette index < GROUND_LAYERS
// are placeholders for ground texture <index>, sampled in world space so it tiles seamlessly.
// Other indices are literal colours (cliffs, shores, details).
//
// Enhanced mode uses the upscaled set from tools/upscale/hd_terrain.py instead: an RGBA atlas
// (literal art + coverage) and a layer map telling which ground shows underneath each pixel.

const int CELL = 32;
const int GROUND_LAYERS = 40;

uniform sampler2D cells : filter_nearest;          // RG8: tile id low/high byte
uniform sampler2D atlas_index : filter_nearest;    // R8: palette index
uniform sampler2D atlas_palette : filter_nearest;  // 256x1
uniform sampler2DArray ground : filter_linear_mipmap, repeat_enable;
uniform int atlas_tiles_per_row = 20;
uniform vec2 map_size;
uniform float ground_period = 512.0;

uniform bool enhanced = false;
uniform sampler2D hd_atlas : filter_linear_mipmap;
uniform sampler2D hd_layers : filter_nearest;
uniform int hd_tile = 64;
uniform int hd_columns = 64;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	vec2 w = clamp(world, vec2(0.0), map_size - 0.001);
	ivec2 p = ivec2(floor(w));
	vec2 c = texelFetch(cells, p / CELL, 0).rg;
	int tile = int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
	if (enhanced) {
		float scale = float(hd_tile) / float(CELL);
		vec2 local = clamp((w - vec2(p / CELL * CELL)) * scale, vec2(0.5), vec2(float(hd_tile) - 0.5));
		vec2 origin = vec2(float(tile % hd_columns), float(tile / hd_columns)) * float(hd_tile);
		vec2 atlas_size = vec2(textureSize(hd_atlas, 0));
		vec4 art = textureLod(hd_atlas, (origin + local) / atlas_size, 0.0);
		int layer = int(round(texelFetch(hd_layers, ivec2(origin + local), 0).r * 255.0));
		vec4 base = texture(ground, vec3(world / ground_period, float(layer)));
		COLOR = vec4(mix(base.rgb, art.rgb, art.a), 1.0);
	} else {
		ivec2 origin = ivec2(tile % atlas_tiles_per_row, tile / atlas_tiles_per_row) * CELL;
		int index = int(round(texelFetch(atlas_index, origin + p % CELL, 0).r * 255.0));
		if (index < GROUND_LAYERS) {
			COLOR = texture(ground, vec3(world / ground_period, float(index)));
		} else {
			COLOR = texelFetch(atlas_palette, ivec2(index, 0), 0);
		}
	}
}
