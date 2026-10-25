shader_type canvas_item;
uniform vec2 player_position = vec2(200.0, 300.0);
uniform vec2 canvas_size = vec2(1200.0, 540.0);
uniform float sight_radius = 155.0;
void fragment() {
 float distance_to_player = distance(UV * canvas_size, player_position);
 float darkness = smoothstep(sight_radius * 0.70, sight_radius, distance_to_player);
 COLOR = vec4(0.008, 0.012, 0.022, darkness * 0.995);
}
