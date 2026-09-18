# frozen_string_literal: true

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
    end

    it "reports an unregistered resource rather than raising" do
      result = client.call_tool("query", resource: "Nonexistent")

      expect(result["error"]).to eq("Resource not found: Nonexistent")
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
