# Declares a form block that declares no inputs of its own: `f.inputs` with no
# block is legal, and Formtastic expands it against the model at render time.
# There is nothing in it to read, so the e2e suite can prove `describe_form`
# falls back to the resource's permitted params rather than reporting a form
# whose every field is missing — which a client reads as "nothing may be
# written here".
ActiveAdmin.register Bulletin do
  permit_params :headline, :body

  form do |f|
    f.inputs
    f.actions
  end
end
