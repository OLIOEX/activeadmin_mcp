# frozen_string_literal: true

module ActiveAdminMcp
  class McpController < ActionController::API
    before_action :authenticate_mcp_token!

    attr_reader :current_mcp_user

    def call
      request_body = JSON.parse(request.body.read)
      response = RequestHandler.new(current_user: current_mcp_user).handle(request_body)

      response ? render(json: response) : head(:no_content)
    rescue JSON::ParserError => e
      render json: { jsonrpc: "2.0", error: { code: -32_700, message: e.message } }, status: :bad_request
    end

    private

    def authenticate_mcp_token!
      return unless ActiveAdminMcp.config.authentication_enabled?

      token = extract_bearer_token
      unless token
        render json: jsonrpc_error(-32_000, "Unauthorized"), status: :unauthorized
        return
      end

      api_token = ApiToken.find_by_raw_token(token)
      unless api_token
        render json: jsonrpc_error(-32_000, "Unauthorized"), status: :unauthorized
        return
      end

      @current_mcp_user = api_token.user
      api_token.touch_last_used!
    rescue ActiveRecord::StatementInvalid
      render json: jsonrpc_error(-32_000, "Authentication not configured — run migrations"),
             status: :internal_server_error
    end

    def extract_bearer_token
      header = request.headers[ActiveAdminMcp.config.auth_header_name]
      return nil unless header&.start_with?("Bearer ")

      header.delete_prefix("Bearer ")
    end

    def jsonrpc_error(code, message)
      { jsonrpc: "2.0", id: nil, error: { code: code, message: message } }
    end
  end
end
