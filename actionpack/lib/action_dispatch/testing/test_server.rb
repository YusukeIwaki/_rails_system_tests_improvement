# frozen_string_literal: true

require "socket"
require "timeout"

module ActionDispatch
  class TestServer # :nodoc:
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_WAIT = 5
    DEFAULT_PUMA_OPTIONS = { Threads: "0:4", workers: 0, daemon: false }.freeze

    attr_reader :app, :host, :port

    def initialize(app:, host: DEFAULT_HOST, port: nil, server: :puma, server_options: {}, wait: DEFAULT_WAIT)
      @app = app
      @host = host
      @port = port || find_available_port(host)
      @server_name = server
      @server_options = server_options
      @wait = wait
      @server = nil
      @server_thread = nil
      @server_error = nil
    end

    def start
      return self if running?

      @server_error = nil
      @server_thread = Thread.new { run }
      @server_thread.abort_on_exception = false
      wait_until_ready

      self
    rescue Exception
      stop
      raise
    end

    def stop
      stop_server
      stop_thread
    end

    def running?
      @server_thread&.alive? && responsive?
    end

    def base_url
      "http://#{host}:#{port}"
    end

    private
      def run
        resolved_server.run(app, **options) do |server|
          @server = server
        end
      rescue Exception => error
        @server_error = error
      ensure
        @server = nil
      end

      def options
        {
          Host: host,
          Port: port
        }.merge(@server_options)
      end

      def resolved_server
        if @server_name.respond_to?(:run)
          @server_name
        elsif @server_name == :puma
          PumaServer
        elsif @server_name
          rackup_handler.get(@server_name) || raise(LoadError, "Could not find Rack handler for #{@server_name.inspect}")
        else
          rackup_handler.default
        end
      end

      def rackup_handler
        @rackup_handler ||= begin
          require "rackup/handler"
          Rackup::Handler
        rescue LoadError
          require "rack/handler"
          Rack::Handler
        end
      end

      def wait_until_ready
        Timeout.timeout(@wait) do
          until responsive?
            raise @server_error if @server_error

            sleep 0.01
          end
        end
      rescue Timeout::Error
        raise @server_error if @server_error

        raise
      end

      def responsive?
        Socket.tcp(host, port, connect_timeout: 0.1) do |socket|
          socket.close
        end
        true
      rescue SystemCallError, IOError
        false
      end

      def stop_server
        if @server.respond_to?(:stop)
          @server.stop
        elsif @server.respond_to?(:shutdown)
          @server.shutdown
        end
      end

      def stop_thread
        return unless @server_thread

        @server_thread.join(@wait)
        if @server_thread.alive?
          @server_thread.kill
          @server_thread.join
        end
        @server_thread = nil
      end

      def find_available_port(host)
        TCPServer.open(host, 0) do |server|
          server.addr[1]
        end
      end

      module PumaServer
        module_function

        def run(app, **options)
          begin
            require "rackup"
          rescue LoadError
            # Puma can still register itself as Rack::Handler on Rack < 3.
          end

          begin
            require "rack/handler/puma"
          rescue LoadError
            raise LoadError, "Unable to load `puma` for the test server. Add `puma` to your Gemfile or configure another Rack server."
          end

          puma_handler = defined?(Rackup::Handler::Puma) ? Rackup::Handler::Puma : Rack::Handler::Puma
          unless puma_handler.respond_to?(:config)
            raise LoadError, "The test server requires puma 3.8.0 or newer."
          end

          config = puma_handler.config(app, DEFAULT_PUMA_OPTIONS.merge(options))
          config.clamp

          log_writer = puma_log_writer(config)
          config.options[:log_writer] = log_writer

          puma_server = Puma::Server.new(config.app, puma_events(log_writer), config.options)
          puma_server.binder.parse(config.options[:binds], log_writer)
          if puma_server.respond_to?(:min_threads=)
            puma_server.min_threads = config.options[:min_threads]
            puma_server.max_threads = config.options[:max_threads]
          end

          yield puma_server if block_given?

          puma_server.run.join
        end

        def puma_log_writer(config)
          log_writer = defined?(Puma::LogWriter) ? Puma::LogWriter : Puma::Events
          config.options[:Silent] ? log_writer.strings : log_writer.stdio
        end

        def puma_events(log_writer)
          defined?(Puma::LogWriter) ? nil : log_writer
        end
      end
  end
end
