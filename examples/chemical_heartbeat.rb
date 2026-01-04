# frozen_string_literal: true

# chemical heartbeat
# Original: https://www.shadertoy.com/view/lXtXD4
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0
# https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rbgl"
require "rlsl"

WIDTH = 640
HEIGHT = 480

# Define shader using pure Ruby DSL
shader = RLSL.define(:chemical_heartbeat) do
  uniforms do
    float :time
    float :camera_x
    float :camera_y
  end

  fragment do |frag_coord, resolution, u|
    uv = frag_coord / resolution.y

    # Constants
    inv_hex_size = 50.0
    sqrt3_div3 = 0.5773502691896257
    one_div3 = 0.3333333333333333
    two_div3 = 0.6666666666666666
    inv_warp_grid = 5.0
    warp_clamp = 1.7
    warp_scale = 4.4
    warp_amplitude = 0.015
    warp_speed = 1.5
    time_dilation = 0.2

    # Colors
    color_a = vec3(58.0 / 255.0, 1.0 / 255.0, 92.0 / 255.0)
    color_b = vec3(201.0 / 255.0, 100.0 / 255.0, 128.0 / 255.0)
    color_c = vec3(59.0 / 255.0, 206.0 / 255.0, 172.0 / 255.0)
    color_d = vec3(17.0 / 255.0, 0.0 / 255.0, 28.0 / 255.0)

    # Apply camera offset
    base_ux = uv.x - 0.5 + u.camera_x
    base_uy = uv.y - 0.5 + u.camera_y

    # Zoomy warp
    pos_x = base_ux * inv_warp_grid
    pos_y = base_uy * inv_warp_grid
    ax = floor(pos_x)
    ay = floor(pos_y)

    hash_a = hash21(vec2(ax, ay))
    hash_b = hash21(vec2(ax + 1.0, ay))
    hash_c = hash21(vec2(ax, ay + 1.0))
    hash_d = hash21(vec2(ax + 1.0, ay + 1.0))

    diff_x = pos_x - ax
    diff_y = pos_y - ay

    warp = hash_a + (hash_b - hash_a) * diff_x
    warp = warp + ((hash_c + (hash_d - hash_c) * diff_x) - warp) * diff_y
    warp = warp + u.time * warp_speed

    smoothed = (1.0 + cos(warp * TAU)) * 0.5
    clamped = smoothed * warp_scale - warp_clamp
    clamped = clamp(clamped, 0.0, 1.0)

    ux = base_ux + cos(clamped) * warp_amplitude
    uy = base_uy + sin(clamped) * warp_amplitude

    # Axial from pixel
    axial_q = (sqrt3_div3 * ux - one_div3 * uy) * inv_hex_size
    axial_r = two_div3 * uy * inv_hex_size
    axial_s = 0.0 - axial_q - axial_r

    # Axial round
    q = floor(axial_q)
    r = floor(axial_r)
    s = floor(axial_s)

    q_diff = abs(q - axial_q)
    r_diff = abs(r - axial_r)
    s_diff = abs(s - axial_s)

    if q_diff > r_diff && q_diff > s_diff
      q = 0.0 - r - s
    elsif r_diff > s_diff
      r = 0.0 - q - s
    end

    # Hash for hex cell
    hash_val = hash21(vec2(q, r))

    # Animated color value
    value = fract(hash_val + u.time * time_dilation)
    value = smoothstep(0.0, 1.0, value)
    value = (1.0 + cos(value * TAU)) * 0.5

    # Color mixing
    ab = mix(color_a, color_b, value)
    bc = mix(color_b, color_c, value)
    cd = mix(color_c, color_d, value)

    left = mix(ab, bc, value)
    right = mix(bc, cd, value)

    mix(left, right, value)
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: "Chemical Heartbeat")

puts "Chemical Heartbeat"
puts "Original: https://www.shadertoy.com/view/lXtXD4"
puts "License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0"
puts "https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en"
puts "Press 'q' or Escape to quit"

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true

buffer = "\x00" * (WIDTH * HEIGHT * 4)

while running && !window.should_close?
  time = Time.now - start_time

  # Camera movement
  circle_value = time * 0.1
  wave_value = time * 0.33
  radius = 1.0 + Math.cos(wave_value) * 0.25
  camera_x = Math.cos(circle_value) * radius
  camera_y = Math.sin(circle_value) * radius

  # Render using compiled shader
  shader.render(buffer, WIDTH, HEIGHT, {
    time: time,
    camera_x: camera_x,
    camera_y: camera_y
  })

  window.set_pixels(buffer)

  events = window.poll_events_raw
  events.each do |e|
    if e[:type] == :key_press && (e[:key] == 12 || e[:key] == "q")
      running = false
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
