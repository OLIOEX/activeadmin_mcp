# frozen_string_literal: true

ActiveadminMcp::Engine.routes.draw do
  post "/", to: "mcp#call"
end
