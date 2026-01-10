# frozen_string_literal: true

module RBGL
  module GUI
    class Window
      attr_reader :context, :backend, :width, :height, :fps

      def initialize(width:, height:, title: 'RBGL', backend: :auto, **options)
        @width = width
        @height = height
        @title = title
        @context = Engine::Context.new(width: width, height: height)

        @backend = case backend
                   when :auto, :native
                     detect_backend(width, height, title)
                   when :file
                     FileBackend.new(width, height, title, **options)
                   when :x11
                     require_relative 'x11/backend'
                     X11::Backend.new(width, height, title)
                   when :wayland
                     require_relative 'wayland/backend'
                     Wayland::Backend.new(width, height, title)
                   when :cocoa
                     require_relative 'cocoa/backend'
                     Cocoa::Backend.new(width, height, title)
                   when Backend
                     backend
                   else
                     raise "Unknown backend: #{backend}"
                   end

        @running = false
        @frame_callback = nil
        @last_time = Time.now
        @fps = 0
        @frame_count = 0
        @event_handlers = Hash.new { |h, k| h[k] = [] }
      end

      def on(event_type, &block)
        @event_handlers[event_type] << block
      end

      def on_key(&)
        @backend.on_key(&)
      end

      def on_mouse(&)
        @backend.on_mouse(&)
      end

      def run(&frame_callback)
        @frame_callback = frame_callback
        @running = true
        @start_time = Time.now

        while @running && !@backend.should_close?
          current_time = Time.now
          delta_time = current_time - @last_time
          @last_time = current_time

          process_events

          @frame_callback&.call(@context, delta_time)

          @backend.present(@context.framebuffer)

          @frame_count += 1
          elapsed = current_time - @start_time
          @fps = @frame_count / elapsed if elapsed.positive?
        end

        @backend.close
      end

      def stop
        @running = false
      end

      def present_framebuffer(framebuffer = nil)
        fb = framebuffer || @context.framebuffer
        @backend.present(fb)
      end

      def set_pixels(buffer)
        @backend.set_pixels(buffer, @width, @height)
      end

      def metal_available?
        @backend.metal_available?
      end

      def native_handle
        @backend.native_handle
      end

      def should_close?
        @backend.should_close?
      end

      def poll_events_raw
        @backend.poll_events_raw
      end

      def close
        @backend.close
      end

      private

      def detect_backend(width, height, title)
        case RUBY_PLATFORM
        when /darwin/
          require_relative 'cocoa/backend'
          Cocoa::Backend.new(width, height, title)
        when /linux/
          if ENV['WAYLAND_DISPLAY']
            require_relative 'wayland/backend'
            Wayland::Backend.new(width, height, title)
          elsif ENV['DISPLAY']
            require_relative 'x11/backend'
            X11::Backend.new(width, height, title)
          else
            raise 'No display server found (DISPLAY or WAYLAND_DISPLAY not set)'
          end
        else
          raise "Unsupported platform: #{RUBY_PLATFORM}"
        end
      end

      def process_events
        events = @backend.poll_events

        return unless events.is_a?(Array)

        events.each do |event|
          next unless event.is_a?(Event)

          @event_handlers[event.type].each { |handler| handler.call(event) }
        end
      end
    end
  end
end
