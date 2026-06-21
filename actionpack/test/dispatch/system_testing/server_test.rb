# frozen_string_literal: true

require "abstract_unit"
require "capybara/dsl"
require "action_dispatch/system_testing/server"

class ServerTest < ActiveSupport::TestCase
  FakeDriver = Struct.new(:server_required?, keyword_init: true)
  FakeTestServer = Struct.new(:app, :host, :port, :server, :server_options, :base_url, keyword_init: true) do
    def start
      self
    end

    def running?
      true
    end

    def stop
    end
  end

  setup do
    @old_capybara_server = Capybara.server
    @old_capybara_app_host = Capybara.app_host
    @old_capybara_run_server = Capybara.run_server
    @old_capybara_server_host = Capybara.server_host
    @old_capybara_server_port = Capybara.server_port
  end

  test "port is always included" do
    ActionDispatch::SystemTesting::Server.new.run
    assert Capybara.always_include_port, "expected Capybara.always_include_port to be true"
  end

  test "server is changed from `default` to `puma`" do
    Capybara.server = :default
    ActionDispatch::SystemTesting::Server.new.run
    assert_not_equal Capybara.server, Capybara.servers[:default]
  end

  test "server is not changed to `puma` when is different than default" do
    Capybara.server = :webrick
    ActionDispatch::SystemTesting::Server.new.run
    assert_equal Capybara.server, Capybara.servers[:webrick]
  end

  test "starts the Rails test server when using the default Capybara server" do
    app = ->(_) { [200, {}, []] }
    driver = FakeDriver.new(server_required?: true)
    started_server = nil

    ActionDispatch::TestServer.stub(:new, ->(**options) {
      started_server = FakeTestServer.new(**options, base_url: "http://127.0.0.1:31337")
    }) do
      Capybara.server = :default
      ActionDispatch::SystemTesting::Server.new(app: app, driver: driver).run
    end

    assert_equal app, started_server.app
    assert_equal "127.0.0.1", started_server.host
    assert_nil started_server.port
    assert_not Capybara.run_server
    assert_equal "http://127.0.0.1:31337", Capybara.app_host
  ensure
    ActionDispatch::SystemTesting::Server.stop
  end

  test "does not start the Rails test server for rack_test-style drivers" do
    driver = FakeDriver.new(server_required?: false)

    ActionDispatch::TestServer.stub(:new, ->(**) { flunk "should not start a test server" }) do
      Capybara.server = :default
      ActionDispatch::SystemTesting::Server.new(app: ->(_) { [200, {}, []] }, driver: driver).run
    end

    assert Capybara.run_server
    assert_nil Capybara.app_host
  end

  teardown do
    ActionDispatch::SystemTesting::Server.stop
    Capybara.server = @old_capybara_server
    Capybara.app_host = @old_capybara_app_host
    Capybara.run_server = @old_capybara_run_server
    Capybara.server_host = @old_capybara_server_host
    Capybara.server_port = @old_capybara_server_port
  end
end
