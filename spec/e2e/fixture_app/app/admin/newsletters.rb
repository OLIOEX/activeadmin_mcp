# Declares its `permit_params` in the BLOCK form, which ActiveAdmin
# instance_execs on the controller, and the block reads `current_admin_user`
# — the documented way an application varies the writable set by user. So the
# e2e suite can prove the permitted set is resolved in controller context: a
# caller asking a bare controller instance gets a NameError, reads that as
# "this resource declared no permit_params", and refuses `create`, `update`
# and `describe_form` outright.
#
# E2E_ADMIN_EMAIL is only set for the process that seeds the database, not for
# the running server, so the seeded admin's email is fixed here rather than
# read from the environment: it has to match AppBuilder::ADMIN_EMAIL.
#
# `secret_note` is permitted to nobody, so the suite has something the block
# withholds as well as something it grants.
ActiveAdmin.register Newsletter do
  permit_params do
    current_admin_user&.email == "admin@example.com" ? %i[title body] : %i[title]
  end
end
