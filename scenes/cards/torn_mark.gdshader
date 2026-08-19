shader_type canvas_item;

// TEXTURE = l'icône de la gemme retirée, utilisée uniquement comme masque de forme.
// torn_tex = la texture de papier déchiré, révélée à travers ce masque.
uniform sampler2D torn_tex;

// On échantillonne une petite zone centrale de torn_tex (grain de papier uni,
// sans les bords déchirés du pourtour de l'image) pour que le résultat ait
// toujours l'air d'un simple accroc, quelle que soit la forme du masque.
uniform vec2 torn_sample_origin = vec2(0.35, 0.35);
uniform vec2 torn_sample_size = vec2(0.3, 0.3);

// Masque de surface : la déchirure ne peut apparaître que là où la carte a
// vraiment de la matière visible. On combine deux sources (union, pas
// intersection) : le fond de carte (bg_card.png) et l'icône de mana, qui
// déborde parfois du bord de la carte et rétrécit visuellement en changeant
// de frame de spritesheet (le nœud lui-même ne change pas de taille).
// *_uv_origin/size positionnent, dans l'espace UV de la texture concernée,
// le rectangle exact que ce nœud occupe sur la carte (calculé côté GDScript).
uniform sampler2D card_mask_tex;
uniform vec2 card_mask_uv_origin = vec2(0.0);
uniform vec2 card_mask_uv_size = vec2(1.0);

uniform bool has_mana_mask = false;
uniform sampler2D mana_mask_tex;
uniform vec2 mana_mask_uv_origin = vec2(0.0);
uniform vec2 mana_mask_uv_size = vec2(1.0);

void fragment() {
	vec4 gem_mask = texture(TEXTURE, UV);
	vec2 torn_uv = torn_sample_origin + UV * torn_sample_size;
	vec4 torn = texture(torn_tex, torn_uv);

	vec2 card_uv = card_mask_uv_origin + UV * card_mask_uv_size;
	float surface_alpha = texture(card_mask_tex, card_uv).a;

	if (has_mana_mask) {
		vec2 mana_uv = mana_mask_uv_origin + UV * mana_mask_uv_size;
		float mana_alpha = texture(mana_mask_tex, mana_uv).a;
		surface_alpha = max(surface_alpha, mana_alpha);
	}

	COLOR = vec4(torn.rgb, torn.a * gem_mask.a * surface_alpha);
}
