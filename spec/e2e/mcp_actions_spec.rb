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

      it "is refused as an unknown tool when it carries no mcp: key, and leaves the record untouched, since being absent from tools/list would not on its own stop it being dispatched by name" do
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

      it "allows the call once the record satisfies the proc, proving the proc is consulted per record rather than refusing unconditionally as a proc hardcoded to refuse would also do" do
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
  # The driving case for mcp_action: actions a shared concern declares, which
  # cannot carry an mcp: key of their own without describing every resource
  # that includes the concern identically.
  describe "an action declared in a shared concern and annotated with mcp_action" do
    describe "in tools/list" do
      it "is advertised under the tool name the annotation chose" do
        expect(tool_names).to include("post_flag", "post_unflag", "post_bulk_flag")
      end

      it "is not advertised for a resource that includes the same concern but annotates nothing, so exposure stays per resource" do
        expect(tool_names.grep(/\Areview_/)).to be_empty
      end

      it "inherits the param types of a batch action whose form: is a proc, by evaluating it as ActiveAdmin does" do
        properties = tool("post_bulk_flag")["inputSchema"]["properties"]

        expect(properties["reason"]["type"]).to eq("string")
        expect(properties["notify"]["type"]).to eq("boolean")
      end
    end

    describe "when called" do
      it "runs the member action against the real controller" do
        client.call_tool("post_flag", id: post_id("small-gods"), reason: "discworld")

        expect(post_status("small-gods")).to eq("flagged:discworld")
      end

      # Both tools dispatch the same action; only the verb differs, and the
      # action's own body branches on it. Without the annotation choosing one,
      # only the first verb ActiveAdmin recorded would ever be reachable.
      it "dispatches the verb the annotation chose, reaching the other branch of the same action" do
        client.call_tool("post_unflag", id: post_id("small-gods"))

        expect(post_status("small-gods")).to eq("unflagged")
      end

      it "runs a collection action the concern declared" do
        client.call_tool("post_flag", id: post_id("small-gods"), reason: "discworld")

        result = client.call_tool("post_clear_flags")

        expect(result["error"]).to be_nil
        expect(post_status("small-gods")).to eq("draft")
      end

      it "tells the batch action of the same name apart from the member one, and applies it to exactly the selected records" do
        result = client.call_tool(
          "post_bulk_flag",
          ids: [post_id("a-wizard-of-earthsea"), post_id("the-tombs-of-atuan")],
          reason: "earthsea"
        )

        expect(result["error"]).to be_nil
        expect(post_status("a-wizard-of-earthsea")).to eq("flagged:earthsea")
        expect(post_status("the-tombs-of-atuan")).to eq("flagged:earthsea")
        expect(post_status("small-gods")).to eq("draft")
      end
    end

    # ActiveAdmin lets a batch action be titled with a String and derives its
    # symbol by mangling that title, which leaves punctuation in the symbol.
    # Applications generate these in loops from data, so the annotation names
    # the title it wrote rather than the symbol ActiveAdmin made of it.
    describe "a batch action generated in a loop and titled with a String" do
      it "is advertised under a tool name derived from the mangled symbol, with the punctuation removed" do
        expect(tool_names).to include("post_warning_fridge_left_open", "post_warning_past_use_by_date")
      end

      it "runs the action the title named, and no other of the same family" do
        result = client.call_tool("post_warning_fridge_left_open", ids: [post_id("small-gods")])

        expect(result["error"]).to be_nil
        expect(post_status("small-gods")).to eq("warned:Fridge left open")
        expect(post_status("a-wizard-of-earthsea")).to eq("draft")
      end
    end

    # ActiveAdmin hides a batch action whose :if proc refuses, but consults the
    # proc only when rendering — a dispatched request reaches the action
    # regardless. The seeded admin is not the superuser the proc asks for.
    describe "a batch action ActiveAdmin hides behind an :if proc" do
      it "is not advertised, because the admin UI would not offer it either" do
        expect(tool_names).not_to include("post_purge")
      end

      it "refuses the call as well, so MCP is not the way round the gate, and deletes nothing" do
        before_count = client.call_tool("query", resource: "Post")["count"]

        result = client.call_tool("post_purge", ids: [post_id("small-gods")])

        expect(result["error"]).to match(/not available/i)
        expect(client.call_tool("query", resource: "Post")["count"]).to eq(before_count)
      end
    end

    # The concern guards the batch dispatch with a controller before_action.
    # Dispatching through the real controller is what makes that still apply.
    it "is stopped by a before_action the concern declared, and leaves the records unchanged" do
      result = client.call_tool("post_guarded_flag", ids: [post_id("small-gods")])

      expect(result["flash"]&.values&.join).to match(/before_action/i)
      expect(post_status("small-gods")).to eq("draft")
    end
  end
end
