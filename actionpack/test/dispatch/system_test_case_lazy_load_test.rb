# frozen_string_literal: true

require "abstract_unit"
require "open3"
require "rbconfig"

class SystemTestCaseLazyLoadTest < ActiveSupport::TestCase
  test "loads without capybara being available" do
    script = <<~RUBY
      module Kernel
        alias_method :require_without_capybara_guard, :require
        def require(path)
          raise LoadError, "capybara is unavailable" if path.start_with?("capybara")
          require_without_capybara_guard(path)
        end

        alias_method :gem_without_capybara_guard, :gem
        def gem(name, *requirements)
          raise Gem::LoadError, "capybara is unavailable" if name == "capybara"
          gem_without_capybara_guard(name, *requirements)
        end
      end

      require "active_support/testing/autorun"
      require "action_dispatch/system_test_case"

      abort "Capybara was loaded" if defined?(Capybara)
    RUBY

    stdout, stderr, status = Open3.capture3(
      { "BUNDLE_GEMFILE" => Bundler.default_gemfile.to_s },
      RbConfig.ruby,
      "-rbundler/setup",
      "-e",
      script
    )

    assert status.success?, "#{stdout}\n#{stderr}"
  end
end
