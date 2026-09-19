# frozen_string_literal: true

# Permits title and body but deliberately not slug, so the e2e suite can prove
# the MCP `update` tool drops attributes the admin form does not accept.
ActiveAdmin.register Post do
  permit_params :title, :body
end
