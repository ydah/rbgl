# frozen_string_literal: true

# Teapot - Raymarched Bezier Curves (Ruby Mode)
# Original: https://www.shadertoy.com/view/MdKcDw
# Created by Sebastien Durand - 2014
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0
# https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rbgl"
require "rlsl"

WIDTH = 640
HEIGHT = 480

shader = RLSL.define(:teapot_ruby) do
  uniforms do
    float :time
    vec2 :mouse
  end

  functions do
    # Helper functions
    define :cross2d, returns: :float, params: { a: :vec2, b: :vec2 }
    define :smin, returns: :float, params: { a: :float, b: :float, k: :float }
    define :bezier_dist, returns: :vec2, params: { m: :vec2, n: :vec2, o: :vec2, p: :vec3 }
    define :scene_dist, returns: :float, params: { p: :vec3 }
    define :basis, returns: [:vec3, :vec3], params: { n: :vec3 }
    define :calc_normal, returns: :vec3, params: { p: :vec3, ray: :vec3, t: :float, res_x: :float }
    define :compute_brdf, returns: :vec3, params: { n: :vec3, l: :vec3, h: :vec3, r: :vec3, tang: :vec3, binorm: :vec3 }
    define :hsv2rgb_smooth, returns: :vec3, params: { h: :float, s: :float, v: :float }
  end

  helpers do
    # Control points - Body profile (15 points)
    A = [
      vec2(0.0, 0.0), vec2(0.64, 0.0), vec2(0.64, 0.03),
      vec2(0.8, 0.12), vec2(0.8, 0.3), vec2(0.8, 0.48),
      vec2(0.64, 0.9), vec2(0.6, 0.93), vec2(0.56, 0.9),
      vec2(0.56, 0.96), vec2(0.12, 1.02), vec2(0.0, 1.05),
      vec2(0.16, 1.14), vec2(0.2, 1.2), vec2(0.0, 1.2)
    ]

    # Control points - Spout (5 points)
    T1 = [
      vec2(1.16, 0.96), vec2(1.04, 0.9), vec2(1.0, 0.72),
      vec2(0.92, 0.48), vec2(0.72, 0.42)
    ]

    # Control points - Handle (5 points)
    T2 = [
      vec2(-0.6, 0.78), vec2(-1.16, 0.84), vec2(-1.16, 0.63),
      vec2(-1.2, 0.42), vec2(-0.72, 0.24)
    ]

    # Material properties
    LO = vec2(0.450, 0.048)
    ALPHA_M = vec2(0.045, 0.068)
    SCALE = vec3(1.0, 20.0, 10.0)
    SURFACE_COLOR = vec3(0.45, 0.54, 1.0)

    # Light direction (pre-normalized: normalize(vec3(1.0, 0.72, 1.0)))
    L = vec3(0.6286, 0.4526, 0.6286)

    # Up vector
    Y = vec3(0.0, 1.0, 0.0)

    # Constants
    ONE_OVER_PI = 0.31830988618

    # Cross product 2D
    def cross2d(a, b)
      a.x * b.y - b.x * a.y
    end

    # Smooth minimum for blending
    def smin(a, b, k)
      h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
      mix(b, a, h) - k * h * (1.0 - h)
    end

    # Distance to quadratic Bezier curve
    def bezier_dist(m, n, o, p)
      q = vec2(p.x, p.y)
      m = vec2(m.x - q.x, m.y - q.y)
      n = vec2(n.x - q.x, n.y - q.y)
      o = vec2(o.x - q.x, o.y - q.y)

      x = cross2d(m, o)
      y = 2.0 * cross2d(n, m)
      z = 2.0 * cross2d(o, n)

      i = vec2(o.x - m.x, o.y - m.y)
      j = vec2(o.x - n.x, o.y - n.y)
      k = vec2(n.x - m.x, n.y - m.y)

      s = vec2(
        2.0 * (x * i.x + y * j.x + z * k.x),
        2.0 * (x * i.y + y * j.y + z * k.y)
      )

      dot_s = s.x * s.x + s.y * s.y
      if dot_s < 0.0000000001
        dot_s = 0.0000000001
      end

      r = vec2(
        m.x + (y * z - x * x) * s.y / dot_s,
        m.y - (y * z - x * x) * s.x / dot_s
      )

      denom = x + x + y + z
      if abs(denom) < 0.0000000001
        denom = 0.0000000001
      end

      t = clamp((cross2d(r, i) + 2.0 * cross2d(k, r)) / denom, 0.0, 1.0)

      jk = vec2(j.x - k.x, j.y - k.y)
      r = vec2(
        m.x + t * (k.x + k.x + t * jk.x),
        m.y + t * (k.y + k.y + t * jk.y)
      )

      vec2(sqrt(r.x * r.x + r.y * r.y + p.z * p.z), t)
    end

    # Scene distance function
    def scene_dist(p)
      # Spout curve
      h = bezier_dist(T1[2], T1[3], T1[4], p)

      # Handle distance
      handle_d = min(
        bezier_dist(T2[0], T2[1], T2[2], p).x,
        bezier_dist(T2[2], T2[3], T2[4], p).x
      ) - 0.06

      # Spout distance
      spout_hole = abs(bezier_dist(T1[0], T1[1], T1[2], p).x - 0.07) - 0.01
      spout_body = h.x * (1.0 - 0.75 * h.y) - 0.08
      spout_d = max(p.y - 0.9, min(spout_hole, spout_body))

      b = min(handle_d, spout_d)

      # Body distance (rotation symmetry)
      r_xz = sqrt(p.x * p.x + p.z * p.z)
      qq = vec3(r_xz, p.y, 0.0)

      # Body curves (step by 2)
      a0 = bezier_dist(A[0], A[1], A[2], qq).x - 0.015
      a1 = bezier_dist(A[2], A[3], A[4], qq).x - 0.015
      a2 = bezier_dist(A[4], A[5], A[6], qq).x - 0.015
      a3 = bezier_dist(A[6], A[7], A[8], qq).x - 0.015
      a4 = bezier_dist(A[8], A[9], A[10], qq).x - 0.015
      a5 = bezier_dist(A[10], A[11], A[12], qq).x - 0.015
      a6 = bezier_dist(A[12], A[13], A[14], qq).x - 0.015

      a = min(a0, min(a1, min(a2, min(a3, min(a4, min(a5, a6)))))) * 0.7

      smin(a, b, 0.02)
    end

    # Build orthonormal basis from normal
    def basis(n)
      a = n.y / (1.0 + n.z + 0.0000000001)
      b = n.y * a
      c = 0.0 - n.x * a
      xp = vec3(n.z + b, c, 0.0 - n.x)
      yp = vec3(c, 1.0 - b, 0.0 - n.y)
      [xp, yp]
    end

    # Normal calculation
    def calc_normal(p, ray, t, res_x)
      eps = 0.4 * t / res_x

      d0 = scene_dist(p)
      dx = scene_dist(vec3(p.x + eps, p.y, p.z)) - d0
      dy = scene_dist(vec3(p.x, p.y + eps, p.z)) - d0
      dz = scene_dist(vec3(p.x, p.y, p.z + eps)) - d0

      grad = vec3(dx, dy, dz)

      # Prevent normals pointing away from camera
      d = grad.x * ray.x + grad.y * ray.y + grad.z * ray.z
      if d > 0.0
        grad = vec3(grad.x - ray.x * d, grad.y - ray.y * d, grad.z - ray.z * d)
      end

      normalize(grad)
    end

    # BRDF computation
    def compute_brdf(n, l, h, r, tang, binorm)
      e1 = (h.x * tang.x + h.y * tang.y + h.z * tang.z) / ALPHA_M.x
      e2 = (h.x * binorm.x + h.y * binorm.y + h.z * binorm.z) / ALPHA_M.y
      hn = h.x * n.x + h.y * n.y + h.z * n.z
      big_e = 0.0 - 2.0 * ((e1 * e1 + e2 * e2) / (1.0 + hn))

      cos_i = n.x * l.x + n.y * l.y + n.z * l.z
      cos_r = n.x * r.x + n.y * r.y + n.z * r.z
      denom = sqrt(abs(cos_i * cos_r) + 0.000001)

      brdf = LO.x * ONE_OVER_PI + LO.y * (1.0 / denom) * (1.0 / (4.0 * PI * ALPHA_M.x * ALPHA_M.y)) * exp(big_e)

      intensity = SCALE.x * LO.x * ONE_OVER_PI + SCALE.y * LO.y * cos_i * brdf + SCALE.z * hn * LO.y

      vec3(SURFACE_COLOR.x * intensity, SURFACE_COLOR.y * intensity, SURFACE_COLOR.z * intensity)
    end

    # HSV to RGB with cubic smoothing
    def hsv2rgb_smooth(h, s, v)
      rx = abs(mod(h * 6.0 + 0.0, 6.0) - 3.0) - 1.0
      gx = abs(mod(h * 6.0 + 4.0, 6.0) - 3.0) - 1.0
      bx = abs(mod(h * 6.0 + 2.0, 6.0) - 3.0) - 1.0

      rx = clamp(rx, 0.0, 1.0)
      gx = clamp(gx, 0.0, 1.0)
      bx = clamp(bx, 0.0, 1.0)

      # Cubic smoothing
      rx = rx * rx * (3.0 - 2.0 * rx)
      gx = gx * gx * (3.0 - 2.0 * gx)
      bx = bx * bx * (3.0 - 2.0 * bx)

      vec3(
        v * (1.0 + s * (rx - 1.0)),
        v * (1.0 + s * (gx - 1.0)),
        v * (1.0 + s * (bx - 1.0))
      )
    end
  end

  fragment do |frag_coord, resolution, u|
    # UV coordinates (aspect-ratio preserving, same as Metal)
    uv = vec2(frag_coord.x / resolution.y, frag_coord.y / resolution.y)

    # Normalized screen coordinates
    q = vec2(uv.x * resolution.y / resolution.x, uv.y)

    # Centered coordinates for camera ray
    p = vec2(q.x * 2.0 - 1.0, q.y * 2.0 - 1.0)
    p = vec2(p.x * resolution.x / resolution.y, p.y)

    # Camera with mouse control
    mouse_x = u.mouse.x / resolution.x
    mouse_y = u.mouse.y / resolution.y
    cam_angle = 5.0 + 0.2 * u.time + 4.0 * mouse_x

    origin = vec3(cos(cam_angle) * 3.5, (0.7 - mouse_y) * 3.5, sin(cam_angle) * 3.5)
    target = vec3(Y.x * 0.4, Y.y * 0.4, Y.z * 0.4)
    w = normalize(vec3(target.x - origin.x, target.y - origin.y, target.z - origin.z))

    # Camera basis
    cam_u = normalize(vec3(
      w.y * Y.z - w.z * Y.y,
      w.z * Y.x - w.x * Y.z,
      w.x * Y.y - w.y * Y.x
    ))
    cam_v = vec3(
      cam_u.y * w.z - cam_u.z * w.y,
      cam_u.z * w.x - cam_u.x * w.z,
      cam_u.x * w.y - cam_u.y * w.x
    )

    ray = normalize(vec3(
      cam_u.x * p.x + cam_v.x * p.y + w.x * 2.0,
      cam_u.y * p.x + cam_v.y * p.y + w.y * 2.0,
      cam_u.z * p.x + cam_v.z * p.y + w.z * 2.0
    ))

    # Raymarching
    t = 0.0
    h = 0.1
    i = 0.0
    while i < 48.0 && h > 0.0001 && t < 4.7
      pos = vec3(origin.x + ray.x * t, origin.y + ray.y * t, origin.z + ray.z * t)
      h = scene_dist(pos)
      t = t + h
      i = i + 1.0
    end

    # Background gradient
    color = mix(
      hsv2rgb_smooth(0.5 + u.time * 0.02, 0.35, 0.4),
      hsv2rgb_smooth(0.0 - 0.5 + u.time * 0.02, 0.35, 0.7),
      q.y
    )

    if h < 0.001
      hit = vec3(origin.x + ray.x * t, origin.y + ray.y * t, origin.z + ray.z * t)
      n = calc_normal(hit, ray, t, resolution.x)

      big_v = normalize(vec3(origin.x - hit.x, origin.y - hit.y, origin.z - hit.z))
      big_h = normalize(vec3(L.x + big_v.x, L.y + big_v.y, L.z + big_v.z))
      dot_nl = n.x * L.x + n.y * L.y + n.z * L.z
      big_r = normalize(vec3(
        n.x * 2.0 * dot_nl - L.x,
        n.y * 2.0 * dot_nl - L.y,
        n.z * 2.0 * dot_nl - L.z
      ))

      tang, binorm = basis(n)
      color = compute_brdf(n, L, big_h, big_r, tang, binorm)
    end

    # Vignette
    vignette = pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.16)
    vec3(color.x * vignette, color.y * vignette, color.z * vignette)
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: "Teapot Ruby (Raymarched Bezier)")

puts "Teapot - Raymarched Bezier Curves (Ruby Mode)"
puts "Original: https://www.shadertoy.com/view/MdKcDw"
puts "License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0"
puts "https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en"
puts "Move mouse to rotate camera"
puts "Press 'q' or Escape to quit"

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true
mouse_x = 0.0
mouse_y = 0.0

buffer = "\x00" * (WIDTH * HEIGHT * 4)

while running && !window.should_close?
  time = Time.now - start_time

  shader.render(buffer, WIDTH, HEIGHT, { time: time, mouse: [mouse_x, mouse_y] })

  window.set_pixels(buffer)

  events = window.poll_events_raw
  events.each do |e|
    case e[:type]
    when :key_press
      running = false if e[:key] == 12 || e[:key] == "q"
    when :mouse_move
      mouse_x = e[:x].to_f
      mouse_y = e[:y].to_f
    end
  end

  frame_count += 1
  now = Time.now
  if now - last_fps_time >= 1.0
    fps = frame_count / (now - last_fps_time)
    puts "FPS: #{fps.round(1)}"
    frame_count = 0
    last_fps_time = now
  end
end

window.close
