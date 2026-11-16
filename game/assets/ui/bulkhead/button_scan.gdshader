shader_type canvas_item;
render_mode unshaded;

uniform float scan_position = -0.24;

void fragment() {
	float distance_to_scan = abs(UV.x + (UV.y - 0.5) * 0.16 - scan_position);
	float glow = 1.0 - smoothstep(0.0, 0.14, distance_to_scan);
	float line = 1.0 - smoothstep(0.0, 0.018, distance_to_scan);
	COLOR = vec4(1.0, 0.70, 0.40, 0.18 * glow + 0.18 * line);
}
