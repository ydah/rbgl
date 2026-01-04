# frozen_string_literal: true

module RBGL
  module Engine
    class VertexAttribute
      attr_reader :name, :size, :offset

      def initialize(name, size, offset = 0)
        @name = name.to_sym
        @size = size
        @offset = offset
      end
    end

    class VertexLayout
      attr_reader :attributes, :stride

      def initialize(&block)
        @attributes = {}
        @offset = 0
        instance_eval(&block) if block_given?
        @stride = @offset
      end

      def attribute(name, size)
        @attributes[name.to_sym] = VertexAttribute.new(name, size, @offset)
        @offset += size
      end

      def self.position_only
        new { attribute :position, 3 }
      end

      def self.position_color
        new do
          attribute :position, 3
          attribute :color, 4
        end
      end

      def self.position_normal_uv
        new do
          attribute :position, 3
          attribute :normal, 3
          attribute :uv, 2
        end
      end

      def self.position_normal_uv_color
        new do
          attribute :position, 3
          attribute :normal, 3
          attribute :uv, 2
          attribute :color, 4
        end
      end
    end

    class VertexBuffer
      attr_reader :data, :layout, :vertex_count

      def initialize(layout)
        @layout = layout
        @data = []
        @vertex_count = 0
      end

      def add_vertex(**attributes)
        vertex_data = []
        @layout.attributes.each do |name, attr|
          value = attributes[name]
          raise "Missing attribute: #{name}" unless value

          case value
          when Larb::Vec2
            vertex_data.concat([value.x, value.y])
          when Larb::Vec3
            vertex_data.concat([value.x, value.y, value.z])
          when Larb::Vec4
            vertex_data.concat([value.x, value.y, value.z, value.w])
          when Larb::Color
            vertex_data.concat(value.to_a)
          when Array
            vertex_data.concat(value)
          when Numeric
            vertex_data << value.to_f
          end
        end
        @data.concat(vertex_data)
        @vertex_count += 1
        self
      end

      def add_vertices(*vertices)
        vertices.each { |v| add_vertex(**v) }
        self
      end

      def get_vertex(index)
        return nil if index < 0 || index >= @vertex_count

        start = index * @layout.stride
        vertex = {}

        @layout.attributes.each do |name, attr|
          offset = start + attr.offset
          values = @data[offset, attr.size]

          vertex[name] = case attr.size
                         when 1 then values[0]
                         when 2 then Larb::Vec2.new(*values)
                         when 3 then Larb::Vec3.new(*values)
                         when 4
                           if name == :color
                             Larb::Color.new(*values)
                           else
                             Larb::Vec4.new(*values)
                           end
                         end
        end

        vertex
      end

      def self.from_array(layout, data)
        buffer = new(layout)
        data.each { |vertex| buffer.add_vertex(**vertex) }
        buffer
      end
    end

    class IndexBuffer
      attr_reader :indices

      def initialize(indices = [])
        @indices = indices.map(&:to_i)
      end

      def add(*idx)
        @indices.concat(idx.flatten.map(&:to_i))
        self
      end

      def triangle_count
        @indices.size / 3
      end

      def get_triangle(index)
        start = index * 3
        @indices[start, 3]
      end

      def each_triangle
        return enum_for(:each_triangle) unless block_given?

        (0...triangle_count).each { |i| yield get_triangle(i) }
      end
    end
  end
end
