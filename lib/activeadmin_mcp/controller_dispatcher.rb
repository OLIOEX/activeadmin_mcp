# frozen_string_literal: true

module ActiveadminMcp
  # Runs a real ActiveAdmin controller action out of band, so an MCP tool call
  # goes through the same before_action chain, authorization and callbacks as a
  # click in the admin UI.
  #
  # We synthesize the request rather than route one. Routing would mean issuing
  # a second HTTP request against the app, which would have to authenticate as
  # the MCP user by forging an admin session — a back door this gem should not
  # have. Building the request by hand lets us inject the already-authenticated
  # MCP user directly onto the controller instead.
  class ControllerDispatcher
    def initialize(config:, current_user:)
      @config = config
      @current_user = current_user
    end

    def call(action:, path:, verb: :get, params: {}, path_params: {})
      controller = build_controller
      request = build_request(path: path, verb: verb, params: params, action: action, path_params: path_params)
      response = ActionDispatch::Response.new

      controller.set_request!(request)
      controller.set_response!(response)
      controller.process(action)

      capture(request, response)
    rescue StandardError => e
      { error: "#{@config.resource_class.name}##{action} failed: #{e.message}" }
    end

    private

    def build_controller
      user = @current_user
      controller = @config.controller.new

      controller.define_singleton_method(ActiveadminMcp.config.current_user_method) { user }
      controller.define_singleton_method(:current_active_admin_user) { user }

      # The namespace's authentication_method (typically Devise's
      # authenticate_admin_user!) would redirect us to a login page. The MCP
      # request has already authenticated by bearer token, so it is a no-op
      # here — this does NOT skip authorization, which still runs in full.
      auth_method = @config.namespace.authentication_method
      controller.define_singleton_method(auth_method) { true } if auth_method

      controller
    end

    def build_request(path:, verb:, params:, action:, path_params:)
      env = Rack::MockRequest.env_for(
        path,
        method: verb.to_s.upcase,
        params: params.transform_keys(&:to_s)
      )
      # Flash needs somewhere to live; without a session the action raises.
      env["rack.session"] = {}
      env["action_dispatch.request.path_parameters"] =
        { controller: controller_path, action: action.to_s }.merge(path_params)

      ActionDispatch::Request.new(env)
    end

    def controller_path
      @config.controller.name.underscore.sub(/_controller\z/, "")
    end

    def capture(request, response)
      result = { status: response.status }

      if response.redirect?
        result[:redirect_to] = response.location
      else
        # Deliberately not the body: admin HTML is large and almost entirely
        # chrome, and would swamp the client's context for no benefit.
        result[:rendered] = true
      end

      flash = extract_flash(request)
      result[:flash] = flash if flash&.any?
      result
    end

    def extract_flash(request)
      request.flash.to_hash
    rescue StandardError
      nil
    end
  end
end
