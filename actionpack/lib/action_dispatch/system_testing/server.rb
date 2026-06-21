# frozen_string_literal: true

# :markup: markdown

require "action_dispatch/testing/test_server"

module ActionDispatch
  module SystemTesting
    class Server # :nodoc:
      class << self
        attr_accessor :silence_puma, :test_server

        def stop
          test_server&.stop
          self.test_server = nil
        end
      end

      self.silence_puma = false

      def initialize(app: nil, driver: nil)
        @app = app
        @driver = driver
      end

      def run
        setup
      end

      private
        def setup
          set_server
          set_port
        end

        def set_server
          unset_rails_test_server_url if using_rails_test_server_url?

          if use_rails_test_server?
            start_rails_test_server
          elsif driver_uses_server? && Capybara.server == Capybara.servers[:default]
            Capybara.server = :puma, { Silent: self.class.silence_puma }
          end
        end

        def set_port
          Capybara.always_include_port = true
        end

        def use_rails_test_server?
          @app && driver_uses_server? && Capybara.app_host.nil? && Capybara.server == Capybara.servers[:default]
        end

        def driver_uses_server?
          !@driver.respond_to?(:server_required?) || @driver.server_required?
        end

        def start_rails_test_server
          host = Capybara.server_host || ActionDispatch::TestServer::DEFAULT_HOST
          port = Capybara.server_port

          server = self.class.test_server
          unless server&.running? && server.app.equal?(@app) && server.host == host && (!port || server.port == port)
            self.class.stop
            server = ActionDispatch::TestServer.new(
              app: @app,
              host: host,
              port: port,
              server: :puma,
              server_options: { Silent: self.class.silence_puma }
            ).start
            self.class.test_server = server
          end

          Capybara.run_server = false
          Capybara.app_host = server.base_url
        end

        def using_rails_test_server_url?
          self.class.test_server && Capybara.app_host == self.class.test_server.base_url
        end

        def unset_rails_test_server_url
          Capybara.app_host = nil
          Capybara.run_server = true
        end
    end
  end
end

at_exit { ActionDispatch::SystemTesting::Server.stop }
