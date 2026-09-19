RSpec.describe "MCP actions declared with an mcp: option" do
  let(:client) { E2E::McpClient.new(url: E2E::AppServer.instance.mcp_url, token: E2E.token) }

  def tool_names
    client.tools_list["tools"].map { |tool| tool["name"] }
  end

  def tool(name)
    client.tools_list["tools"].find { |candidate| candidate["name"] == name }
  end

  def post_status(slug)
    client.call_tool("query", resource: "Post", q: { slug_eq: slug })["records"].first["status"]
  end

  def post_id(slug)
    client.call_tool("query", resource: "Post", q: { slug_eq: slug })["records"].first["id"]
  end

  describe "a member_action" do
    describe "in tools/list" do
      it "is advertised as its own tool, with its declared params in the input schema" do
        publish = tool("post_publish")

        expect(publish).not_to be_nil
        expect(publish["inputSchema"]["properties"]).to include("visibility")
        expect(publish["inputSchema"]["properties"]["visibility"]["enum"]).to eq(%w[public unlisted])
        expect(publish["inputSchema"]["required"]).to include("visibility")
      end

      it "is not advertised when it carries no mcp: key, proving MCP exposure is opt-in" do
        expect(tool_names).not_to include("post_archive")
      end
    end

    describe "when called" do
      it "runs against the real ActiveAdmin controller, so the change is visible on a subsequent query" do
        id = post_id("small-gods")

        result = client.call_tool("post_publish", id: id, visibility: "public")

        expect(result["error"]).to be_nil
        expect(post_status("small-gods")).to eq("public")
      end

      it "refuses a value outside a param's static enum: before dispatch, and leaves the record's status unchanged" do
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

      # Absence from tools/list is not by itself a guarantee: a tool that were
      # merely hidden but still dispatchable by name would be a hole, not an
      # untidiness. This asserts the call side of the opt-in promise.
      it "is refused as an unknown tool when it carries no mcp: key, and leaves the record untouched" do
        result = client.call_tool("post_archive", id: post_id("small-gods"))

        expect(result["error"]).to eq("Unknown tool: post_archive")
        expect(post_status("small-gods")).to eq("draft")
      end

      it "reports a generic failure naming the resource and action when its body raises, keeping the exception's own message away from the client where it could disclose SQL, table names or file paths" do
        result = client.call_tool("post_explode", id: post_id("small-gods"))

        expect(result["error"]).to eq("Post#explode failed")
        expect(result["error"]).not_to include("classified_dossier")
        expect(result["error"]).not_to match(/SQLite3|no such table|StatementInvalid/)
      end
    end

    describe "guarded by a permission: proc that takes the record" do
      it "is still advertised, because a proc needing a record cannot be resolved at tools/list time and must refuse at call time instead" do
        expect(tool_names).to include("post_feature")
      end

      it "refuses the call with the string the proc returned as the reason, and leaves the record unchanged" do
        result = client.call_tool("post_feature", id: post_id("small-gods"))

        expect(result["error"]).to eq("Only a published post can be featured")
        expect(post_status("small-gods")).to eq("draft")
      end

      # Without this, a proc hardcoded to refuse everything would satisfy the
      # example above: the refusal has to be shown to depend on the record.
      it "allows the call once the record satisfies the proc, proving the proc is consulted per record rather than refusing unconditionally" do
        id = post_id("small-gods")
        client.call_tool("post_publish", id: id, visibility: "public")

        result = client.call_tool("post_feature", id: id)

        expect(result["error"]).to be_nil
        expect(post_status("small-gods")).to eq("featured")
      end
    end
  end

  describe "a collection_action" do
    describe "in tools/list" do
      it "is advertised when its zero-argument permission: proc calls current_admin_user, proving the proc is evaluated in controller context at listing time rather than raising NameError and silently hiding the tool" do
        expect(tool_names).to include("post_purge_drafts")
      end
    end
  end

  describe "a batch_action" do
    describe "in tools/list" do
      it "is advertised with an ids array, and with its param types taken from the action's ActiveAdmin form: hash rather than from the mcp: declaration" do
        set_status = tool("post_set_status")

        expect(set_status).not_to be_nil
        expect(set_status["inputSchema"]["properties"]["ids"]["type"]).to eq("array")
        expect(set_status["inputSchema"]["required"]).to include("ids")
        expect(set_status["inputSchema"]["properties"]["status"]["type"]).to eq("string")
      end
    end

    describe "when called" do
      it "applies to exactly the selected records, leaving an unselected record untouched" do
        selected_id = post_id("a-wizard-of-earthsea")

        result = client.call_tool("post_set_status", ids: [selected_id], status: "archived")

        expect(result["error"]).to be_nil
        expect(post_status("a-wizard-of-earthsea")).to eq("archived")
        expect(post_status("the-tombs-of-atuan")).to eq("draft")
      end
    end
  end
end
