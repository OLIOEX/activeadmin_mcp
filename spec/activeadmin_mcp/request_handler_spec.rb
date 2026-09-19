require "spec_helper"
require "support/active_admin"

RSpec.describe ActiveadminMcp::RequestHandler do
  subject(:handler) { described_class.new }

  # A stand-in ActiveAdmin authorization adapter. `scope_collection` mirrors
  # the real adapters by returning the collection it is handed, so tests can
  # assert on the relation the handler builds. `calls` records every
  # authorized? call, so a test can assert on the subject that was checked.
  def adapter_class(authorized:, calls: [])
    Class.new do
      define_method(:initialize) { |*| }
      define_method(:authorized?) do |action, subject = nil|
        calls << [action, subject]
        authorized
      end
      def scope_collection(collection, *) = collection
    end
  end

  def handle(method, params = nil, id: 1)
    request = { "id" => id, "method" => method }
    request["params"] = params if params
    handler.handle(request)
  end

  describe "#handle" do
    describe "initialize" do
      it "returns the protocol version, server info and capabilities" do
        result = handle("initialize")[:result]

        expect(result[:protocolVersion]).to eq(described_class::PROTOCOL_VERSION)
        expect(result[:serverInfo]).to eq(name: "activeadmin-mcp", version: ActiveadminMcp::VERSION)
        expect(result[:capabilities]).to eq(tools: {})
      end

      it "echoes the request id and jsonrpc version" do
        response = handle("initialize", id: 42)

        expect(response[:jsonrpc]).to eq("2.0")
        expect(response[:id]).to eq(42)
      end
    end

    describe "notifications/initialized" do
      it "returns nil so the controller sends no content" do
        expect(handle("notifications/initialized")).to be_nil
      end
    end

    describe "ping" do
      it "returns an empty result" do
        expect(handle("ping")[:result]).to eq({})
      end
    end

    describe "tools/list" do
      before { allow(ActiveadminMcp::ActionCatalog).to receive(:all).and_return([]) }

      it "advertises the list_resources, query, create, update and describe_form tools" do
        tools = handle("tools/list")[:result][:tools]

        expect(tools.map { |t| t[:name] })
          .to contain_exactly("list_resources", "query", "create", "update", "describe_form")
      end

      it "marks resource as required on the query tool" do
        tools = handle("tools/list")[:result][:tools]
        query = tools.find { |t| t[:name] == "query" }

        expect(query[:inputSchema][:required]).to eq(["resource"])
      end

      it "requires resource, id and attributes on the update tool" do
        tools = handle("tools/list")[:result][:tools]
        update = tools.find { |t| t[:name] == "update" }

        expect(update[:inputSchema][:required]).to contain_exactly("resource", "id", "attributes")
      end

      it "requires only resource on the describe_form tool, since the action defaults" do
        tools = handle("tools/list")[:result][:tools]
        describe_form = tools.find { |t| t[:name] == "describe_form" }

        expect(describe_form[:inputSchema][:required]).to eq(["resource"])
        expect(describe_form[:inputSchema][:properties][:action][:enum]).to eq(%w[new edit])
      end

      it "requires resource and attributes on the create tool" do
        tools = handle("tools/list")[:result][:tools]
        create = tools.find { |t| t[:name] == "create" }

        expect(create[:inputSchema][:required]).to contain_exactly("resource", "attributes")
      end
    end

    describe "unknown method" do
      it "returns a -32601 Method not found error" do
        response = handle("does/not/exist")

        expect(response[:error][:code]).to eq(-32_601)
        expect(response[:error][:message]).to eq("Method not found: does/not/exist")
      end
    end
  end

  describe "tools/call" do
    def call_tool(name, arguments = {})
      response = handle("tools/call", { "name" => name, "arguments" => arguments })
      text = response[:result][:content].first[:text]
      JSON.parse(text)
    end

    def call_tool_as(current_user, name, arguments = {})
      response = described_class.new(current_user: current_user).handle(
        "id" => 1,
        "method" => "tools/call",
        "params" => { "name" => name, "arguments" => arguments },
      )
      JSON.parse(response[:result][:content].first[:text])
    end

    def resource_config(authorized: true)
      namespace = double("namespace", authorization_adapter: adapter_class(authorized: authorized))
      double("config", namespace: namespace)
    end

    describe "list_resources" do
      it "returns info only for resources the user is authorized to read" do
        readable = { name: "User", model: double, config: resource_config(authorized: true) }
        hidden = { name: "Secret", model: double, config: resource_config(authorized: false) }
        allow(ActiveadminMcp::ResourceRegistry).to receive(:resources).and_return([readable, hidden])
        allow(ActiveadminMcp::ResourceRegistry).to receive(:resource_info).with(readable)
          .and_return(name: "User", table: "users", attributes: %w[id email])

        expect(call_tool("list_resources")).to eq("resources" => [
          { "name" => "User", "table" => "users", "attributes" => %w[id email] },
        ])
      end
    end

    describe "query" do
      let(:records) { [{ "id" => 1, "name" => "john" }] }
      let(:relation) { double("relation", limit: records) }
      let(:model) { double("model") }

      def stub_resource(authorized: true)
        allow(records).to receive(:as_json).and_return(records)
        allow(records).to receive(:size).and_return(records.length)
        allow(model).to receive(:ransack).and_return(double("search", result: relation))
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find)
          .with("User").and_return(name: "User", model: model, config: resource_config(authorized: authorized))
      end

      before { stub_resource }

      it "returns matching records with a count" do
        result = call_tool("query", "resource" => "User", "q" => { "name_cont" => "john" })

        expect(result).to eq("resource" => "User", "count" => 1, "records" => records)
      end

      it "defaults the limit to 25 when none is given" do
        expect(relation).to receive(:limit).with(25).and_return(records)
        call_tool("query", "resource" => "User")
      end

      it "caps the limit at 100" do
        expect(relation).to receive(:limit).with(100).and_return(records)
        call_tool("query", "resource" => "User", "limit" => 500)
      end

      it "passes an empty Ransack query when none is provided" do
        expect(model).to receive(:ransack).with({}).and_return(double("search", result: relation))
        call_tool("query", "resource" => "User")
      end

      it "scopes the relation through the authorization adapter before limiting" do
        scoped = double("scoped relation")
        authorization = instance_double(ActiveadminMcp::Authorization)
        allow(ActiveadminMcp::Authorization).to receive(:for).and_return(authorization)
        allow(authorization).to receive(:authorized?).and_return(true)
        expect(authorization).to receive(:scope_collection).with(relation, :read).and_return(scoped)
        expect(scoped).to receive(:limit).with(25).and_return(records)

        call_tool("query", "resource" => "User")
      end

      it "returns an authorization error when the user cannot read the resource" do
        stub_resource(authorized: false)

        expect(call_tool("query", "resource" => "User"))
          .to eq("error" => "Not authorized to query User")
      end

      it "strips sensitive attributes from the returned records" do
        leaky = [{ "id" => 1, "email" => "a@b.com", "encrypted_password" => "x", "api_key" => "y" }]
        allow(leaky).to receive(:as_json).and_return(leaky)
        allow(leaky).to receive(:size).and_return(1)
        allow(relation).to receive(:limit).and_return(leaky)

        result = call_tool("query", "resource" => "User")

        expect(result["records"]).to eq([{ "id" => 1, "email" => "a@b.com" }])
      end

      it "returns an error when the resource is not found" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("Ghost").and_return(nil)

        expect(call_tool("query", "resource" => "Ghost"))
          .to eq("error" => "Resource not found: Ghost")
      end
    end

    describe "update" do
      it "returns an error when the resource is not found" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("Ghost").and_return(nil)

        expect(call_tool("update", "resource" => "Ghost", "id" => 1, "attributes" => { "name" => "x" }))
          .to eq("error" => "Resource not found: Ghost")
      end

      it "returns an error when no id is given" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find)
          .with("User").and_return(name: "User", model: double, config: double)

        expect(call_tool("update", "resource" => "User", "attributes" => { "name" => "x" }))
          .to eq("error" => "id is required")
      end

      it "returns an error when no attributes are given" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find)
          .with("User").and_return(name: "User", model: double, config: double)

        expect(call_tool("update", "resource" => "User", "id" => 1))
          .to eq("error" => "attributes are required")
      end

      it "delegates to the record writer with the resource and current user" do
        resource = { name: "User", model: double, config: double }
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("User").and_return(resource)
        writer = instance_double(ActiveadminMcp::RecordWriter, update: { updated: [:name] })
        allow(ActiveadminMcp::RecordWriter).to receive(:new).and_return(writer)

        result = call_tool_as(:admin, "update", "resource" => "User", "id" => 7, "attributes" => { "name" => "x" })

        expect(ActiveadminMcp::RecordWriter).to have_received(:new)
          .with(resource: resource, current_user: :admin)
        expect(writer).to have_received(:update).with(id: 7, attributes: { "name" => "x" })
        expect(result).to eq("updated" => ["name"])
      end
    end

    describe "create" do
      it "returns an error when the resource is not found" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("Ghost").and_return(nil)

        expect(call_tool("create", "resource" => "Ghost", "attributes" => { "name" => "x" }))
          .to eq("error" => "Resource not found: Ghost")
      end

      it "returns an error when no attributes are given" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find)
          .with("User").and_return(name: "User", model: double, config: double)

        expect(call_tool("create", "resource" => "User"))
          .to eq("error" => "attributes are required")
      end

      it "delegates to the record writer with the resource and current user" do
        resource = { name: "User", model: double, config: double }
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("User").and_return(resource)
        writer = instance_double(ActiveadminMcp::RecordWriter, create: { id: 7 })
        allow(ActiveadminMcp::RecordWriter).to receive(:new).and_return(writer)

        result = call_tool_as(:admin, "create", "resource" => "User", "attributes" => { "name" => "x" })

        expect(ActiveadminMcp::RecordWriter).to have_received(:new)
          .with(resource: resource, current_user: :admin)
        expect(writer).to have_received(:create).with(attributes: { "name" => "x" })
        expect(result).to eq("id" => 7)
      end
    end

    describe "describe_form" do
      it "returns an error when the resource is not found" do
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("Ghost").and_return(nil)

        expect(call_tool("describe_form", "resource" => "Ghost"))
          .to eq("error" => "Resource not found: Ghost")
      end

      it "delegates to the form description with the resource and current user" do
        resource = { name: "User", model: double, config: double }
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("User").and_return(resource)
        description = instance_double(ActiveadminMcp::FormDescription, call: { source: "form" })
        allow(ActiveadminMcp::FormDescription).to receive(:new).and_return(description)

        result = call_tool_as(:admin, "describe_form", "resource" => "User", "action" => "edit")

        expect(ActiveadminMcp::FormDescription).to have_received(:new)
          .with(resource: resource, current_user: :admin)
        expect(description).to have_received(:call).with(action: "edit")
        expect(result).to eq("source" => "form")
      end

      it "describes the new form when no action is given" do
        resource = { name: "User", model: double, config: double }
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("User").and_return(resource)
        description = instance_double(ActiveadminMcp::FormDescription, call: {})
        allow(ActiveadminMcp::FormDescription).to receive(:new).and_return(description)

        call_tool("describe_form", "resource" => "User")

        expect(description).to have_received(:call).with(action: "new")
      end
    end

    describe "an unknown tool" do
      it "returns an error naming the tool" do
        expect(call_tool("frobnicate")).to eq("error" => "Unknown tool: frobnicate")
      end
    end
  end

  describe "action tools" do
    let(:resource_class) { Class.new }

    def definition(tool_name: "volunteer_create_warning", permission: nil, display_if: nil,
                   params: { reason: { type: :string, required: true } },
                   adapter: adapter_class(authorized: true))
      namespace = double("namespace", authorization_adapter: adapter)
      double(
        "definition",
        tool_name: tool_name,
        description: "Record a warning",
        kind: :member,
        params: params,
        permission: permission,
        display_if: display_if,
        action_name: :create_warning,
        resource_name: "Volunteer",
        config: double("config", namespace: namespace, resource_class: resource_class)
      )
    end

    def handle(request, current_user: :admin)
      ActiveadminMcp::RequestHandler.new(current_user: current_user).handle(request)
    end

    def tool_names(definitions, current_user: :admin)
      allow(ActiveadminMcp::ActionCatalog).to receive(:all).and_return(Array(definitions))
      allow(ActiveadminMcp::ResourceRegistry).to receive(:resources).and_return([])

      handle({ "id" => 1, "method" => "tools/list" }, current_user: current_user)[:result][:tools]
        .map { |tool| tool[:name] }
    end

    it "lists opted-in actions alongside the built-in tools" do
      allow(ActiveadminMcp::ActionCatalog).to receive(:all).and_return([definition])
      allow(ActiveadminMcp::ResourceRegistry).to receive(:resources).and_return([])

      response = handle({ "id" => 1, "method" => "tools/list" })
      names = response[:result][:tools].map { |tool| tool[:name] }

      expect(names).to include("volunteer_create_warning")
      tool = response[:result][:tools].find { |t| t[:name] == "volunteer_create_warning" }
      expect(tool[:description]).to eq("Record a warning")
      expect(tool[:inputSchema][:required]).to include("id", "reason")
    end

    it "routes a call to the action runner" do
      target = definition
      allow(ActiveadminMcp::ActionCatalog).to receive(:find)
        .with("volunteer_create_warning", current_user: :admin).and_return(target)

      runner = instance_double(ActiveadminMcp::ActionRunner, call: { status: 302 })
      allow(ActiveadminMcp::ActionRunner).to receive(:new)
        .with(definition: target, current_user: :admin).and_return(runner)

      response = handle({
        "id" => 2, "method" => "tools/call",
        "params" => { "name" => "volunteer_create_warning",
                      "arguments" => { "id" => "1", "reason" => "Late" } }
      })

      expect(runner).to have_received(:call).with({ "id" => "1", "reason" => "Late" })
      expect(response[:result][:content].first[:text]).to include("302")
    end

    it "reports an unknown tool" do
      allow(ActiveadminMcp::ActionCatalog).to receive(:find).and_return(nil)

      response = handle({
        "id" => 3, "method" => "tools/call",
        "params" => { "name" => "nope", "arguments" => {} }
      })

      expect(response[:result][:content].first[:text]).to include("Unknown tool")
    end

    describe "authorization at listing time" do
      it "hides an action tool the authorization adapter refuses" do
        denied = definition(adapter: adapter_class(authorized: false))

        expect(tool_names(denied)).not_to include("volunteer_create_warning")
      end

      it "checks the resource class, since there is no record at listing time" do
        calls = []
        listed = definition(adapter: adapter_class(authorized: true, calls: calls))

        tool_names(listed)

        expect(calls).to eq([[:create_warning, resource_class]])
      end

      it "hides only the offending tool when an adapter raises" do
        exploding = Class.new do
          define_method(:initialize) { |*| }
          define_method(:authorized?) { |*| raise "adapter exploded" }
        end
        boom = definition(tool_name: "volunteer_boom", adapter: exploding)
        allow_any_instance_of(described_class).to receive(:warn)

        names = tool_names([boom, definition])

        expect(names).not_to include("volunteer_boom")
        expect(names).to include("volunteer_create_warning")
      end

      # The schema is what runs the application's `suggestions:` procs, so it
      # must never be built for a tool the user is not authorized for. Filtering
      # an assembled list would be too late: the proc would already have read
      # the database and handed its rows over.
      it "never runs a suggestions proc for a user the adapter refuses" do
        ran = false
        suggestions = -> { ran = true; %w[secret-category] }
        denied = definition(
          adapter: adapter_class(authorized: false),
          params: { category: { type: :string, suggestions: suggestions } }
        )

        names = tool_names(denied)

        # Asserted first, deliberately: filtering the assembled list would hide
        # the tool and still leak, so the proc not running is the real property.
        expect(ran).to be(false)
        expect(names).not_to include("volunteer_create_warning")
      end

      it "does run a suggestions proc for an authorized user" do
        ran = false
        suggestions = -> { ran = true; %w[visible-category] }
        allowed = definition(params: { category: { type: :string, suggestions: suggestions } })

        expect(tool_names(allowed)).to include("volunteer_create_warning")
        expect(ran).to be(true)
      end
    end

    # These need the real ActiveAdmin harness: the point of the fix is that the
    # proc is instance_exec'd against a real controller, which no double can
    # stand in for.
    describe "a permission proc at listing time" do
      let(:admin) { AdminUser.create!(email: "admin@example.com") }

      after { AdminUser.delete_all }

      def catalog_definition(action_name, kind)
        ActiveadminMcp::ActionCatalog.all.find do |d|
          d.action_name == action_name && d.kind == kind
        end
      end

      let(:export) { catalog_definition(:export, :collection) }

      it "evaluates a zero-arity proc in controller context" do
        seen = nil
        allow(export).to receive(:permission).and_return(-> { seen = current_active_admin_user; true })

        names = tool_names(export, current_user: admin)

        expect(seen).to eq(admin)
        expect(names).to include("volunteer_export")
      end

      it "hides the tool when a controller-context proc refuses" do
        allow(export).to receive(:permission).and_return(-> { current_active_admin_user.nil? })

        expect(tool_names(export, current_user: admin)).not_to include("volunteer_export")
      end

      it "hides only the raising tool and keeps the rest of the listing" do
        allow(export).to receive(:permission).and_return(-> { raise "proc exploded" })
        allow_any_instance_of(described_class).to receive(:warn)

        names = tool_names([export, definition], current_user: admin)

        expect(names).not_to include("volunteer_export")
        expect(names).to include("volunteer_create_warning", "query")
      end

      it "leaves a member action's proc for call time" do
        warning = catalog_definition(:create_warning, :member)
        allow(warning).to receive(:permission).and_return(->(_record) { false })

        expect(tool_names(warning, current_user: admin)).to include("volunteer_create_warning")
      end
    end

    # ActiveAdmin consults a batch action's :if proc only when rendering the
    # UI, so listing one it refuses would offer a tool the admin itself will
    # not show.
    describe "a batch action guarded by ActiveAdmin's own :if proc" do
      let(:admin) { AdminUser.create!(email: "admin@example.com") }
      let(:superuser) { AdminUser.create!(email: "superuser@example.com") }

      after { AdminUser.delete_all }

      def purge_for(current_user)
        ActiveadminMcp::ActionCatalog.all(current_user: current_user)
                                     .find { |d| d.action_name == :purge && d.kind == :batch }
      end

      let(:purge) { purge_for(admin) }

      it "hides the tool from a user the proc refuses" do
        expect(tool_names(purge, current_user: admin)).not_to include("shift_purge")
      end

      it "lists the tool for a user the proc admits" do
        expect(tool_names(purge, current_user: superuser)).to include("shift_purge")
      end

      # Such a proc commonly reads request state — a filter from params — which
      # a listing has no way to supply.
      it "hides the tool, and says why, when the proc raises for want of a request it cannot have" do
        messages = []
        allow_any_instance_of(described_class).to receive(:warn) { |_, message| messages << message }
        allow(purge).to receive(:display_if).and_return(proc { params[:q][:type] == "x" })

        names = tool_names(purge, current_user: admin)

        expect(names).not_to include("shift_purge")
        expect(messages.join).to match(/if: proc/)
      end
    end
  end
end
