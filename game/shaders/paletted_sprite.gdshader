shader_type canvas_item;
// Draws an LA8 sprite atlas (L = palette index, A = coverage) through a palette row.
// Row 0 is the object's base palette; rows 1..8 are the original team colour variants.

uniform sampler2D palette : filter_nearest;
instance uniform int palette_row = 1;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	int index = int(round(texel.r * 255.0));
	vec4 color = texelFetch(palette, ivec2(index, palette_row), 0);
	COLOR = vec4(color.rgb * modulate.rgb, texel.a * modulate.a);
}
