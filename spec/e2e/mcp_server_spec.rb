RSpec.describe "the MCP server" do
  let(:url) { E2E::AppServer.instance.mcp_url }
  let(:client) { E2E::McpClient.new(url: url, token: E2E.token) }

  describe "the handshake" do
    it "reports the protocol version and server info" do
      result = client.initialize_session

      expect(result["protocolVersion"]).to eq("2025-06-18")
      expect(result["serverInfo"]["name"]).to eq("activeadmin-mcp")
      expect(result["serverInfo"]["version"]).to eq(ActiveadminMcp::VERSION)
      expect(result["capabilities"]).to have_key("tools")
    end

    it "advertises the three tools" do
      names = client.tools_list["tools"].map { |tool| tool["name"] }

      expect(names).to contain_exactly("list_resources", "query", "update")
    end
  end

  describe "authentication" do
    it "rejects a request with no token" do
      response = E2E::McpClient.new(url: url).post("initialize")

      expect(response.code).to eq("401")
      expect(JSON.parse(response.body).dig("error", "code")).to eq(-32_000)
    end

    it "rejects a request with an unrecognised token" do
      response = E2E::McpClient.new(url: url, token: "aamcp_not_a_real_token").post("initialize")

      expect(response.code).to eq("401")
      expect(JSON.parse(response.body).dig("error", "code")).to eq(-32_000)
    end

    it "accepts a request with the minted token" do
      expect(client.post("initialize").code).to eq("200")
    end
  end
end
