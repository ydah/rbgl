# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rbgl"

include Larb
include RBGL::Engine

ctx = Context.new(width: 320, height: 240)

pipeline = Pipeline.create do
  vertex do |input, _uniforms, output|
    output.position = input.position.to_vec4
    output.color = input.color
  end

  fragment do |input, _uniforms, output|
    output.color = input.color
  end
end

layout = VertexLayout.position_color
vertices = VertexBuffer.from_array(layout, [
  { position: Vec3[0.0, 0.5, 0.0], color: Color.red },
  { position: Vec3[-0.5, -0.5, 0.0], color: Color.green },
  { position: Vec3[0.5, -0.5, 0.0], color: Color.blue }
])

ctx.clear(color: Color.from_hex("#1a1a2e"))
ctx.bind_pipeline(pipeline)
ctx.bind_vertex_buffer(vertices)
ctx.draw_arrays(:triangles, 0, 3)

File.write("hello_triangle.ppm", ctx.framebuffer.to_ppm)
puts "Rendered to hello_triangle.ppm"
