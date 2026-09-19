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

    initializer "activeadmin_mcp.active_admin_ext" do
      ActiveSupport.on_load(:after_initialize) do
        next unless defined?(::ActiveAdmin)

        # The DSL has to exist before ActiveAdmin loads the registrations that
        # call it; the option readers only have to exist before the catalog is
        # read, and ActiveAdmin::BatchAction does not exist until load time.
        ActiveadminMcp::ActiveAdminExt.apply_dsl!
        ActiveAdmin.after_load { ActiveadminMcp::ActiveAdminExt.apply! }
      end
    end
  end
end
