# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/system_testing/test_adapters/playwright_adapter"

class PlaywrightAdapterTest < ActiveSupport::TestCase
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

    def new_page
      @events << :open_page
      FakePage.new(@events)
    end

    def close
      @events << :close_context
    end
  end

  class FakeBrowser
    attr_reader :context_options

    def initialize(events)
      @events = events
    end

    def new_context(**options)
      @context_options = options
      @events << :open_context
      FakeContext.new(@events)
    end

    def close
      @events << :close_browser
    end
  end

  class FakeBrowserType
    attr_reader :launch_options

    def initialize(events, browser)
      @events = events
      @browser = browser
    end

    def launch(**options)
      @launch_options = options
      @events << :open_browser
      @browser
    end
  end

  class FakeExecution
    attr_reader :playwright, :browser

    def initialize(events, playwright: nil, browser: nil)
      @events = events
      @playwright = playwright
      @browser = browser
    end

    def stop
      @events << :stop_execution
    end
  end

  class FakePlaywrightApi
    attr_reader :browser_type

    def initialize(events, browser)
      @browser_type = FakeBrowserType.new(events, browser)
    end

    def firefox
      @browser_type
    end
  end

  class FakePlaywright
    attr_reader :cli_path, :remote_options

    def initialize(local_execution:, remote_execution: nil)
      @local_execution = local_execution
      @remote_execution = remote_execution
    end

    def create(playwright_cli_executable_path:)
      @cli_path = playwright_cli_executable_path
      @local_execution
    end

    def connect_to_browser_server(endpoint, **options)
      @remote_options = [endpoint, options]
      @remote_execution
    end
  end

  class TestCase
    def base_url
      "http://127.0.0.1:3000"
    end
  end

  test "provides a fresh page and context for each test" do
    events = []
    browser = FakeBrowser.new(events)
    playwright_api = FakePlaywrightApi.new(events, browser)
    execution = FakeExecution.new(events, playwright: playwright_api)
    playwright = FakePlaywright.new(local_execution: execution)
    adapter = new_adapter(
      playwright: playwright,
      playwright_cli_executable_path: "/bin/playwright",
      browser_type: :firefox,
      headless: false,
      channel: "firefox-beta",
      slow_mo: 50,
      browser_context_options: { locale: "ja-JP" },
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
    assert_equal "/bin/playwright", playwright.cli_path
    assert_equal({ headless: false, channel: "firefox-beta", slowMo: 50 }, playwright_api.browser_type.launch_options)
    assert_equal({ baseURL: "http://127.0.0.1:3000", locale: "ja-JP" }, browser.context_options)
    assert_equal 1, events.count(:open_browser)
    assert_equal 2, events.count(:open_context)
    assert_equal 2, events.count(:open_page)
    assert_equal [:close_page, :close_context], events.last(2)

    adapter.shutdown

    assert_equal [:close_browser, :stop_execution], events.last(2)
  end

  test "connects to a browser server" do
    events = []
    browser = FakeBrowser.new(events)
    remote_execution = FakeExecution.new(events, browser: browser)
    playwright = FakePlaywright.new(local_execution: nil, remote_execution: remote_execution)
    adapter = new_adapter(
      playwright: playwright,
      browser_type: :firefox,
      browser_server_endpoint_url: "ws://playwright:3000/ws",
    )
    adapter.install(TestCase)
    test_case = TestCase.new
    adapter.before_setup

    assert_same browser, test_case.browser
    assert_equal ["ws://playwright:3000/ws", { browser_type: "firefox" }], playwright.remote_options

    adapter.after_teardown
    adapter.shutdown

    assert_equal [:stop_execution], events
  end

  test "rejects unknown browser types" do
    adapter = new_adapter(playwright: Object.new, browser_type: :netscape)
    adapter.install(TestCase)
    test_case = TestCase.new
    adapter.before_setup

    error = assert_raises(ArgumentError) { test_case.browser }
    assert_equal "unknown Playwright browser type: :netscape", error.message
  ensure
    adapter&.after_teardown if test_case
    adapter&.shutdown
  end

  private
    def new_adapter(**options)
      adapter = ActionDispatch::SystemTesting::TestAdapters::PlaywrightAdapter.new(**options)
      adapter.define_singleton_method(:playwright) { options.fetch(:playwright) }
      adapter
    end
end
