# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveAdminMcp::RequestHandler do
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
        expect(result[:serverInfo]).to eq(name: "active-admin-mcp", version: ActiveAdminMcp::VERSION)
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
      it "advertises the list_resources and query tools" do
        tools = handle("tools/list")[:result][:tools]

        expect(tools.map { |t| t[:name] }).to contain_exactly("list_resources", "query")
      end

      it "marks resource as required on the query tool" do
        tools = handle("tools/list")[:result][:tools]
        query = tools.find { |t| t[:name] == "query" }

        expect(query[:inputSchema][:required]).to eq(["resource"])
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

    describe "list_resources" do
      it "returns the registry's resources" do
        resources = [{ name: "User", table: "users", attributes: %w[id email] }]
        allow(ActiveAdminMcp::ResourceRegistry).to receive(:all).and_return(resources)

        expect(call_tool("list_resources")).to eq("resources" => [
          { "name" => "User", "table" => "users", "attributes" => %w[id email] },
        ])
      end
    end

    describe "query" do
      let(:records) { [{ "id" => 1, "name" => "john" }] }
      let(:relation) { double("relation", limit: records) }
      let(:model) { double("model") }

      before do
        allow(records).to receive(:as_json).and_return(records)
        allow(records).to receive(:size).and_return(records.length)
        allow(model).to receive(:ransack).and_return(double("search", result: relation))
        allow(ActiveAdminMcp::ResourceRegistry).to receive(:find)
          .with("User").and_return(name: "User", model: model)
      end

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

      it "returns an error when the resource is not found" do
        allow(ActiveAdminMcp::ResourceRegistry).to receive(:find).with("Ghost").and_return(nil)

        expect(call_tool("query", "resource" => "Ghost"))
          .to eq("error" => "Resource not found: Ghost")
      end
    end

    describe "an unknown tool" do
      it "returns an error naming the tool" do
        expect(call_tool("frobnicate")).to eq("error" => "Unknown tool: frobnicate")
      end
    end
  end
end
