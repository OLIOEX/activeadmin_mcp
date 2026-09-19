RSpec.describe "the MCP tools" do
  let(:client) { E2E::McpClient.new(url: E2E::AppServer.instance.mcp_url, token: E2E.token) }

  describe "list_resources" do
    it "lists the registered resources with their attributes" do
      resources = client.call_tool("list_resources")["resources"]

      expect(resources.map { |resource| resource["name"] }).to include("Post", "Author")

      post = resources.find { |resource| resource["name"] == "Post" }
      expect(post["table"]).to eq("posts")
      expect(post["attributes"]).to include("title", "body", "slug")
    end

    it "omits sensitive attributes from the admin user" do
      resources = client.call_tool("list_resources")["resources"]
      admin_user = resources.find { |resource| resource["name"] == "AdminUser" }

      expect(admin_user["attributes"]).not_to include("encrypted_password")
      expect(admin_user["attributes"]).not_to include("reset_password_token")
    end
  end

  describe "query" do
    it "filters with Ransack syntax" do
      result = client.call_tool("query", resource: "Post", q: { title_cont: "Earthsea" })

      expect(result["count"]).to eq(1)
      expect(result["records"].first["title"]).to eq("A Wizard of Earthsea")
    end

    it "returns every record when no query is given" do
      result = client.call_tool("query", resource: "Post")

      expect(result["count"]).to eq(3)
    end

    it "honours the limit" do
      result = client.call_tool("query", resource: "Post", limit: 1)

      expect(result["count"]).to eq(1)
      expect(result["records"].length).to eq(1)
    end

    # No example asserts the documented 100-record cap (README: "capped at
    # 100"). With only three Posts seeded, any assertion on the result of a
    # limit above 100 (count, records.length, or absence of an error) would
    # be identical whether the clamp fired or not, so it would pass whether
    # or not the clamp exists - see the final-fix-report for the fuller
    # reasoning. Demonstrating the clamp for real needs >100 seeded records,
    # which is a real cost (seed script size, migrate/seed time on every
    # run) we're not paying just for this.

    it "reports an unregistered resource rather than raising" do
      result = client.call_tool("query", resource: "Nonexistent")

      expect(result["error"]).to eq("Resource not found: Nonexistent")
    end
  end

  describe "create" do
    def posts
      client.call_tool("query", resource: "Post")["records"]
    end

    it "creates a record through the resource's own ActiveAdmin create action, so its callbacks run" do
      result = client.call_tool("create", resource: "Post", attributes: { title: "Mort", body: "The fourth." })

      expect(result["error"]).to be_nil
      expect(result["created"]).to contain_exactly("title", "body")

      created = client.call_tool("query", resource: "Post", q: { id_eq: result["id"] })["records"].first
      expect(created["title"]).to eq("Mort")
      expect(created["slug"]).to eq("mort")
    end

    it "drops an attribute the resource's permitted params do not accept" do
      result = client.call_tool(
        "create",
        resource: "Post",
        attributes: { title: "Mort", slug: "tampered" }
      )

      expect(result["created"]).to eq(["title"])

      created = client.call_tool("query", resource: "Post", q: { id_eq: result["id"] })["records"].first
      expect(created["slug"]).to eq("mort")
    end

    it "reports the model's validation messages and creates nothing when the new record is rejected" do
      result = client.call_tool("create", resource: "Post", attributes: { title: "", body: "No title." })

      expect(result["error"]).to match(/validation/i)
      expect(result["details"]).to include("Title can't be blank")
      expect(posts.length).to eq(3)
    end

    it "refuses to create a record for a resource registered without the create action" do
      result = client.call_tool("create", resource: "Author", attributes: { name: "Iain" })

      expect(result["error"]).to eq("Resource is not creatable: Author")
      expect(client.call_tool("query", resource: "Author")["count"]).to eq(2)
    end

    it "refuses to create a record for a resource that declares no permitted params" do
      result = client.call_tool("create", resource: "Tag", attributes: { name: "science-fiction" })

      expect(result["error"]).to match(/permit_params/)

      tags = client.call_tool("query", resource: "Tag")["records"]
      expect(tags.map { |tag| tag["name"] }).to eq(["fantasy"])
    end
  end

  describe "update" do
    let(:post_id) do
      client.call_tool("query", resource: "Post", q: { slug_eq: "small-gods" })["records"].first["id"]
    end

    it "updates a permitted attribute and persists it" do
      result = client.call_tool("update", resource: "Post", id: post_id, attributes: { title: "Pyramids" })

      expect(result["error"]).to be_nil
      expect(result["updated"]).to eq(["title"])

      reread = client.call_tool("query", resource: "Post", q: { id_eq: post_id })["records"].first
      expect(reread["title"]).to eq("Pyramids")
    end

    it "drops an attribute the resource does not permit" do
      result = client.call_tool(
        "update",
        resource: "Post",
        id: post_id,
        attributes: { title: "Hogfather", slug: "tampered" }
      )

      expect(result["updated"]).to eq(["title"])

      reread = client.call_tool("query", resource: "Post", q: { id_eq: post_id })["records"].first
      expect(reread["title"]).to eq("Hogfather")
      expect(reread["slug"]).to eq("small-gods")
    end

    it "updates through the resource's own ActiveAdmin update action, so its callbacks run" do
      client.call_tool("update", resource: "Post", id: post_id, attributes: { title: "Pyramids" })

      reread = client.call_tool("query", resource: "Post", q: { id_eq: post_id })["records"].first
      expect(reread["body"]).to eq("Unrelated. (revised)")
    end

    it "reports the model's validation messages and leaves the record alone when the change is rejected" do
      result = client.call_tool("update", resource: "Post", id: post_id, attributes: { title: "" })

      expect(result["error"]).to match(/validation/i)
      expect(result["details"]).to include("Title can't be blank")

      reread = client.call_tool("query", resource: "Post", q: { id_eq: post_id })["records"].first
      expect(reread["title"]).to eq("Small Gods")
    end

    it "refuses to update a resource that declares no permitted params" do
      tag_id = client.call_tool("query", resource: "Tag")["records"].first["id"]

      result = client.call_tool("update", resource: "Tag", id: tag_id, attributes: { name: "tampered" })

      expect(result["error"]).to match(/permit_params/)

      reread = client.call_tool("query", resource: "Tag", q: { id_eq: tag_id })["records"].first
      expect(reread["name"]).to eq("fantasy")
    end

    it "refuses a resource that does not register the update action" do
      author_id = client.call_tool("query", resource: "Author", q: { name_eq: "Terry" })["records"].first["id"]

      result = client.call_tool("update", resource: "Author", id: author_id, attributes: { name: "Terence" })

      expect(result["error"]).to eq("Resource is not editable: Author")
    end

    it "reports a missing record rather than raising" do
      result = client.call_tool("update", resource: "Post", id: 999_999, attributes: { title: "Nope" })

      expect(result["error"]).to eq("Record not found: Post#999999")
    end
  end
end
