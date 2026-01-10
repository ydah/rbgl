# frozen_string_literal: true

module RBGL
  module Engine
    class Pipeline
      attr_accessor :vertex_shader, :fragment_shader, :depth_test, :depth_write, :cull_mode, :blend_mode

      def initialize
        @vertex_shader = nil
        @fragment_shader = nil
        @depth_test = true
        @depth_write = true
        @cull_mode = :back
        @blend_mode = :none
      end

      def self.create(&)
        pipeline = new
        pipeline.instance_eval(&) if block_given?
        pipeline
      end

      def vertex(&)
        @vertex_shader = VertexShader.new(&)
      end

      def fragment(&)
        @fragment_shader = FragmentShader.new(&)
      end
    end
  end
end
