# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/testing/test_server"
require "net/http"
require "stringio"

class TestServerTest < ActiveSupport::TestCase
  class InProcessRackHandler
    def self.run(app, **options)
      server = new(app, **options)
      yield server if block_given?
      server.run
    end

    def initialize(app, **options)
      @app = app
      @server = TCPServer.new(options.fetch(:Host), options.fetch(:Port))
      @host = options.fetch(:Host)
      @port = options.fetch(:Port)
    end

    def run
      loop do
        socket = @server.accept
        handle(socket)
      end
    rescue IOError, Errno::EBADF
    ensure
      @server.close unless @server.closed?
    end

    def stop
      @server.close unless @server.closed?
    end

    private
      def handle(socket)
        request = socket.gets
        return unless request

        request_method, full_path = request.split(/\s+/, 3)
        while (line = socket.gets)
          break if line == "\r\n"
        end

        path, query = full_path.split("?", 2)
        status, headers, body = @app.call(
          "REQUEST_METHOD" => request_method,
          "PATH_INFO" => path,
          "QUERY_STRING" => query.to_s,
          "SERVER_NAME" => @host,
          "SERVER_PORT" => @port.to_s,
          "rack.input" => StringIO.new,
          "rack.url_scheme" => "http"
        )

        response = +""
        body.each { |part| response << part }
        body.close if body.respond_to?(:close)

        socket.write "HTTP/1.1 #{status} OK\r\n"
        headers.each do |key, value|
          socket.write "#{key}: #{value}\r\n"
        end
        socket.write "Content-Length: #{response.bytesize}\r\n"
        socket.write "Connection: close\r\n"
        socket.write "\r\n"
        socket.write response
      ensure
        socket.close
      end
  end

  test "serves a Rack app in a separate thread" do
    app = lambda do |env|
      [200, { "Content-Type" => "text/plain" }, ["Hello from #{env["PATH_INFO"]}"]]
    end
    server = ActionDispatch::TestServer.new(app: app, server: InProcessRackHandler)

    server.start

    assert_predicate server, :running?
    assert_equal "Hello from /test", Net::HTTP.get(URI("#{server.base_url}/test"))
  ensure
    server&.stop
  end
end
