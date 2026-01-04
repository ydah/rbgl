# RBGL

RuBy Graphics Library - A pure Ruby graphics library with software rendering engine and cross-platform GUI support.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rbgl'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install rbgl
```

## Requirements

- Ruby 3.1.0 or higher

## Usage

### Basic Window

```ruby
require "rbgl"

window = RBGL::GUI::Window.new(width: 800, height: 600, title: "Hello RBGL")

window.run do |context, delta_time|
  context.clear(color: Larb::Color.new(0.1, 0.1, 0.1, 1.0))
end
```

### Rendering with Pipeline

```ruby
require "rbgl"

# Create a window with rendering context
window = RBGL::GUI::Window.new(width: 800, height: 600, title: "Triangle")

# Define vertex shader
vertex_shader = RBGL::Engine::Shader.new do |input, uniforms|
  { position: input[:position], color: input[:color] }
end

# Define fragment shader
fragment_shader = RBGL::Engine::Shader.new do |input, uniforms|
  input[:color]
end

# Create pipeline
pipeline = RBGL::Engine::Pipeline.new(
  vertex_shader: vertex_shader,
  fragment_shader: fragment_shader
)

# Create vertex buffer
vertices = [
  { position: Larb::Vec4.new(0.0, 0.5, 0.0, 1.0), color: Larb::Color.red },
  { position: Larb::Vec4.new(-0.5, -0.5, 0.0, 1.0), color: Larb::Color.green },
  { position: Larb::Vec4.new(0.5, -0.5, 0.0, 1.0), color: Larb::Color.blue }
]
vertex_buffer = RBGL::Engine::VertexBuffer.new(vertices)

window.run do |context, delta_time|
  context.clear
  context.bind_pipeline(pipeline)
  context.bind_vertex_buffer(vertex_buffer)
  context.draw_arrays(:triangles, 0, 3)
end
```

### Event Handling

```ruby
window.on_key do |event|
  case event.key
  when :escape
    window.stop
  end
end

window.on_mouse do |event|
  puts "Mouse: #{event.x}, #{event.y}"
end
```

### Backend Selection

RBGL automatically detects the appropriate backend for your platform:

- macOS: Cocoa (requires `metaco` gem)
- Linux: Wayland or X11 (based on environment)

To use the Cocoa backend on macOS, install the `metaco` gem:

```
$ gem install metaco
```

You can also specify a backend explicitly:

```ruby
# Use specific backend
window = RBGL::GUI::Window.new(width: 800, height: 600, backend: :x11)

# Use file backend for headless rendering
window = RBGL::GUI::Window.new(width: 800, height: 600, backend: :file, output_path: "output.png")
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
