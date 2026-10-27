shader_type canvas_item;
// A unit's picture drawn again over everything, showing only where something drawn later
// (a tree's crown, a roof) hides it: there, a faint silhouette in its team colour with a
// stronger rim. Where the unit is in plain view the screen already holds its own pixels,
// so nothing is drawn and it looks as before. The sprite is sampled exactly as the body
// is (same sheet, region, filter and transform; team colours as hd_sprite.gdshader), so
// the comparison holds at every zoom.

uniform sampler2D team_mask : filter_linear_mipmap;
uniform sampler2D ramps : filter_linear;  // 64 x 9, row t = team t
uniform bool has_team = false;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
instance uniform int palette_row = 1;
instance uniform vec4 ghost_colour = vec4(0.9, 0.9, 0.9, 1.0);

const float FILL_ALPHA = 0.35;
const float RIM_ALPHA = 0.85;
const float RIM_TEXELS = 3.0;  // in the upscaled sheet: about 1.5 px on the map
const float TOLERANCE = 0.08;  // how far the screen may stray from the unit's own colour

void fragment() {
	vec4 c = COLOR;
	if (has_team) {
		float m = texture(team_mask, UV).r;
		vec3 tint = texture(ramps, vec2(clamp(c.r, 0.0, 1.0), (float(palette_row) + 0.5) / 9.0)).rgb;
		c.rgb = mix(c.rgb, tint, m);
	}
	vec4 shown = vec4(0.0);
	if (c.a > 0.5) {
		// Where the body shows, the screen is its colour blended over the ground by its alpha.
		vec3 seen = texture(screen, SCREEN_UV).rgb;
		vec3 off = abs(seen - c.rgb);
		if (max(off.r, max(off.g, off.b)) > (1.0 - c.a) + TOLERANCE) {
			vec2 reach = TEXTURE_PIXEL_SIZE * RIM_TEXELS;
			float edge = min(min(texture(TEXTURE, UV + vec2(reach.x, 0.0)).a, texture(TEXTURE, UV - vec2(reach.x, 0.0)).a),
					min(texture(TEXTURE, UV + vec2(0.0, reach.y)).a, texture(TEXTURE, UV - vec2(0.0, reach.y)).a));
			vec3 lit = min(ghost_colour.rgb * 1.25 + 0.1, vec3(1.0));
			shown = edge < 0.5 ? vec4(lit, RIM_ALPHA) : vec4(mix(c.rgb, lit, 0.6), FILL_ALPHA);
		}
	}
	COLOR = shown;
}
