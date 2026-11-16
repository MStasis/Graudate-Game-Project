shader_type canvas_item;
render_mode unshaded;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 sprite = texture(TEXTURE, UV);
	float lightness = dot(sprite.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(tint.rgb * (0.66 + 0.46 * lightness), tint.a * sprite.a);
}
