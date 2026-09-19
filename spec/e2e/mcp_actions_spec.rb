RSpec.describe "MCP actions declared with an mcp: option" do
  let(:client) { E2E::McpClient.new(url: E2E::AppServer.instance.mcp_url, token: E2E.token) }

  def post_status(slug)
    client.call_tool("query", resource: "Post", q: { slug_eq: slug })["records"].first["status"]
  end

  def post_id(slug)
    client.call_tool("query", resource: "Post", q: { slug_eq: slug })["records"].first["id"]
  end

  describe "tools/list" do
    it "advertises a member_action opted in with an mcp: key as its own tool, with its declared params in the input schema" do
      tools = client.tools_list["tools"]
      publish = tools.find { |tool| tool["name"] == "post_publish" }

      expect(publish).not_to be_nil
      expect(publish["inputSchema"]["properties"]).to include("visibility")
      expect(publish["inputSchema"]["properties"]["visibility"]["enum"]).to eq(%w[public unlisted])
      expect(publish["inputSchema"]["required"]).to include("visibility")
    end

    it "does not advertise a member_action registered without an mcp: key, proving MCP exposure is opt-in" do
      tools = client.tools_list["tools"]

      expect(tools.map { |tool| tool["name"] }).not_to include("post_archive")
    end

    it "advertises a collection_action whose zero-argument permission: proc calls current_admin_user, proving the proc is evaluated in controller context at listing time rather than raised as a bare NameError that would hide the tool" do
      tools = client.tools_list["tools"]

      expect(tools.map { |tool| tool["name"] }).to include("post_purge_drafts")
    end
  end

  describe "calling an opted-in member action" do
    it "runs the action against the real controller, so the change is visible on a subsequent query" do
      id = post_id("small-gods")

      result = client.call_tool("post_publish", id: id, visibility: "public")

      expect(result["error"]).to be_nil
      expect(post_status("small-gods")).to eq("public")
    end

    it "refuses a value outside a static enum: before dispatch, and leaves the record's status unchanged" do
      id = post_id("small-gods")

      result = client.call_tool("post_publish", id: id, visibility: "top-secret")

      expect(result["error"]).to match(/visibility/)
      expect(post_status("small-gods")).to eq("draft")
    end

    it "refuses a call omitting a required param before dispatch, and leaves the record's status unchanged" do
      id = post_id("small-gods")

      result = client.call_tool("post_publish", id: id)

      expect(result["error"]).to match(/visibility/)
      expect(post_status("small-gods")).to eq("draft")
    end
  end

  describe "calling an action that was never opted in" do
    # Absence from tools/list is not by itself a guarantee: a tool that were
    # merely hidden but still dispatchable by name would be a hole, not a
    # nicety. This asserts the call side of the opt-in promise.
    it "refuses a member_action registered without an mcp: key as an unknown tool, and leaves the record untouched" do
      result = client.call_tool("post_archive", id: post_id("small-gods"))

      expect(result["error"]).to eq("Unknown tool: post_archive")
      expect(post_status("small-gods")).to eq("draft")
    end
  end

  describe "calling an opted-in batch action" do
    it "applies to exactly the selected records, leaving an unselected record untouched" do
      selected_id = post_id("a-wizard-of-earthsea")
      other_id = post_id("the-tombs-of-atuan")

      result = client.call_tool("post_set_status", ids: [selected_id], status: "archived")

      expect(result["error"]).to be_nil
      expect(post_status("a-wizard-of-earthsea")).to eq("archived")
      expect(post_status("the-tombs-of-atuan")).to eq("draft")
    end
  end
end
