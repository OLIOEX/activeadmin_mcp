# Permits title and body but deliberately not slug, so the e2e suite can prove
# the MCP `update` tool drops attributes the admin form does not accept.
ActiveAdmin.register Post do
  permit_params :title, :body

  # Opted in via `mcp:`, with a required `visibility` param bound to a static
  # enum, so the e2e suite can prove an out-of-enum value is refused before
  # dispatch, and that a permitted value actually runs against the real
  # controller.
  member_action :publish, method: :post, mcp: {
    description: "Publish a post with the given visibility",
    params: {
      visibility: {
        type: :string,
        required: true,
        enum: %w[public unlisted],
        hint: "Who can see the post once published",
      },
    },
  } do
    resource.update!(status: params[:visibility])
    redirect_to resource_path(resource), notice: "Published"
  end

  # No `mcp:` key at all, so the e2e suite can prove the opt-in guarantee: an
  # action that exists in the admin UI is not automatically exposed as a tool.
  member_action :archive, method: :post do
    resource.update!(status: "archived")
    redirect_to resource_path(resource), notice: "Archived"
  end

  # Opted in via `mcp:` with only a description: its param type is inherited
  # from `form:`, so the e2e suite can prove a batch action applies to exactly
  # the selected records and leaves the rest untouched.
  batch_action :set_status, form: { status: :text }, mcp: {
    description: "Set the status on the selected posts",
  } do |ids, inputs|
    Post.where(id: ids).update_all(status: inputs["status"])
    redirect_to collection_path, notice: "Status updated"
  end

  # Opted in via `mcp:` with a ZERO-ARGUMENT `permission:` proc that calls
  # `current_admin_user`, so the e2e suite can prove the proc is evaluated in
  # controller context at tools/list time. `current_admin_user` is only
  # defined on the controller: if listing-time evaluation ever regressed to a
  # bare `proc.call`, this would raise NameError, the tool would be hidden by
  # the rescue, and the example asserting it IS listed would fail.
  # E2E_ADMIN_EMAIL is only set for the process that seeds the database, not
  # for the running server, so the seeded admin's email is fixed here rather
  # than read from the environment: it has to match AppBuilder::ADMIN_EMAIL.
  collection_action :purge_drafts, method: :post, mcp: {
    description: "Purge draft posts, restricted to the seeded admin",
    permission: -> { current_admin_user&.email == "admin@example.com" },
  } do
    redirect_to collection_path, notice: "Purged"
  end
end
