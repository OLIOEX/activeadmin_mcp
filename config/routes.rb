ActiveadminMcp::Engine.routes.draw do
  post "/", to: "mcp#call"
end
