shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float glow_size : hint_range(0.0, 0.2) = 0.05;
uniform vec2 margin_uv = vec2(0.07, 0.07);
uniform int radius_steps : hint_range(1, 20) = 8;
uniform int angle_samples : hint_range(4, 32) = 12;

vec4 sample_source(sampler2D tex, vec2 uv) {
	vec2 image_uv = (uv - margin_uv) / (vec2(1.0) - 2.0 * margin_uv);
	if (image_uv.x < 0.0 || image_uv.x > 1.0 || image_uv.y < 0.0 || image_uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(tex, image_uv);
}

void fragment() {
	vec4 tex_color = sample_source(TEXTURE, UV);
	
	float best_intensity = 0.0;
	
	for (int r = 1; r <= radius_steps; r++) {
		float radius = glow_size * float(r) / float(radius_steps);
		float found = 0.0;
		for (int a = 0; a < angle_samples; a++) {
			float angle = float(a) / float(angle_samples) * TAU;
			vec2 offset = vec2(cos(angle), sin(angle)) * radius;
			float neighbor_alpha = sample_source(TEXTURE, UV + offset).a;
			found = max(found, neighbor_alpha);
		}
		if (found > 0.5) {
			float distance_ratio = float(r) / float(radius_steps);
			float intensity = 1.0 - distance_ratio;
			best_intensity = max(best_intensity, intensity);
		}
	}
	
	float glow_mask = best_intensity * (1.0 - tex_color.a);
	COLOR = vec4(glow_color.rgb, glow_color.a * glow_mask);
}