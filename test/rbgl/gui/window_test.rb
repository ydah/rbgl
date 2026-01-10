# frozen_string_literal: true

require_relative '../../test_helper'
require 'tmpdir'

class WindowTest < Test::Unit::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test 'initializes with file backend' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      title: 'Test',
      backend: :file,
      output_dir: @tmpdir
    )
    assert_equal 100, window.width
    assert_equal 100, window.height
    assert_kind_of RBGL::Engine::Context, window.context
    assert_kind_of RBGL::GUI::FileBackend, window.backend
  end

  test 'context is initialized with correct dimensions' do
    window = RBGL::GUI::Window.new(
      width: 200,
      height: 150,
      backend: :file,
      output_dir: @tmpdir
    )
    assert_equal 200, window.context.width
    assert_equal 150, window.context.height
  end

  test 'on registers event handler' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    called = false
    window.on(:key_press) { called = true }
    assert_false called
  end

  test 'on_key delegates to backend' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    window.on_key { |_key, _action| }
  end

  test 'on_mouse delegates to backend' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    window.on_mouse { |_x, _y, _button, _action| }
  end

  test 'stop sets running to false' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    window.stop
  end

  test 'present_framebuffer uses context framebuffer by default' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    window.present_framebuffer
    assert File.exist?(File.join(@tmpdir, 'frame_00000.ppm'))
  end

  test 'present_framebuffer can use custom framebuffer' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    fb = RBGL::Engine::Framebuffer.new(50, 50)
    window.present_framebuffer(fb)
  end

  test 'fps returns 0 initially' do
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: :file,
      output_dir: @tmpdir
    )
    assert_equal 0, window.fps
  end

  test 'raises error for unknown backend' do
    assert_raise(RuntimeError) do
      RBGL::GUI::Window.new(
        width: 100,
        height: 100,
        backend: :unknown
      )
    end
  end

  test 'accepts Backend instance directly' do
    backend = RBGL::GUI::FileBackend.new(100, 100, 'Test', output_dir: @tmpdir)
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: backend
    )
    assert_same backend, window.backend
  end
end

class MockLoopBackend < RBGL::GUI::Backend
  attr_reader :present_count, :poll_count, :closed

  def initialize(width, height, title = 'RBGL', max_frames: 2)
    super(width, height, title)
    @present_count = 0
    @poll_count = 0
    @closed = false
    @max_frames = max_frames
    @events = []
  end

  def present(_framebuffer)
    @present_count += 1
  end

  def poll_events
    @poll_count += 1
    @events.shift
  end

  def should_close?
    @present_count >= @max_frames
  end

  def close
    @closed = true
  end

  def add_events(events)
    @events.concat(events)
  end
end

class WindowRunTest < Test::Unit::TestCase
  test 'run executes frame loop' do
    backend = MockLoopBackend.new(100, 100, max_frames: 3)
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: backend
    )

    frame_count = 0
    window.run do |_ctx, _dt|
      frame_count += 1
    end

    assert_equal 3, frame_count
    assert_equal 3, backend.present_count
    assert_true backend.closed
  end

  test 'run updates fps' do
    backend = MockLoopBackend.new(100, 100, max_frames: 5)
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: backend
    )

    window.run { |_ctx, _dt| }

    assert backend.present_count.positive?
    assert window.fps.positive?
  end

  test 'process_events dispatches events to handlers' do
    backend = MockLoopBackend.new(100, 100, max_frames: 2)
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: backend
    )

    event = RBGL::GUI::Event.new(:key_press, key: 65)
    backend.add_events([[event]])

    received_events = []
    window.on(:key_press) { |e| received_events << e }

    window.run { |_ctx, _dt| }

    assert_equal 1, received_events.size
    assert_equal :key_press, received_events[0].type
  end

  test 'run with nil frame callback' do
    backend = MockLoopBackend.new(100, 100, max_frames: 2)
    window = RBGL::GUI::Window.new(
      width: 100,
      height: 100,
      backend: backend
    )

    window.run
    assert_equal 2, backend.present_count
  end
end
