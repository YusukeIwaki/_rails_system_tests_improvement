# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/system_testing/test_adapters/ferrum_adapter"

class FerrumAdapterTest < ActiveSupport::TestCase
  class FakePage
    def initialize(events)
      @events = events
    end

    def close
      @events << :close_page
    end
  end

  class FakeContext
    def initialize(events)
      @events = events
    end

    def create_page
      @events << :open_page
      FakePage.new(@events)
    end

    def dispose
      @events << :dispose_context
    end
  end

  class FakeContexts
    attr_reader :options

    def initialize(events)
      @events = events
    end

    def create(**options)
      @options = options
      @events << :open_context
      FakeContext.new(@events)
    end
  end

  class FakeBrowser
    attr_reader :contexts, :options

    def initialize(events, **options)
      @events = events
      @options = options
      @contexts = FakeContexts.new(events)
      @events << :open_browser
    end

    def quit
      @events << :quit_browser
    end
  end

  class TestCase
    def base_url
      "http://127.0.0.1:3000"
    end
  end

  test "provides an isolated context and page for each test" do
    events = []
    adapter = new_adapter(
      events,
      browser_options: { headless: false, timeout: 10 },
      browser_context_options: { disposeOnDetach: true },
    )
    adapter.install(TestCase)

    first_test = TestCase.new
    adapter.before_setup
    first_page = first_test.page
    assert_same first_page, first_test.page
    adapter.after_teardown

    second_test = TestCase.new
    adapter.before_setup
    second_page = second_test.page
    adapter.after_teardown

    assert_not_same first_page, second_page
    assert_equal({ base_url: "http://127.0.0.1:3000", headless: false, timeout: 10 }, first_test.browser.options)
    assert_equal({ disposeOnDetach: true }, first_test.browser.contexts.options)
    assert_equal 1, events.count(:open_browser)
    assert_equal 2, events.count(:open_context)
    assert_equal 2, events.count(:open_page)
    assert_equal [:close_page, :dispose_context], events.last(2)

    adapter.shutdown

    assert_equal :quit_browser, events.last
  end

  private
    def new_adapter(events, **options)
      browser_class = Class.new do
        define_singleton_method(:new) do |**browser_options|
          FakeBrowser.new(events, **browser_options)
        end
      end
      adapter = ActionDispatch::SystemTesting::TestAdapters::FerrumAdapter.new(**options)
      adapter.define_singleton_method(:ferrum_browser) { browser_class }
      adapter
    end
end
