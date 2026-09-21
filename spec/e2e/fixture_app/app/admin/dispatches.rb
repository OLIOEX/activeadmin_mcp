# Declares a form block whose second `f.inputs` names an association with
# `for:`, so the e2e suite can prove `describe_form` reports the associated
# record's fields as a nested group rather than flattening them in with the
# dispatch's own. `name` belongs to the author, and `create` and `update`
# would drop it from a write against a dispatch.
ActiveAdmin.register Dispatch do
  permit_params :headline, :author_id

  form do |f|
    f.inputs "Dispatch" do
      f.input :headline
    end
    f.inputs "Author", for: :author do |a|
      a.input :name
    end
    f.actions
  end
end
