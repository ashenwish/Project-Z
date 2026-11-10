shader_type canvas_item;
// Датчик HUD (раунд 13): кольца здоровья и ульты горят по сегментам.
// TEXTURE — всё горит, tex_empty — пусто, tex_glow — ярко; tex_mask: R — полоса здоровья, G — полоса ульты.
// Угол как в tools/hud_gen.py: от верха по часовой, доля оборота.

uniform sampler2D tex_empty : filter_nearest;
uniform sampler2D tex_glow : filter_nearest;
uniform sampler2D tex_mask : filter_nearest;
uniform vec2 size_px = vec2(132.0, 120.0);
uniform vec2 center_px = vec2(72.0, 59.0);
uniform float hp_fill = 1.0;
uniform float ult_fill = 1.0;
uniform float hp_segs = 28.0;
uniform float ult_segs = 20.0;
uniform bool hp_glow = false;
uniform bool ult_glow = false;

void fragment() {
	vec4 full = texture(TEXTURE, UV);
	vec4 m = texture(tex_mask, UV);
	vec2 p = floor(UV * size_px) + 0.5 - center_px;
	float a = fract(atan(p.x, -p.y) / (2.0 * PI) + 1.0);
	vec4 col = full;
	if (m.r > 0.5) {
		bool lit = floor(a * hp_segs) < floor(hp_fill * hp_segs + 0.001);
		col = lit ? (hp_glow ? texture(tex_glow, UV) : full) : texture(tex_empty, UV);
	} else if (m.g > 0.5) {
		// раунд 17: ульта заливается плавно по углу, а не целыми сегментами (разделители остаются в рисунке)
		bool lit = a < ult_fill - 0.0005 || ult_fill >= 0.999;
		col = lit ? (ult_glow ? texture(tex_glow, UV) : full) : texture(tex_empty, UV);
	}
	COLOR = col;
}
