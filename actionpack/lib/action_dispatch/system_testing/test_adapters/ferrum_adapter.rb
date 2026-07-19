# frozen_string_literal: true

require "action_dispatch/system_testing/test_adapter"

module ActionDispatch
  module SystemTesting
    module TestAdapters
      # Provides Ferrum's native Browser, Context, and Page objects to
      # `ActionDispatch::ServerSystemTestCase`.
      class FerrumAdapter < TestAdapter
        global_helper :browser do |base_url:|
          browser = ferrum_browser.new(**browser_options(base_url))
          on_teardown { browser.quit }
          browser
        end

        helper :browser_context do |browser:|
          context = browser.contexts.create(**browser_context_options)
          on_teardown { context.dispose }
          context
        end

        helper :page do |browser_context:|
          page = browser_context.create_page
          on_teardown { page.close }
          page
        end

        private
          def ferrum_browser
            require "ferrum"
            Ferrum::Browser
          rescue LoadError
            raise LoadError, "The Ferrum system test adapter requires the `ferrum` gem."
          end

          def browser_options(base_url)
            { base_url: options.fetch(:base_url, base_url) }.merge(options.fetch(:browser_options, {}))
          end

          def browser_context_options
            options.fetch(:browser_context_options, {})
          end
      end
    end
  end
end
