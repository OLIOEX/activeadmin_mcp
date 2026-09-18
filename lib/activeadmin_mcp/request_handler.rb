module ActiveadminMcp
  class RequestHandler
    PROTOCOL_VERSION = "2025-06-18"

    def initialize(current_user: nil)
      @current_user = current_user
    end

    def handle(request)
      id = request["id"]
      method = request["method"]
      params = request["params"] || {}

      case method
      when "initialize"
        success(id, initialize_result)
      when "notifications/initialized"
        nil
      when "tools/list"
        success(id, tools_list)
      when "tools/call"
        success(id, call_tool(params))
      when "ping"
        success(id, {})
      else
        error(id, -32_601, "Method not found: #{method}")
      end
    end

    private

    def initialize_result
      {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: { name: "activeadmin-mcp", version: ActiveadminMcp::VERSION },
        capabilities: { tools: {} },
      }
    end

    def tools_list
      { tools: built_in_tools + action_tools }
    end

    # Both gates run before the schema is built, never after: ActionSchema calls
    # the application's `suggestions:` procs, which read the database. Filtering
    # an already-assembled list would mean those procs had already run — and
    # their values already been read — for a user authorized for none of it.
    def action_tools
      ActionCatalog.all.filter_map do |definition|
        next unless authorized_to_run?(definition)
        next unless authorized_to_list?(definition)

        {
          name: definition.tool_name,
          description: definition.description,
          inputSchema: ActionSchema.new(definition).to_h,
        }
      end
    end

    # The same authorization adapter check ActionRunner makes before dispatch,
    # and the one list_resources makes for reads. There is no record at listing
    # time, so the subject is the resource class.
    def authorized_to_run?(definition)
      Authorization.for(definition.config, @current_user)
                   .authorized?(definition.action_name, definition.config.resource_class)
    rescue StandardError => e
      warn("[activeadmin_mcp] hiding #{definition.tool_name}: authorization check raised #{e.class}: #{e.message}")
      false
    end

    # Collection and batch actions whose permission proc takes no record can be
    # resolved now, so the tool is simply hidden. A member action's proc needs a
    # record, so its tool stays listed and refusal happens at call time.
    #
    # The proc is evaluated in controller context, exactly as ActionRunner
    # evaluates it at call time, so `current_admin_user`, `can?` and the rest of
    # the admin helpers are in scope. Evaluating it bare would make every such
    # proc raise NameError and hide its tool from everybody.
    def authorized_to_list?(definition)
      permission = definition.permission
      return true unless permission
      return true unless permission.respond_to?(:arity) && permission.arity.zero?

      controller = ControllerDispatcher.new(config: definition.config, current_user: @current_user)
                                       .controller_with_mcp_user
      !!::MethodOrProcHelper.render_in_context(controller, permission)
    rescue StandardError => e
      # One broken proc hides its own tool and nothing else, but it says so.
      warn("[activeadmin_mcp] hiding #{definition.tool_name}: permission proc raised #{e.class}: #{e.message}")
      false
    end

    def built_in_tools
      [
        {
          name: "list_resources",
          description: "List the ActiveAdmin resources the authenticated user is authorized " \
                       "to read, with their attributes",
          inputSchema: { type: "object", properties: {} },
        },
        {
          name: "query",
          description: "Query an ActiveAdmin resource using Ransack syntax. Respects ActiveAdmin " \
                       "authorization: the resource must be readable by the authenticated user, " \
                       "and results are scoped to the records they may access.",
          inputSchema: {
            type: "object",
            properties: {
              resource: { type: "string", description: "Resource name (e.g., 'User', 'Post')" },
              q: { type: "object", description: "Ransack query (e.g., {name_cont: 'john'})" },
              limit: { type: "integer", description: "Max records (default: 25)" },
            },
            required: ["resource"],
          },
        },
        {
          name: "update",
          description: "Update an existing record. Only fields the resource's ActiveAdmin " \
                       "form permits are written, and the update respects ActiveAdmin authorization.",
          inputSchema: {
            type: "object",
            properties: {
              resource: { type: "string", description: "Resource name (e.g., 'User', 'Post')" },
              id: { type: ["integer", "string"], description: "Primary key of the record to update" },
              attributes: { type: "object", description: "Attributes to update (e.g., {name: 'New name'})" },
            },
            required: %w[resource id attributes],
          },
        },
      ]
    end

    def call_tool(params)
      name = params["name"]
      args = params["arguments"] || {}

      result = case name
               when "list_resources" then tool_list_resources
               when "query" then tool_query(args)
               when "update" then tool_update(args)
               else tool_action(name, args)
               end

      { content: [{ type: "text", text: JSON.pretty_generate(result) }] }
    end

    def tool_action(name, args)
      definition = ActionCatalog.find(name)
      return { error: "Unknown tool: #{name}" } unless definition

      ActionRunner.new(definition: definition, current_user: @current_user).call(args)
    end

    def tool_list_resources
      entries = ResourceRegistry.resources.select { |entry| authorized_to_read?(entry) }
      { resources: entries.map { |entry| ResourceRegistry.resource_info(entry) } }
    end

    def tool_query(args)
      resource = ResourceRegistry.find(args["resource"])
      return { error: "Resource not found: #{args['resource']}" } unless resource
      return { error: "Not authorized to query #{resource[:name]}" } unless authorized_to_read?(resource)

      limit = [args["limit"] || 25, 100].min
      q = args["q"] || {}

      relation = resource[:model].ransack(q).result
      records = authorization(resource).scope_collection(relation, Authorization::READ).limit(limit)
      { resource: resource[:name], count: records.size, records: filter_sensitive(records.as_json) }
    end

    def tool_update(args)
      resource = ResourceRegistry.find(args["resource"])
      return { error: "Resource not found: #{args['resource']}" } unless resource
      return { error: "id is required" } if args["id"].nil?

      attributes = args["attributes"] || {}
      return { error: "attributes are required" } if attributes.empty?

      RecordUpdater.new(resource: resource, current_user: @current_user)
                   .call(id: args["id"], attributes: attributes)
    end

    def authorized_to_read?(resource)
      authorization(resource).authorized?(Authorization::READ, resource[:model])
    end

    def authorization(resource)
      Authorization.for(resource[:config], @current_user)
    end

    def filter_sensitive(records)
      sensitive = ResourceRegistry.sensitive_attributes
      Array(records).map do |record|
        record.is_a?(Hash) ? record.except(*sensitive) : record
      end
    end

    def success(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
  end
end
