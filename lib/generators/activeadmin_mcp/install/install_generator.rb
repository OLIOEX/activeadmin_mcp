# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module ActiveadminMcp
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :auth, type: :string, default: nil,
                          desc: "Authentication method (e.g., devise_token)"
      class_option :admin_path, type: :string, default: "app/admin",
                                desc: "Path for ActiveAdmin page file"

      def copy_initializer
        template "initializer.rb", "config/initializers/activeadmin_mcp.rb"
      end

      def copy_migration
        return unless auth_method

        migration_template "migration.rb.erb", "db/migrate/create_mcp_api_tokens.rb"
      end

      def copy_admin_page
        return unless auth_method

        copy_file "mcp_api_tokens.rb", File.join(options[:admin_path], "mcp_api_tokens.rb")
      end

      def set_auth_config
        return unless auth_method

        gsub_file "config/initializers/activeadmin_mcp.rb",
                  "# config.authentication_method = :devise_token",
                  "config.authentication_method = :#{auth_method}"
      end

      def show_instructions
        say ""
        say "=" * 60, :green
        say " ActiveadminMcp installed!", :green
        say "=" * 60, :green
        say ""
        say "Your MCP server is available at: /mcp"
        say ""

        if auth_method
          say "Authentication (#{auth_method}) enabled! Next steps:", :yellow
          say ""
          say "  1. Run migrations:"
          say "     rails db:migrate"
          say ""
          say "  2. Create tokens via ActiveAdmin:"
          say "     Log in to /admin and visit 'MCP Tokens' under Settings"
          say ""
          say "  3. Connect Claude Code with your token:"
          say "     claude mcp add --transport http \\", :cyan
          say "       --header 'Authorization: Bearer YOUR_TOKEN' \\", :cyan
          say "       #{app_name} http://localhost:3000/mcp/", :cyan
        else
          say "Connect Claude Code:"
          say ""
          say "  claude mcp add --transport http #{app_name} http://localhost:3000/mcp/"
          say ""
          say "To add authentication later:"
          say "  rails generate activeadmin_mcp:install --auth devise_token"
        end

        say ""
      end

      private

      def auth_method
        options[:auth]
      end

      def app_name
        Rails.application.class.module_parent_name.underscore.dasherize
      rescue StandardError
        "my-app"
      end
    end
  end
end
