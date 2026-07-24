shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform float glow_size : hint_range(0.0, 0.1) = 0.03;
uniform vec2 margin_uv = vec2(0.07, 0.07);

vec4 sample_source(sampler2D tex, vec2 uv) {
	vec2 image_uv = (uv - margin_uv) / (vec2(1.0) - 2.0 * margin_uv);
	if (image_uv.x < 0.0 || image_uv.x > 1.0 || image_uv.y < 0.0 || image_uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(tex, image_uv);
}

void fragment() {
	vec4 tex_color = sample_source(TEXTURE, UV);
	
	float max_alpha = 0.0;
	int samples = 12;
	for (int i = 0; i < samples; i++) {
		float angle = float(i) / float(samples) * TAU;
		vec2 offset = vec2(cos(angle), sin(angle)) * glow_size;
		float neighbor_alpha = sample_source(TEXTURE, UV + offset).a;
		max_alpha = max(max_alpha, neighbor_alpha);
	}
	
	float glow_mask = max_alpha * (1.0 - tex_color.a);
	COLOR = vec4(glow_color.rgb, glow_color.a * glow_mask);
}