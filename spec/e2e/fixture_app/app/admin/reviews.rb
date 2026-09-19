# The only fixture resource that declares an explicit `form do ... end` block,
# so the e2e suite can prove `describe_form` reads a declared form — its input
# types, labels, hints and literal collections — rather than deriving the
# description from permitted params as it does for every other resource here.
ActiveAdmin.register Review do
  permit_params :body, :status

  form do |f|
    f.inputs "Review" do
      f.input :body, hint: "Shown beneath the post"
      f.input :status, as: :select, collection: %w[pending approved], label: "Moderation status"
    end
    f.actions
  end
end
