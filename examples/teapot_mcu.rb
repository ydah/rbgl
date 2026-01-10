# frozen_string_literal: true

# Teapot - Raymarched Bezier Curves (Metal Compute Shader)
# Original: https://www.shadertoy.com/view/MdKcDw
# GPU-accelerated version
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0
# https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rbgl'
require 'rlsl'

WIDTH = 640
HEIGHT = 480

# Generate control points as Metal constants
def generate_teapot_constants
  body = [
    [0.0, 0.0], [0.64, 0.0], [0.64, 0.03],
    [0.8, 0.12], [0.8, 0.3], [0.8, 0.48],
    [0.64, 0.9], [0.6, 0.93], [0.56, 0.9],
    [0.56, 0.96], [0.12, 1.02], [0.0, 1.05],
    [0.16, 1.14], [0.2, 1.2], [0.0, 1.2]
  ]
  spout = [
    [1.16, 0.96], [1.04, 0.9], [1.0, 0.72],
    [0.92, 0.48], [0.72, 0.42]
  ]
  handle = [
    [-0.6, 0.78], [-1.16, 0.84], [-1.16, 0.63],
    [-1.2, 0.42], [-0.72, 0.24]
  ]

  body_init = body.map.with_index { |(x, y), i| "constant float2 A#{i} = float2(#{x}f, #{y}f);" }.join("\n")
  spout_init = spout.map.with_index { |(x, y), i| "constant float2 T1_#{i} = float2(#{x}f, #{y}f);" }.join("\n")
  handle_init = handle.map.with_index { |(x, y), i| "constant float2 T2_#{i} = float2(#{x}f, #{y}f);" }.join("\n")

  <<~MSL
    // Control points as constants
    #{body_init}
    #{spout_init}
    #{handle_init}

    // Pre-computed: normalize(float3(1.0f, 0.72f, 1.0f))
    constant float3 L = float3(0.6302f, 0.4537f, 0.6302f);
    constant float3 Y_VEC = float3(0.0f, 1.0f, 0.0f);

    // Material properties
    constant float2 lo = float2(0.450f, 0.048f);
    constant float2 alpha_m = float2(0.045f, 0.068f);
    constant float3 Scale = float3(1.0f, 20.0f, 10.0f);
    constant float3 surfaceColor = float3(0.45f, 0.54f, 1.0f);
    constant float ONE_OVER_PI = 0.31830988618f;
  MSL
end

