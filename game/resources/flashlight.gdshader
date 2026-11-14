shader_type canvas_item;
uniform vec2 player_position = vec2(200.0, 300.0);
uniform vec2 canvas_size = vec2(1200.0, 540.0);
uniform float sight_radius = 155.0;
uniform bool flashlight_enabled = false;
uniform vec2 flashlight_direction = vec2(1.0, 0.0);
uniform float flashlight_range = 390.0;
uniform float cone_half_angle = 0.558505;
uniform vec4 obstacles[32];
uniform int obstacle_count = 0;
uniform bool ambient_enabled = false;
uniform bool fleet_lighting = false;
bool occluded(vec2 point) {
 for (int i = 0; i < obstacle_count; i++) {
  vec4 r = obstacles[i];
  if (all(greaterThanEqual(point, r.xy)) && all(lessThanEqual(point, r.zw))) { continue; }
  if (all(greaterThanEqual(player_position, r.xy)) && all(lessThanEqual(player_position, r.zw))) { continue; }
  vec2 ray = point - player_position;
  float low = 0.0;
  float high = 1.0;
  bool hit = true;
  for (int axis = 0; axis < 2; axis++) {
   if (abs(ray[axis]) < 0.001) {
    if (player_position[axis] < r[axis] || player_position[axis] > r[axis + 2]) { hit = false; break; }
   } else {
    float a = (r[axis] - player_position[axis]) / ray[axis];
    float b = (r[axis + 2] - player_position[axis]) / ray[axis];
    low = max(low, min(a, b)); high = min(high, max(a, b));
    if (low > high) { hit = false; break; }
   }
  }
  if (hit && low < 0.999 && high > 0.001) { return true; }
 }
 return false;
}
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
 if (ambient_enabled) { darkness = distance_to_player < 550.0 ? 0.0 : 0.995; }
 if (occluded(UV * canvas_size)) { darkness = 1.0; }
 if (fleet_lighting) {
  // Emergency lighting leaves the deck and doors legible. A shallow shadow
  // preserves the feet-based layering without blacking out tall sprite art.
  float shadow = occluded(UV * canvas_size) ? 0.10 : 0.0;
  darkness = ambient_enabled ? shadow : mix(0.68, 0.21, light) + shadow;
 }
 COLOR = vec4(0.008, 0.012, 0.022, darkness * 0.995);
}
