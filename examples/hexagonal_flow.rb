# frozen_string_literal: true

# Hexagon X5 - Hexagonal Flow Pattern
# Original: https://www.shadertoy.com/view/4cVfWG
# Created by @byt3_m3chanic - 12/17/2024
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rbgl'
require 'rlsl'

WIDTH = 640
HEIGHT = 480

# Hexagonal grid constants
module HexConstants
  N = 3.0
  S4 = 0.577350  # 1/sqrt(3)
  S3 = 0.288683  # 1/(2*sqrt(3))
  S2 = 0.866025  # sqrt(3)/2
end

shader = RLSL.define(:hexflow) do
  uniforms do
    float :time
    vec2 :mouse
  end

  helpers(:c) do
    n = HexConstants::N
    s4 = HexConstants::S4
    s3 = HexConstants::S3
    s2 = HexConstants::S2

    <<~C
      // Constants (PI and TAU already defined in code_generator.rb)
      #define PI2 6.283185307f

      static const float N = #{n}f;
      static const float s4 = #{s4}f;
      static const float s3 = #{s3}f;
      static const float s2 = #{s2}f;

      // Global state
      static vec3 clr, trm;
      static float tk, ln;
      static float r2_cos, r2_sin, r3_cos, r3_sin;

      // 2x2 matrix multiply
      static inline vec2 mat2_mul(float c, float s, vec2 v) {
        return vec2_new(c * v.x + s * v.y, -s * v.x + c * v.y);
      }

      // Hash function (custom version for hex grid)
      static float hex_hash21(vec2 p) {
        p.x = fmodf(p.x, 3.0f * N);
        if (p.x < 0.0f) p.x += 3.0f * N;
        float d = p.x * 26.37f + p.y * 45.93f;
        return fract(sinf(d) * 4374.23f);
      }

      // Hexagon grid system
      static vec4 hexgrid(vec2 uv) {
        vec2 p1 = vec2_new(floorf(uv.x / 1.732f) + 0.5f, floorf(uv.y) + 0.5f);
        vec2 p2 = vec2_new(floorf((uv.x - 1.0f) / 1.732f) + 0.5f, floorf(uv.y - 0.5f) + 0.5f);

        vec2 h1 = vec2_new(uv.x - p1.x * 1.732f, uv.y - p1.y);
        vec2 h2 = vec2_new(uv.x - (p2.x + 0.5f) * 1.732f, uv.y - (p2.y + 0.5f));

        if (vec2_dot(h1, h1) < vec2_dot(h2, h2)) {
          return vec4_new(h1.x, h1.y, p1.x, p1.y);
        } else {
          return vec4_new(h2.x, h2.y, p2.x + 0.5f, p2.y + 0.5f);
        }
      }

      // Draw function with anti-aliasing
      static void draw(float d, float px, vec3 *C) {
        float b = fabsf(d) - tk;

        // Shadow
        float t1 = smoothstep(0.1f + px, -px, b - 0.01f);
        C->x = mix_f(C->x, C->x * 0.25f, t1);
        C->y = mix_f(C->y, C->y * 0.25f, t1);
        C->z = mix_f(C->z, C->z * 0.25f, t1);

        // Fill
        float t2 = smoothstep(px, -px, b);
        C->x = mix_f(C->x, clr.x, t2);
        C->y = mix_f(C->y, clr.y, t2);
        C->z = mix_f(C->z, clr.z, t2);

        // Highlight
        float t3 = smoothstep(0.01f + px, -px, b + 0.1f);
        C->x = mix_f(C->x, clamp_f(C->x + 0.2f, C->x, 0.95f), t3);
        C->y = mix_f(C->y, clamp_f(C->y + 0.2f, C->y, 0.95f), t3);
        C->z = mix_f(C->z, clamp_f(C->z + 0.2f, C->z, 0.95f), t3);

        // Trim
        float t4 = smoothstep(px, -px, fabsf(b) - ln);
        C->x = mix_f(C->x, trm.x, t4);
        C->y = mix_f(C->y, trm.y, t4);
        C->z = mix_f(C->z, trm.z, t4);
      }

      // Procedural texture replacement (since we don't have iChannel0)
      static vec3 proc_texture(vec2 p) {
        float n = sinf(p.x * 10.0f) * sinf(p.y * 10.0f);
        n = n * 0.5f + 0.5f;
        return vec3_new(0.906f * n, 0.282f * n, 0.075f * n);
      }
    C
  end

  fragment do
    <<~C
      // Initialize rotation matrices (1.047 radians = 60 degrees)
      r2_cos = cosf(1.047f);
      r2_sin = sinf(1.047f);
      r3_cos = cosf(-1.047f);
      r3_sin = sinf(-1.047f);

      // Normalized coordinates
      vec2 uv_screen = vec2_new(
        (2.0f * frag_coord.x - resolution.x) / fmaxf(resolution.x, resolution.y),
        (2.0f * frag_coord.y - resolution.y) / fmaxf(resolution.x, resolution.y)
      );

      // Mouse offset
      vec2 mouse_norm = vec2_new(
        (2.0f * u.mouse.x - resolution.x) / resolution.x,
        (2.0f * u.mouse.y - resolution.y) / resolution.y
      );

      // Log-polar transformation
      float len = sqrtf(uv_screen.x * uv_screen.x + uv_screen.y * uv_screen.y);
      if (len < 0.001f) len = 0.001f;

      vec2 uv_polar = vec2_new(
        -logf(len) - mouse_norm.x,
        -atan2f(uv_screen.y, uv_screen.x) - mouse_norm.y
      );

      uv_polar = vec2_div(uv_polar, 3.628f);
      uv_polar = vec2_mul(uv_polar, N);

      // Animation
      uv_polar.y += u.time * 0.05f;
      uv_polar.x += u.time * 0.15f;

      float sc = 3.0f;
      float px = 0.01f;  // Approximate fwidth

      // Hexgrid with swapped coordinates
      vec4 H = hexgrid(vec2_new(uv_polar.y * sc, uv_polar.x * sc));
      vec2 p = vec2_new(H.x, H.y);
      vec2 id = vec2_new(H.z, H.w);

      float hs = hex_hash21(id);

      // Random rotation
      if (hs < 0.5f) {
        if (hs < 0.25f) {
          p = mat2_mul(r3_cos, r3_sin, p);
        } else {
          p = mat2_mul(r2_cos, r2_sin, p);
        }
      }

      // Triangle vertices
      vec2 p0 = vec2_new(p.x - (-s3), p.y - 0.5f);
      vec2 p1 = vec2_new(p.x - s4, p.y);
      vec2 p2 = vec2_new(p.x - (-s3), p.y - (-0.5f));

      vec3 d3 = vec3_new(vec2_length(p0), vec2_length(p1), vec2_length(p2));
      vec2 pp = vec2_new(0.0f, 0.0f);

      if (d3.x > d3.y) pp = p1;
      if (d3.y > d3.z) pp = p2;
      if (d3.z > d3.x && d3.y > d3.x) pp = p0;

      ln = 0.015f;
      tk = 0.14f + 0.1f * sinf(uv_polar.x * 5.0f + u.time);

      vec3 C = vec3_new(0.0f, 0.0f, 0.0f);

      // Tile background (hexagon SDF)
      float d = fmaxf(fabsf(p.x) * s2 + fabsf(p.y) * 0.5f, fabsf(p.y)) - (0.5f - ln);
      vec3 tex_col = proc_texture(vec2_mul(p, 2.0f));

      float t_bg = smoothstep(px, -px, d);
      C.x = mix_f(0.0125f, tex_col.x, t_bg);
      C.y = mix_f(0.0125f, tex_col.y, t_bg);
      C.z = mix_f(0.0125f, tex_col.z, t_bg);

      // Shading
      float shade1 = clamp_f(1.0f - (H.y + 0.15f), 0.0f, 1.0f);
      float t_s1 = mix_f(smoothstep(px, -px, d + 0.035f), 0.0f, shade1);
      C.x = mix_f(C.x, C.x + 0.1f, t_s1);
      C.y = mix_f(C.y, C.y + 0.1f, t_s1);
      C.z = mix_f(C.z, C.z + 0.1f, t_s1);

      float shade2 = clamp_f(1.0f - (H.x + 0.5f), 0.0f, 1.0f);
      float t_s2 = mix_f(smoothstep(px, -px, d + 0.025f), 0.0f, shade2);
      C.x = mix_f(C.x, C.x * 0.1f, t_s2);
      C.y = mix_f(C.y, C.y * 0.1f, t_s2);
      C.z = mix_f(C.z, C.z * 0.1f, t_s2);

      // Base tile distance
      float b = vec2_length(pp) - s3;
      float t_val = 1e5f, g = 1e5f;
      float tg = 1.0f;

      hs = fract(hs * 53.71f);

      // Alternate tile patterns
      if (hs > 0.95f) {
        vec2 p4 = mat2_mul(r3_cos, r3_sin, p);
        vec2 p5 = mat2_mul(r2_cos, r2_sin, p);

        b = vec2_length(vec2_new(p.x, fabsf(p.y) - 0.5f));
        g = fabsf(p5.x);
        t_val = fabsf(p4.x);
        tg = 0.0f;
      } else if (hs > 0.65f) {
        b = fabsf(p.x);
        g = fminf(vec2_length(p1) - s3, vec2_length(vec2_new(p1.x + 1.155f, p1.y)) - s3);
        tg = 0.0f;
      } else if (hs < 0.15f) {
        vec2 p4 = mat2_mul(r3_cos, r3_sin, p);
        vec2 p5 = mat2_mul(r2_cos, r2_sin, p);

        t_val = fabsf(p.x);
        b = fabsf(p5.x);
        g = fabsf(p4.x);
        tg = 0.0f;
      } else if (hs < 0.22f) {
        b = vec2_length(vec2_new(p.x, fabsf(p.y) - 0.5f));
        g = fminf(vec2_length(p1) - s3, vec2_length(vec2_new(p1.x + 1.155f, p1.y)) - s3);
      }

      clr = vec3_new(0.420f, 0.278f, 0.043f);
      trm = vec3_new(0.0f, 0.0f, 0.0f);

      // Draw segments
      draw(t_val, px, &C);
      draw(g, px, &C);
      draw(b, px, &C);

      // Solid balls
      if (tg > 0.0f) {
        float v = vec2_length(p) - 0.25f;

        float t1 = smoothstep(0.1f + px, -px, v - 0.01f);
        C.x = mix_f(C.x, C.x * 0.25f, t1);
        C.y = mix_f(C.y, C.y * 0.25f, t1);
        C.z = mix_f(C.z, C.z * 0.25f, t1);

        float t2 = smoothstep(px, -px, v);
        C.x = mix_f(C.x, clr.x, t2);
        C.y = mix_f(C.y, clr.y, t2);
        C.z = mix_f(C.z, clr.z, t2);

        float t3 = smoothstep(0.01f + px, -px, v + 0.1f);
        C.x = mix_f(C.x, clamp_f(C.x + 0.2f, C.x, 0.95f), t3);
        C.y = mix_f(C.y, clamp_f(C.y + 0.2f, C.y, 0.95f), t3);
        C.z = mix_f(C.z, clamp_f(C.z + 0.2f, C.z, 0.95f), t3);

        float t4 = smoothstep(px, -px, fabsf(v) - ln);
        C.x = mix_f(C.x, trm.x, t4);
        C.y = mix_f(C.y, trm.y, t4);
        C.z = mix_f(C.z, trm.z, t4);
      }

      // Gamma correction
      C.x = powf(C.x, 0.4545f);
      C.y = powf(C.y, 0.4545f);
      C.z = powf(C.z, 0.4545f);

      return C;
    C
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: 'Hexagon X5')

puts 'Hexagon X5 - Hexagonal Flow Pattern'
puts 'Original: https://www.shadertoy.com/view/4cVfWG'
puts 'License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0'
puts 'https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en'
puts 'Move mouse to pan'
puts "Press 'q' or Escape to quit"

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true
mouse_x = WIDTH / 2.0
mouse_y = HEIGHT / 2.0

buffer = "\x00" * (WIDTH * HEIGHT * 4)

while running && !window.should_close?
  time = Time.now - start_time

  shader.render(buffer, WIDTH, HEIGHT, { time: time, mouse: [mouse_x, mouse_y] })

  window.set_pixels(buffer)

  events = window.poll_events_raw
  events.each do |e|
    case e[:type]
    when :key_press
      running = false if [12, 'q'].include?(e[:key])
    when :mouse_move
      mouse_x = e[:x].to_f
      mouse_y = e[:y].to_f
    end
  end

  frame_count += 1
  now = Time.now
  next unless now - last_fps_time >= 1.0

  fps = frame_count / (now - last_fps_time)
  puts "FPS: #{fps.round(1)}"
  frame_count = 0
  last_fps_time = now
end

window.close