shader = RLSL.define_metal(:teapot_metal) do
  uniforms do
    float :time
    vec2 :mouse
  end

  helpers(:c) do
    teapot_constants = generate_teapot_constants

    <<~MSL
      #{teapot_constants}

      // Cross product 2D
      #define U(a,b) ((a).x*(b).y-(b).x*(a).y)

      // Distance to quadratic Bezier curve
      float2 bezier_dist(float2 m, float2 n, float2 o, float3 p) {
        float2 q = float2(p.x, p.y);
        m = m - q;
        n = n - q;
        o = o - q;

        float x = U(m, o);
        float y = 2.0f * U(n, m);
        float z = 2.0f * U(o, n);

        float2 i = o - m;
        float2 j = o - n;
        float2 k = n - m;

        float2 s = float2(
          2.0f * (x * i.x + y * j.x + z * k.x),
          2.0f * (x * i.y + y * j.y + z * k.y)
        );

        float dot_s = dot(s, s);
        if (dot_s < 1e-10f) dot_s = 1e-10f;

        float2 r = float2(
          m.x + (y * z - x * x) * s.y / dot_s,
          m.y - (y * z - x * x) * s.x / dot_s
        );

        float denom = x + x + y + z;
        if (abs(denom) < 1e-10f) denom = 1e-10f;

        float t = clamp((U(r, i) + 2.0f * U(k, r)) / denom, 0.0f, 1.0f);

        float2 jk = j - k;
        r.x = m.x + t * (k.x + k.x + t * jk.x);
        r.y = m.y + t * (k.y + k.y + t * jk.y);

        return float2(sqrt(dot(r, r) + p.z * p.z), t);
      }

      // Smooth minimum for blending
      float smin(float a, float b, float k) {
        float h = clamp(0.5f + 0.5f * (b - a) / k, 0.0f, 1.0f);
        return mix(b, a, h) - k * h * (1.0f - h);
      }

      // Scene distance function
      float scene_dist(float3 p) {
        // Spout
        float2 h = bezier_dist(T1_2, T1_3, T1_4, p);

        // Handle
        float handle_d = min(
          bezier_dist(T2_0, T2_1, T2_2, p).x,
          bezier_dist(T2_2, T2_3, T2_4, p).x
        ) - 0.06f;

        // Spout
        float spout_hole = abs(bezier_dist(T1_0, T1_1, T1_2, p).x - 0.07f) - 0.01f;
        float spout_body = h.x * (1.0f - 0.75f * h.y) - 0.08f;
        float spout_d = max(p.y - 0.9f, min(spout_hole, spout_body));

        float b = min(handle_d, spout_d);

        // Body (rotation symmetry)
        float r_xz = sqrt(p.x * p.x + p.z * p.z);
        float3 qq = float3(r_xz, p.y, 0.0f);

        float a = 99.0f;
        a = min(a, (bezier_dist(A0, A1, A2, qq).x - 0.015f) * 0.7f);
        a = min(a, (bezier_dist(A2, A3, A4, qq).x - 0.015f) * 0.7f);
        a = min(a, (bezier_dist(A4, A5, A6, qq).x - 0.015f) * 0.7f);
        a = min(a, (bezier_dist(A6, A7, A8, qq).x - 0.015f) * 0.7f);
        a = min(a, (bezier_dist(A8, A9, A10, qq).x - 0.015f) * 0.7f);
        a = min(a, (bezier_dist(A10, A11, A12, qq).x - 0.015f) * 0.7f);
        a = min(a, (bezier_dist(A12, A13, A14, qq).x - 0.015f) * 0.7f);

        return smin(a, b, 0.02f);
      }

      // Normal calculation
      float3 calc_normal(float3 p, float3 ray, float t, float res_x) {
        float eps = 0.4f * t / res_x;

        float d0 = scene_dist(p);
        float dx = scene_dist(p + float3(eps, 0.0f, 0.0f)) - d0;
        float dy = scene_dist(p + float3(0.0f, eps, 0.0f)) - d0;
        float dz = scene_dist(p + float3(0.0f, 0.0f, eps)) - d0;

        float3 grad = float3(dx, dy, dz);

        float d = dot(grad, ray);
        if (d > 0.0f) {
          grad = grad - ray * d;
        }

        return normalize(grad);
      }

      // Build orthonormal basis
      void basis(float3 n, thread float3* xp, thread float3* yp) {
        float a = n.y / (1.0f + n.z + 1e-10f);
        float b = n.y * a;
        float c = -n.x * a;
        *xp = float3(n.z + b, c, -n.x);
        *yp = float3(c, 1.0f - b, -n.y);
      }

      // BRDF
      float3 compute_brdf(float3 n, float3 l, float3 h, float3 r, float3 tang, float3 binorm) {
        float e1 = dot(h, tang) / alpha_m.x;
        float e2 = dot(h, binorm) / alpha_m.y;
        float hn = dot(h, n);
        float E = -2.0f * ((e1 * e1 + e2 * e2) / (1.0f + hn));

        float cos_i = dot(n, l);
        float cos_r = dot(n, r);
        float denom = sqrt(abs(cos_i * cos_r) + 1e-6f);

        float brdf = lo.x * ONE_OVER_PI +
                     lo.y * (1.0f / denom) * (1.0f / (4.0f * 3.14159265f * alpha_m.x * alpha_m.y)) * exp(E);

        float intensity = Scale.x * lo.x * ONE_OVER_PI +
                          Scale.y * lo.y * cos_i * brdf +
                          Scale.z * hn * lo.y;

        return surfaceColor * intensity;
      }

      // HSV to RGB
      float3 hsv2rgb_smooth(float h, float s, float v) {
        float3 rgb = float3(
          abs(fmod(h * 6.0f + 0.0f, 6.0f) - 3.0f) - 1.0f,
          abs(fmod(h * 6.0f + 4.0f, 6.0f) - 3.0f) - 1.0f,
          abs(fmod(h * 6.0f + 2.0f, 6.0f) - 3.0f) - 1.0f
        );
        rgb = clamp(rgb, 0.0f, 1.0f);
        rgb = rgb * rgb * (3.0f - 2.0f * rgb);

        return float3(
          v * (1.0f + s * (rgb.x - 1.0f)),
          v * (1.0f + s * (rgb.y - 1.0f)),
          v * (1.0f + s * (rgb.z - 1.0f))
        );
      }
    MSL
  end

  fragment do
    <<~MSL
      float2 q = float2(uv.x * resolution.y / resolution.x, uv.y);
      float2 p = q * 2.0f - float2(1.0f, 1.0f);
      p.x *= resolution.x / resolution.y;

      // Camera with mouse control
      float mouse_x = u.mouse.x / resolution.x;
      float mouse_y = u.mouse.y / resolution.y;
      float cam_angle = 5.0f + 0.2f * u.time + 4.0f * mouse_x;

      float3 origin = float3(cos(cam_angle), 0.7f - mouse_y, sin(cam_angle)) * 3.5f;
      float3 w = normalize(Y_VEC * 0.4f - origin);
      float3 cam_u = normalize(cross(w, Y_VEC));
      float3 cam_v = cross(cam_u, w);

      float3 ray = normalize(cam_u * p.x + cam_v * p.y + w + w);

      // Raymarching
      float t = 0.0f;
      float h = 0.1f;
      for (int i = 0; i < 48; i++) {
        if (h < 0.0001f || t > 4.7f) break;
        h = scene_dist(origin + ray * t);
        t += h;
      }

      // Background
      float3 color = mix(
        hsv2rgb_smooth(0.5f + u.time * 0.02f, 0.35f, 0.4f),
        hsv2rgb_smooth(-0.5f + u.time * 0.02f, 0.35f, 0.7f),
        q.y
      );

      if (h < 0.001f) {
        float3 hit = origin + ray * t;
        float3 n = calc_normal(hit, ray, t, resolution.x);

        float3 V = normalize(origin - hit);
        float3 H = normalize(L + V);
        float3 R = normalize(n * 2.0f * dot(n, L) - L);

        float3 tang, binorm;
        basis(n, &tang, &binorm);

        color = compute_brdf(n, L, H, R, tang, binorm);

        // Shadows
        float shadow = 1.0f;
        float j = 0.0f;
        for (int i = 0; i < 20; i++) {
          j += 0.02f;
          shadow = min(shadow, scene_dist(hit + L * j) / j);
        }
      }

      // Vignette
      float vignette = pow(16.0f * q.x * q.y * (1.0f - q.x) * (1.0f - q.y), 0.16f);
      color = color * vignette;

      return color;
    MSL
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: 'Teapot Metal (GPU)')

puts 'Teapot Metal - GPU Compute Shader'
puts 'Original: https://www.shadertoy.com/view/MdKcDw'
puts 'License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0'
puts 'https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en'
puts 'Move mouse to rotate camera'
puts "Press 'q' or Escape to quit"

# Check Metal availability
unless window.metal_available?
  puts 'Metal compute is NOT available'
  exit 1
end

puts 'Metal compute is available!'

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true
mouse_x = 0.0
mouse_y = 0.0

while running && !window.should_close?
  time = Time.now - start_time

  begin
    shader.render_metal(window.native_handle, WIDTH, HEIGHT, { time: time, mouse: [mouse_x, mouse_y] })
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(10).join("\n")
    running = false
    break
  end

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
