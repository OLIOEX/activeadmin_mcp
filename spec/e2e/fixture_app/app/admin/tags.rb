# Registered with ActiveAdmin's default actions but deliberately without
# `permit_params`, so the e2e suite can prove the MCP `create` and `update`
# tools refuse a resource that has never declared what may be written — which
# is a resource ActiveAdmin cannot write through its own forms either.
ActiveAdmin.register Tag do
end
