# frozen_string_literal: true

require "action_dispatch/system_testing/test_adapter"

module ActionDispatch
  module SystemTesting
    module TestAdapters
      # Provides Playwright's native Browser, BrowserContext, and Page objects to
      # `ActionDispatch::ServerSystemTestCase`.
      class PlaywrightAdapter < TestAdapter
        global_helper :browser do
          browser_type = selected_browser_type

          if browser_server_endpoint_url
            execution = playwright.connect_to_browser_server(
              browser_server_endpoint_url,
              browser_type: browser_type.to_s,
            )
            on_teardown { execution.stop }
            execution.browser
          else
            execution = playwright.create(
              playwright_cli_executable_path: playwright_cli_executable_path,
            )
            on_teardown { execution.stop }

            browser = execution.playwright.public_send(browser_type).launch(**browser_launch_options)
            on_teardown { browser.close }
            browser
          end
        end

        helper :browser_context do |base_url:, browser:|
          context = browser.new_context(**browser_context_options(base_url))
          on_teardown { context.close }
          context
        end

        helper :page do |browser_context:|
          page = browser_context.new_page
          on_teardown { page.close }
          page
        end

        private
          def playwright
            require "playwright"
            Playwright
          rescue LoadError
            raise LoadError, "The Playwright system test adapter requires the `playwright-ruby-client` gem."
          end

          def playwright_cli_executable_path
            options.fetch(:playwright_cli_executable_path) do
              ENV.fetch("PLAYWRIGHT_CLI_EXECUTABLE_PATH", "./node_modules/.bin/playwright")
            end
          end

          def browser_server_endpoint_url
            options.fetch(:browser_server_endpoint_url) { ENV["PLAYWRIGHT_WS_ENDPOINT"] }
          end

          def selected_browser_type
            browser_type = options.fetch(:browser_type) { ENV.fetch("BROWSER", "chromium") }.to_sym
            return browser_type if %i[chromium firefox webkit].include?(browser_type)

            raise ArgumentError, "unknown Playwright browser type: #{browser_type.inspect}"
          end

          def browser_launch_options
            launch_options = {
              headless: options.fetch(:headless) do
                !%w[0 false].include?(ENV.fetch("HEADLESS", "true"))
              end,
            }
            launch_options[:channel] = options[:channel] if options.key?(:channel)
            launch_options[:slowMo] = options[:slow_mo] if options.key?(:slow_mo)
            launch_options.merge(options.fetch(:browser_launch_options, {}))
          end

          def browser_context_options(base_url)
            context_options = { baseURL: options.fetch(:base_url, base_url) }
            context_options.merge(options.fetch(:browser_context_options, {}))
          end
      end
    end
  end
end
