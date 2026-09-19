require "json"
require "net/http"
require "uri"

module E2E
  # A minimal MCP client: JSON-RPC 2.0 over HTTP, the way a real client such
  # as Claude Code talks to the mounted engine.
  class McpClient
    class ProtocolError < StandardError; end

    def initialize(url:, token: nil)
      @uri = URI(url)
      @token = token
      @id = 0
    end

    def initialize_session
      result_of("initialize", protocolVersion: "2025-06-18", clientInfo: { name: "e2e", version: "1.0" })
    end

    def tools_list
      result_of("tools/list")
    end

    # Tool results arrive as a pretty-printed JSON document inside a text
    # content block, so unwrap both layers and hand back the payload itself.
    def call_tool(name, arguments = {})
      result = result_of("tools/call", name: name, arguments: arguments)
      text = result.dig("content", 0, "text")

      raise ProtocolError, "No text content in tool result: #{result.inspect}" unless text

      JSON.parse(text)
    end

    def post(method, params = {})
      @id += 1
      request = Net::HTTP::Post.new(@uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@token}" if @token
      request.body = JSON.generate(jsonrpc: "2.0", id: @id, method: method, params: params)

      Net::HTTP.start(@uri.hostname, @uri.port) { |http| http.request(request) }
    end

    private

    def result_of(method, params = {})
      response = post(method, params)
      body = JSON.parse(response.body)

      raise ProtocolError, "JSON-RPC error from #{method}: #{body['error'].inspect}" if body["error"]

      body.fetch("result")
    end
  end
end
