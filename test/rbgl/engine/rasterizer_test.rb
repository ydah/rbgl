# frozen_string_literal: true

require_relative '../../test_helper'

class RasterizerTest < Test::Unit::TestCase
  setup do
    @fb = RBGL::Engine::Framebuffer.new(100, 100)
    @rasterizer = RBGL::Engine::Rasterizer.new(@fb)
    @fragment_shader = RBGL::Engine::FragmentShader.new do |_input, _uniforms, output|
      output.color = Larb::Color.new(1, 0, 0, 1)
    end
    @uniforms = RBGL::Engine::Uniforms.new
  end

  test 'initializes with framebuffer and viewport' do
    assert_equal({ x: 0, y: 0, width: 100, height: 100 }, @rasterizer.viewport)
  end

  test 'viewport can be changed' do
    @rasterizer.viewport = { x: 10, y: 10, width: 80, height: 80 }
    assert_equal 10, @rasterizer.viewport[:x]
  end

  test 'rasterize_triangle draws triangle' do
    v0 = create_vertex(0.0, 0.5, 0.0)
    v1 = create_vertex(-0.5, -0.5, 0.0)
    v2 = create_vertex(0.5, -0.5, 0.0)

    @rasterizer.rasterize_triangle(v0, v1, v2, @fragment_shader, @uniforms)

    center_color = @fb.get_pixel(50, 50)
    assert_equal 1.0, center_color.r
  end

  test 'rasterize_triangle respects back face culling' do
    v0 = create_vertex(0.0, 0.5, 0.0)
    v1 = create_vertex(0.5, -0.5, 0.0)
    v2 = create_vertex(-0.5, -0.5, 0.0)

    @rasterizer.rasterize_triangle(v0, v1, v2, @fragment_shader, @uniforms, cull_mode: :back)

    center_color = @fb.get_pixel(50, 50)
    assert_equal 0.0, center_color.r
  end

  test 'rasterize_triangle respects front face culling' do
    v0 = create_vertex(0.0, 0.5, 0.0)
    v1 = create_vertex(-0.5, -0.5, 0.0)
    v2 = create_vertex(0.5, -0.5, 0.0)

    @rasterizer.rasterize_triangle(v0, v1, v2, @fragment_shader, @uniforms, cull_mode: :front)

    center_color = @fb.get_pixel(50, 50)
    assert_equal 0.0, center_color.r
  end

  test 'rasterize_triangle with no culling' do
    v0 = create_vertex(0.0, 0.5, 0.0)
    v1 = create_vertex(0.5, -0.5, 0.0)
    v2 = create_vertex(-0.5, -0.5, 0.0)

    @rasterizer.rasterize_triangle(v0, v1, v2, @fragment_shader, @uniforms, cull_mode: :none)

    center_color = @fb.get_pixel(50, 50)
    assert_equal 1.0, center_color.r
  end

  test 'rasterize_triangle skips degenerate triangles' do
    v0 = create_vertex(0.0, 0.0, 0.0)
    v1 = create_vertex(0.0, 0.0, 0.0)
    v2 = create_vertex(0.0, 0.0, 0.0)

    @rasterizer.rasterize_triangle(v0, v1, v2, @fragment_shader, @uniforms)
  end

  test 'rasterize_line draws line' do
    v0 = create_vertex(-0.5, 0.0, 0.0)
    v1 = create_vertex(0.5, 0.0, 0.0)

    @rasterizer.rasterize_line(v0, v1, @fragment_shader, @uniforms)

    middle_color = @fb.get_pixel(50, 50)
    assert_equal 1.0, middle_color.r
  end

  test 'rasterize_point draws point' do
    v = create_vertex(0.0, 0.0, 0.0)

    @rasterizer.rasterize_point(v, @fragment_shader, @uniforms)

    center_color = @fb.get_pixel(50, 50)
    assert_equal 1.0, center_color.r
  end

  test 'rasterize_point with size draws larger point' do
    v = create_vertex(0.0, 0.0, 0.0)

    @rasterizer.rasterize_point(v, @fragment_shader, @uniforms, size: 5)
  end

  private

  def create_vertex(x, y, z)
    io = RBGL::Engine::ShaderIO.new
    io[:position] = Larb::Vec4.new(x, y, z, 1.0)
    io[:color] = Larb::Color.new(1, 1, 1, 1)
    io
  end
end
