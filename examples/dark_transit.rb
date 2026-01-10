# frozen_string_literal: true

# Dark Transit
# Original: https://www.shadertoy.com/view/WcdczB
# 28 steps raymarching tunnel
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0
# https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rbgl'
require 'rlsl'

WIDTH = 640
HEIGHT = 480

shader = RLSL.define(:dark_transit) do
  uniforms do
    float :time
  end

  # Register helper function signatures for Ruby mode
  functions do
    define :get_t, returns: :float, params: { time: :float }
    define :path_point, returns: :vec3, params: { z: :float }
    define :noise_a, returns: :float, params: { f: :float, h: :float, k: :float, p: :vec3 }
    define :cross_prod, returns: :vec3, params: { a: :vec3, b: :vec3 }
    define :mat3_mul, returns: :vec3, params: { c0: :vec3, c1: :vec3, c2: :vec3, v: :vec3 }
  end

  helpers do
    def get_t(time)
      (time * 4.0) + 5.0 + (5.0 * sin(time * 0.3))
    end

    def path_point(z)
      vec3(12.0 * cos(z * 0.1), 12.0 * cos(z * 0.12), z)
    end

    def noise_a(f, h, k, p)
      abs(h * (sin(f * p.x * k) + sin(f * p.y * k) + sin(f * p.z * k))) / k
    end

    def cross_prod(a, b)
      vec3(
        (a.y * b.z) - (a.z * b.y),
        (a.z * b.x) - (a.x * b.z),
        (a.x * b.y) - (a.y * b.x)
      )
    end

    def mat3_mul(c0, c1, c2, v)
      vec3(
        (c0.x * v.x) + (c1.x * v.y) + (c2.x * v.z),
        (c0.y * v.x) + (c1.y * v.y) + (c2.y * v.z),
        (c0.z * v.x) + (c1.z * v.y) + (c2.z * v.z)
      )
    end
  end

  fragment do |frag_coord, resolution, u|
    i_time = u.time
    t_val = get_t(i_time)

    # Scaled coords
    screen_uv = vec2(
      (frag_coord.x - (resolution.x * 0.5)) / resolution.y,
      (frag_coord.y - (resolution.y * 0.5)) / resolution.y
    )

    # Cinema bars
    if abs(screen_uv.y) > 0.375
      vec3(0.0, 0.0, 0.0)
    else
      # Setup variables
      s = 0.0
      i = 0.0
      d = 0.0
      c = vec3(0.0, 0.0, 0.0)

      # Camera path
      p = path_point(t_val)
      z_dir = normalize(path_point(t_val + 4.0) - p)
      x_dir = normalize(vec3(z_dir.z, 0.0, 0.0 - z_dir.x))

      # View matrix
      neg_x = vec3(0.0 - x_dir.x, 0.0 - x_dir.y, 0.0 - x_dir.z)
      cross_xz = cross_prod(x_dir, z_dir)
      ray_d = mat3_mul(neg_x, cross_xz, z_dir, vec3(screen_uv.x, screen_uv.y, 1.0))

      # Raymarching loop
      while i < 28.0 && d < 30.0
        i += 1.0
        p += (ray_d * s)
        x_dir = path_point(p.z)
        t = sin(i_time)

        # Orb position
        orb = vec3(x_dir.x + t, x_dir.y + (t * 2.0), 6.0 + t_val + (t * 2.0))
        e = length(p - orb) - 0.01

        # Tunnel distance
        px_offset = x_dir.x + 6.0
        d1 = length(vec2(p.x - px_offset, p.y - px_offset))
        d2 = length(vec2(p.x - x_dir.x, p.y - x_dir.y))

        s = (cos(p.z * 0.6) * 2.0) + 4.0 - min(d1, d2) + noise_a(4.0, 0.25, 0.1, p) + noise_a(8.0, 0.22, 2.0, p)
        s = min(e, 0.01 + (0.25 * abs(s)))
        d += s

        # Accumulate color
        inv_s = 1.0 / s
        inv_e = 10.0 / max(e, 0.6)
        c = vec3(c.x + inv_s + inv_e, c.y + inv_s + (inv_e * 2.0), c.z + inv_s + (inv_e * 5.0))
      end

      # Output color
      vec3(c.x * c.x / 1_000_000.0, c.y * c.y / 1_000_000.0, c.z * c.z / 1_000_000.0)
    end
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: 'Dark Transit')

puts 'Dark Transit'
puts 'Original: https://www.shadertoy.com/view/WcdczB'
puts 'License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0'
puts 'https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en'
puts "Press 'q' or Escape to quit"

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true

buffer = "\x00" * (WIDTH * HEIGHT * 4)

while running && !window.should_close?
  time = Time.now - start_time

  shader.render(buffer, WIDTH, HEIGHT, { time: time })

  window.set_pixels(buffer)

  events = window.poll_events_raw
  events.each do |e|
    case e[:type]
    when :key_press
      running = false if [12, 'q'].include?(e[:key])
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
