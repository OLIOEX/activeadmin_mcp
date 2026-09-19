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
      controller = controller_with_mcp_user
      request = build_request(path: path, verb: verb, params: params, action: action, path_params: path_params)
      response = ActionDispatch::Response.new

      controller.set_request!(request)
      controller.set_response!(response)
      controller.process(action)

      capture(request, response)
    rescue StandardError => e
      # The exception text can carry internals — SQL fragments, table names,
      # file paths. It belongs in the application's log, not in a tool result
      # that goes to an MCP client.
      warn("[activeadmin_mcp] #{@config.resource_class.name}##{action} raised #{e.class}: #{e.message}")
      { error: "#{@config.resource_class.name}##{action} failed" }
    end

    # A controller instance for this resource with the MCP user injected, ready
    # either to process a request or to serve as the evaluation context for an
    # action's `permission:` proc. Public because listing-time permission checks
    # need exactly the same context a dispatched call gets.
    def controller_with_mcp_user
      user = @current_user
      controller = @config.controller.new

      current_user_methods.each do |method_name|
        controller.define_singleton_method(method_name) { user }
      end

      # The namespace's authentication_method (typically Devise's
      # authenticate_admin_user!) would redirect us to a login page. The MCP
      # request has already authenticated by bearer token, so it is a no-op
      # here — this does NOT skip authorization, which still runs in full.
      auth_method = @config.namespace.authentication_method
      controller.define_singleton_method(auth_method) { true } if auth_method

      # The synthesized request carries no session-bound CSRF token, so
      # Rails' own forgery protection would refuse every non-GET action
      # (member actions declared `method: :post`, and every batch action,
      # which always dispatches as one). The MCP request has already
      # authenticated by bearer token; this does NOT skip authorization,
      # which still runs in full.
      controller.define_singleton_method(:verified_request?) { true }

      controller
    end

    private

    # An application can point ActiveadminMcp at one current-user method and the
    # ActiveAdmin namespace at another. Stub both, so an action body calling
    # either gets the MCP user rather than nil. uniq keeps us from defining the
    # same singleton method twice when they agree.
    def current_user_methods
      namespace_method = @config.namespace.current_user_method if @config.namespace.respond_to?(:current_user_method)

      [
        ActiveadminMcp.config.current_user_method,
        namespace_method,
        :current_active_admin_user,
      ].select { |name| name.respond_to?(:to_sym) }.map(&:to_sym).uniq
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
