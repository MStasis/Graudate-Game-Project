shader_type canvas_item;
render_mode unshaded;

uniform float cycle_seconds : hint_range(1.0, 12.0, 0.1) = 4.0;
// Use a fixed phase for still captures. Negative values use the live clock.
uniform float preview_phase : hint_range(-1.0, 1.0, 0.01) = -1.0;

float falloff(vec2 uv, vec2 center, vec2 radius) {
	vec2 offset = (uv - center) / radius;
	return exp(-dot(offset, offset) * 2.0);
}

void fragment() {
	float phase = preview_phase < 0.0 ? TIME / cycle_seconds : preview_phase;
	float pulse = 0.5 - 0.5 * cos(TAU * phase);

	// Texture-space masks keep the spill aligned when the background is cropped.
	float bulb = falloff(UV, vec2(0.7124, 0.4747), vec2(0.010, 0.031));
	float door_spill = falloff(UV, vec2(0.7124, 0.4747), vec2(0.108, 0.220));
	float floor_spill = falloff(UV, vec2(0.7110, 0.8700), vec2(0.050, 0.143));

	vec3 base = COLOR.rgb;
	float red_ink = smoothstep(0.012, 0.23, base.r - max(base.g, base.b));
	float spill = max(door_spill * 0.79, floor_spill * 0.58) * red_ink;
	float response = max(bulb, spill);
	float exposure = mix(-0.73, 0.34, pulse) * response;
	vec3 illuminated = base * (1.0 + exposure);
	illuminated += vec3(0.28, 0.050, 0.016) * response * pulse;
	COLOR = vec4(clamp(illuminated, vec3(0.0), vec3(1.0)), COLOR.a);
}
