# The only fixture resource that declares an explicit `form do ... end` block,
# so the e2e suite can prove `describe_form` reads a declared form — its input
# types, labels, hints and literal collections — rather than deriving the
# description from permitted params as it does for every other resource here.
ActiveAdmin.register Review do
  permit_params :body, :status

  # Includes the same concern as Post but annotates none of it, so the e2e
  # suite can prove sharing an action does not share its MCP exposure: the
  # opt-in is still per resource.
  include Flaggable

  form do |f|
    f.inputs "Review" do
      f.input :body, hint: "Shown beneath the post"
      f.input :status, as: :select, collection: %w[pending approved], label: "Moderation status"
    end
    # Formtastic's other route into an association's fields, alongside
    # has_many: its inputs belong to the post, not to the review.
    f.inputs for: :post do |post|
      post.input :title
    end
    f.actions
  end
end
