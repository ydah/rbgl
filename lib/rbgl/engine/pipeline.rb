# frozen_string_literal: true

module RBGL
  module Engine
    class Pipeline
      attr_accessor :vertex_shader, :fragment_shader
      attr_accessor :depth_test, :depth_write
      attr_accessor :cull_mode
      attr_accessor :blend_mode

      def initialize
        @vertex_shader = nil
        @fragment_shader = nil
        @depth_test = true
        @depth_write = true
        @cull_mode = :back
        @blend_mode = :none
      end

      def self.create(&block)
        pipeline = new
        pipeline.instance_eval(&block) if block_given?
        pipeline
      end

      def vertex(&block)
        @vertex_shader = VertexShader.new(&block)
      end

      def fragment(&block)
        @fragment_shader = FragmentShader.new(&block)
      end
    end
  end
end
