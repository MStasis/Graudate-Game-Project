shader_type canvas_item;
uniform vec2 player_position = vec2(200.0, 300.0);
uniform vec2 canvas_size = vec2(1200.0, 540.0);
uniform float sight_radius = 155.0;
uniform bool flashlight_enabled = false;
uniform vec2 flashlight_direction = vec2(1.0, 0.0);
uniform float flashlight_range = 390.0;
uniform float cone_half_angle = 0.558505;
void fragment() {
 vec2 offset = UV * canvas_size - player_position;
 float distance_to_player = length(offset);
 float light = 1.0 - smoothstep(sight_radius * 0.70, sight_radius, distance_to_player);
 if (flashlight_enabled && distance_to_player > 0.01) {
  float angular = smoothstep(cos(cone_half_angle), cos(cone_half_angle * 0.75), dot(offset / distance_to_player, normalize(flashlight_direction)));
  float beam = angular * (1.0 - smoothstep(sight_radius * 0.5, flashlight_range, distance_to_player));
  light = max(light, beam);
 }
 float darkness = 1.0 - light;
 COLOR = vec4(0.008, 0.012, 0.022, darkness * 0.995);
}
