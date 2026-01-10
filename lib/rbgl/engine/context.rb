# frozen_string_literal: true

module RBGL
  module Engine
    class Context
      attr_reader :framebuffer, :rasterizer

      def initialize(width:, height:)
        @framebuffer = Framebuffer.new(width, height)
        @rasterizer = Rasterizer.new(@framebuffer)
        @pipeline = nil
        @uniforms = Uniforms.new
        @vertex_buffer = nil
        @index_buffer = nil
      end

      def bind_pipeline(pipeline)
        @pipeline = pipeline
      end

      def bind_vertex_buffer(buffer)
        @vertex_buffer = buffer
      end

      def bind_index_buffer(buffer)
        @index_buffer = buffer
      end

      def set_uniform(name, value)
        @uniforms[name] = value
      end

      def set_uniforms(hash)
        hash.each { |k, v| @uniforms[k] = v }
      end

      def clear(color: Larb::Color.black, depth: Float::INFINITY)
        @framebuffer.clear(color: color, depth: depth)
      end

      def draw_arrays(mode, first, count)
        raise 'No pipeline bound' unless @pipeline
        raise 'No vertex buffer bound' unless @vertex_buffer

        vertices = (first...(first + count)).map { |i| process_vertex(i) }

        case mode
        when :triangles
          (0...vertices.size).step(3) do |i|
            draw_triangle(vertices[i], vertices[i + 1], vertices[i + 2])
          end
        when :lines
          (0...vertices.size).step(2) do |i|
            draw_line(vertices[i], vertices[i + 1])
          end
        when :points
          vertices.each { |v| draw_point(v) }
        when :triangle_strip
          (0...(vertices.size - 2)).each do |i|
            if i.even?
              draw_triangle(vertices[i], vertices[i + 1], vertices[i + 2])
            else
              draw_triangle(vertices[i], vertices[i + 2], vertices[i + 1])
            end
          end
        when :triangle_fan
          (1...(vertices.size - 1)).each do |i|
            draw_triangle(vertices[0], vertices[i], vertices[i + 1])
          end
        end
      end

      def draw_elements(mode, count, offset = 0)
        raise 'No pipeline bound' unless @pipeline
        raise 'No vertex buffer bound' unless @vertex_buffer
        raise 'No index buffer bound' unless @index_buffer

        indices = @index_buffer.indices[offset, count]
        vertices = indices.map { |i| process_vertex(i) }

        case mode
        when :triangles
          (0...vertices.size).step(3) do |i|
            draw_triangle(vertices[i], vertices[i + 1], vertices[i + 2])
          end
        when :lines
          (0...vertices.size).step(2) do |i|
            draw_line(vertices[i], vertices[i + 1])
          end
        end
      end

      def width
        @framebuffer.width
      end

      def height
        @framebuffer.height
      end

      def aspect_ratio
        width.to_f / height
      end

      private

      def process_vertex(index)
        input = @vertex_buffer.get_vertex(index)
        input_io = ShaderIO.new
        input.each { |k, v| input_io[k] = v }

        @pipeline.vertex_shader.process(input_io, @uniforms)
      end

      def draw_triangle(v0, v1, v2)
        return unless v0 && v1 && v2
        return if clip_triangle?(v0, v1, v2)

        @rasterizer.rasterize_triangle(
          v0, v1, v2,
          @pipeline.fragment_shader,
          @uniforms,
          cull_mode: @pipeline.cull_mode
        )
      end

      def draw_line(v0, v1)
        return unless v0 && v1

        @rasterizer.rasterize_line(v0, v1, @pipeline.fragment_shader, @uniforms)
      end

      def draw_point(v)
        return unless v

        @rasterizer.rasterize_point(v, @pipeline.fragment_shader, @uniforms)
      end

      def clip_triangle?(v0, v1, v2)
        positions = [v0[:position], v1[:position], v2[:position]].map do |p|
          if p.is_a?(Larb::Vec4)
            p.perspective_divide
          else
            p
          end
        end

        positions.all? { |p| p.x < -1 } ||
          positions.all? { |p| p.x > 1 } ||
          positions.all? { |p| p.y < -1 } ||
          positions.all? { |p| p.y > 1 } ||
          positions.all? { |p| p.z < -1 } ||
          positions.all? { |p| p.z > 1 }
      end
    end
  end
end
