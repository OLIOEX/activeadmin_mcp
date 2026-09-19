# Registered without the update action, so the e2e suite can prove the MCP
# `update` tool refuses a resource the admin UI would not let you edit either.
ActiveAdmin.register Author do
  actions :index, :show
end
