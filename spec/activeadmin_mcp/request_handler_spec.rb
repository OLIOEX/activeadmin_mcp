# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::RequestHandler do
  subject(:handler) { described_class.new }

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
      it "advertises the list_resources, query and update tools" do
        tools = handle("tools/list")[:result][:tools]

        expect(tools.map { |t| t[:name] }).to contain_exactly("list_resources", "query", "update")
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

    # A stand-in ActiveAdmin authorization adapter. `scope_collection` mirrors
    # the real adapters by returning the collection it is handed, so tests can
    # assert on the relation the handler builds.
    def adapter_class(authorized:)
      Class.new do
        define_method(:initialize) { |*| }
        define_method(:authorized?) { |*| authorized }
        def scope_collection(collection, *) = collection
      end
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

      it "delegates to the record updater with the resource and current user" do
        resource = { name: "User", model: double, config: double }
        allow(ActiveadminMcp::ResourceRegistry).to receive(:find).with("User").and_return(resource)
        updater = instance_double(ActiveadminMcp::RecordUpdater, call: { updated: [:name] })
        allow(ActiveadminMcp::RecordUpdater).to receive(:new).and_return(updater)

        handler = described_class.new(current_user: :admin)
        response = handler.handle(
          "id" => 1,
          "method" => "tools/call",
          "params" => {
            "name" => "update",
            "arguments" => { "resource" => "User", "id" => 7, "attributes" => { "name" => "x" } },
          },
        )
        result = JSON.parse(response[:result][:content].first[:text])

        expect(ActiveadminMcp::RecordUpdater).to have_received(:new)
          .with(resource: resource, current_user: :admin)
        expect(updater).to have_received(:call).with(id: 7, attributes: { "name" => "x" })
        expect(result).to eq("updated" => ["name"])
      end
    end

    describe "an unknown tool" do
      it "returns an error naming the tool" do
        expect(call_tool("frobnicate")).to eq("error" => "Unknown tool: frobnicate")
      end
    end
  end
end
