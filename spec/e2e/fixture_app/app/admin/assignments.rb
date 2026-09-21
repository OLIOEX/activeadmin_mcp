# Declared in the two shapes the rest of the fixture application does not use,
# so the e2e suite covers them rather than only the shapes the gem was written
# against:
#
#   * `permit_params` as a block that reads controller state, which ActiveAdmin
#     instance_execs on the controller;
#   * a `form` block declaring no inputs of its own, leaving Formtastic to
#     expand a bare `f.inputs` at render time, as ActiveAdmin's own default
#     form does — so there is nothing in the block to read and the description
#     has to come from the permitted params instead.
#
# `secret_note` is a column neither branch of the block permits, so the suite
# has something the block withholds as well as something it grants: an example
# that only ever writes a permitted attribute cannot tell a block that filters
# from one whose result is ignored.
ActiveAdmin.register Assignment do
  permit_params do
    current_admin_user ? %i[name notes] : %i[name]
  end

  form do |f|
    f.inputs
    f.actions
  end
end
