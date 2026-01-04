# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rbgl"

puts "Creating window..."

window = RBGL::GUI::Window.new(
  width: 320,
  height: 240,
  title: "Simple Test",
  backend: :cocoa
)

puts "Window created, starting render loop..."

frame = 0
window.run do |ctx, dt|
  frame += 1

  # Simple red background
  ctx.clear(color: Larb::Color.red)

  if frame % 60 == 0
    puts "Frame: #{frame}, FPS: #{window.fps.round(1)}"
  end

  # Exit after 5 seconds
  if frame > 300
    puts "Stopping..."
    window.stop
  end
end

puts "Done"
