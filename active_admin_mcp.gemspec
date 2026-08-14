# frozen_string_literal: true

require_relative "lib/active_admin_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "active_admin_mcp"
  spec.version = ActiveAdminMcp::VERSION
  spec.authors = ["harunkumars"]
  spec.email = ["harun@betacraft.io"]

  spec.summary = "MCP server for Rails apps with ActiveAdmin"
  spec.description = "Expose your ActiveAdmin resources to AI assistants via the Model Context Protocol (MCP)."
  spec.homepage = "https://github.com/harunkumars/active_admin_mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,lib}/**/*", "LICENSE.txt", "README.md"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.1"
  spec.add_dependency "activeadmin", ">= 2.0"

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "sqlite3", ">= 1.4"
end
