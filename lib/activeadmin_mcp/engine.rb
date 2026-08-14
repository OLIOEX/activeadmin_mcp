# frozen_string_literal: true

module ActiveadminMcp
  class Engine < ::Rails::Engine
    isolate_namespace ActiveadminMcp

    initializer "activeadmin_mcp.mount" do |app|
      case ActiveadminMcp.config.mount_strategy
      when :prepend
        app.routes.prepend do
          mount ActiveadminMcp::Engine => ActiveadminMcp.config.mount_path
        end
      when :append
        app.routes.append do
          mount ActiveadminMcp::Engine => ActiveadminMcp.config.mount_path
        end
      end
    end
  end
end
