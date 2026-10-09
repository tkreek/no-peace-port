shader_type canvas_item;
// Enhanced (upscaled) sprite: RGBA atlas with team-coloured pixels stored as grey shading.
// The team mask selects those pixels; the bob's ramp texture maps shading to team colour.

uniform sampler2D team_mask : filter_linear_mipmap;
uniform sampler2D ramps : filter_linear;  // 64 x 9, row t = team t
uniform bool has_team = false;
instance uniform int palette_row = 1;

void fragment() {
	vec4 c = COLOR;
	if (has_team) {
		float m = texture(team_mask, UV).r;
		vec3 tint = texture(ramps, vec2(clamp(c.r, 0.0, 1.0), (float(palette_row) + 0.5) / 9.0)).rgb;
		c.rgb = mix(c.rgb, tint, m);
	}
	COLOR = c;
}
