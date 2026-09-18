# frozen_string_literal: true

# Boots a minimal Rails + ActiveAdmin application so specs can exercise real
# ActiveAdmin objects (resource configs, controllers, dispatch) rather than
# doubles. Required only by specs that genuinely need it; the rest of the
# suite stays double-based and never loads ActiveAdmin.
require "rails"
require "active_record"
require "action_controller/railtie"
require "active_model/railtie"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :volunteers, force: true do |t|
    t.string :name
    t.boolean :active, default: true
    t.timestamps
  end

  create_table :admin_users, force: true do |t|
    t.string :email
    t.timestamps
  end
end

class Volunteer < ActiveRecord::Base; end
class AdminUser < ActiveRecord::Base; end

require "active_admin"

module McpSpec
  class HarnessApp < Rails::Application
    config.eager_load = false
    config.root = File.expand_path("../tmp/harness", __dir__)
    config.secret_key_base = "a" * 64
    config.logger = Logger.new(IO::NULL)
    config.active_support.to_time_preserves_timezone = :zone
  end

  module ActiveAdminHarness
    def self.volunteer_config
      ActiveAdmin.application.namespaces[:admin].resources.find do |resource|
        resource.resource_class == Volunteer
      end
    end
  end
end

FileUtils.mkdir_p(McpSpec::HarnessApp.config.root)
Rails.application.initialize!

# InheritedResources, which ActiveAdmin's resource controllers inherit from,
# references ::ApplicationController at load time.
class ApplicationController < ActionController::Base; end

# Runs ActiveAdmin's before_load hooks, which is what defines
# ActiveAdmin::BatchAction and mixes batch action support into Resource.
ActiveAdmin.application.load!

# Batch actions default to disabled in a bare boot like this one; a real app
# enables them in its ActiveAdmin initializer.
ActiveAdmin.application.namespaces[:admin].batch_actions = true

ActiveAdmin.register Volunteer do
  actions :index, :show, :edit, :update

  member_action :create_warning, method: :post, mcp: {
    description: "Record a warning against a volunteer",
    params: { reason: { type: :string, required: true } }
  } do
    resource.update(name: params[:reason])
    redirect_to resource_path(resource), notice: "Warning recorded"
  end

  member_action :undocumented, method: :post do
    head :ok
  end

  collection_action :export, method: :get, mcp: { description: "Export volunteers" } do
    redirect_to collection_path, notice: "Exported"
  end

  batch_action :suspend, form: { reason: :text },
                         mcp: { description: "Suspend the selected volunteers" } do |ids, inputs|
    redirect_to collection_path, notice: "#{ids.size} suspended: #{inputs[:reason]}"
  end
end

Rails.application.routes.draw do
  ActiveAdmin.routes(self)
end
