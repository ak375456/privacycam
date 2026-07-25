#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_block_size;
uniform sampler2D u_texture_input;

out vec4 frag_color;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 blocks = max(vec2(1.0), u_size / max(2.0, u_block_size));
  vec2 pixel_uv = (floor(uv * blocks) + 0.5) / blocks;
  frag_color = texture(u_texture_input, pixel_uv);
}
