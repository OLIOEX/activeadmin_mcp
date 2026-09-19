# Permits title and body but deliberately not slug, so the e2e suite can prove
# the MCP `update` tool drops attributes the admin form does not accept.
ActiveAdmin.register Post do
  permit_params :title, :body

  # Neither action below is declared here, so neither can carry an `mcp:` key.
  # The mcp_action declarations that follow annotate them by name.
  include Flaggable

  mcp_action :flag, kind: :batch, tool_name: "post_bulk_flag",
             description: "Flag the selected posts",
             params: { reason: { type: :string, required: true } }

  mcp_action :flag, kind: :member, tool_name: "post_flag",
             description: "Flag a post",
             params: { reason: { type: :string, required: true } }

  mcp_action :flag, kind: :member, http_verb: :delete, tool_name: "post_unflag",
             description: "Remove a post's flag"

  mcp_action :clear_flags, kind: :collection, description: "Clear the flag on every flagged post"

  # Named by the title the concern gave them, because the symbols ActiveAdmin
  # derived from those titles carry punctuation. No tool_name: either, so the
  # derived one has to be usable on its own.
  Flaggable::WARNING_REASONS.each do |reason|
    mcp_action "Warning: #{reason}", kind: :batch,
               description: "Warn the selected posts: #{reason.downcase}"
  end

  mcp_action :purge, kind: :batch, description: "Delete the selected posts"

  mcp_action :guarded_flag, kind: :batch, description: "Flag the selected posts, if the controller allows it"

  # These ActiveAdmin callbacks fire only when the create or update action runs
  # through the real controller, so the e2e suite can read their effects to
  # prove an MCP write is dispatched rather than written straight to the model.
  # `slug` is deliberately outside `permit_params`, so a created post can only
  # get one from this callback.
  before_create { |post| post.slug = post.title.to_s.parameterize if post.slug.blank? }
  before_update { |post| post.body = "#{post.body} (revised)" }

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

  # The body raises deliberately, so the e2e suite can prove an action that
  # blows up comes back as a generic error naming the resource and action,
  # with the exception's own message kept away from the MCP client — it can
  # carry SQL, table names and file paths.
  member_action :explode, method: :post, mcp: {
    description: "Always raises, so the error path has something to bite on",
  } do
    raise ActiveRecord::StatementInvalid, "SQLite3::SQLException: no such table: classified_dossier"
  end

  # Opted in with a `permission:` proc that takes the record. A proc needing a
  # record cannot be resolved at tools/list time, so the tool stays advertised
  # and the proc runs at call time instead. It returns a String for a draft
  # post, which the client should see as the refusal reason, and true once the
  # post has been published — so the suite can prove the proc is consulted
  # per record rather than simply always refusing.
  member_action :feature, method: :post, mcp: {
    description: "Feature a published post on the front page",
    permission: lambda { |post|
      post.status == "draft" ? "Only a published post can be featured" : true
    },
  } do
    resource.update!(status: "featured")
    redirect_to resource_path(resource), notice: "Featured"
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
