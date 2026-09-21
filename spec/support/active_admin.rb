# Boots a minimal Rails + ActiveAdmin application so specs can exercise real
# ActiveAdmin objects (resource configs, controllers, dispatch) rather than
# doubles. Required only by specs that genuinely need it; the rest of the
# suite stays double-based and never loads ActiveAdmin.
require "rails"
require "active_record"
require "action_controller/railtie"
require "active_model/railtie"

# Shared-cache URI, not a bare ":memory:" database — see the comment in
# spec/support/active_record.rb for why: two anonymous in-memory databases
# would fight over ActiveRecord::Base's single connection pool depending on
# spec load order, stranding whichever support file's tables loaded first.
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", database: "file:activeadmin_mcp_test?mode=memory&cache=shared"
)
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :volunteers, force: true do |t|
    t.string :name
    t.boolean :active, default: true
    t.timestamps
  end

  # Registered read-only, so a spec can prove a write is refused for a
  # resource whose ActiveAdmin registration does not expose the action.
  create_table :notes, force: true do |t|
    t.string :body
    t.timestamps
  end

  # Registered writable but WITHOUT permit_params, so a spec can prove a write
  # is refused for a resource that never declared what may be written.
  create_table :sightings, force: true do |t|
    t.string :species
    t.references :shift
    t.timestamps
  end

  # Registered with an explicit `form do ... end` block, so a spec can prove a
  # description is read from the form a resource declares rather than derived
  # from its permitted params.
  create_table :shifts, force: true do |t|
    t.string :name
    t.string :location
    t.datetime :starts_at
    t.timestamps
  end

  # Registered with a form block that declares no inputs of its own, leaving
  # Formtastic to expand a bare `f.inputs` at render time — the shape of
  # ActiveAdmin's own default form. There is nothing there to read, so the
  # description has to fall back to permitted params.
  create_table :rosters, force: true do |t|
    t.string :name
    t.string :notes
    t.timestamps
  end

  # Registered with a block-form permit_params that reads controller state,
  # which ActiveAdmin instance_execs on the controller. Resolving it against a
  # controller with no MCP user on it raises, so this is the fixture that keeps
  # the resolution honest about needing controller context.
  create_table :placements, force: true do |t|
    t.string :name
    t.string :notes
    t.timestamps
  end

  create_table :admin_users, force: true do |t|
    t.string :email
    t.timestamps
  end
end

class Volunteer < ActiveRecord::Base
  validates :name, presence: true
end
class Note < ActiveRecord::Base; end
class Placement < ActiveRecord::Base; end
class Roster < ActiveRecord::Base; end
class Shift < ActiveRecord::Base
  has_many :sightings
  accepts_nested_attributes_for :sightings
  validates :name, presence: true
end
class Sighting < ActiveRecord::Base; end
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
  actions :index, :show, :new, :create, :edit, :update

  permit_params :name, :active

  # An ActiveAdmin callback fires only when the create or update action runs
  # through the real controller, so a spec can use the trimmed name to prove a
  # write was dispatched rather than written straight to the model.
  before_save { |volunteer| volunteer.name = volunteer.name.to_s.strip }

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
    Volunteer.where(id: ids).update_all(name: "Suspended: #{inputs[:reason]}")
    redirect_to collection_path, notice: "#{ids.size} suspended: #{inputs[:reason]}"
  end
end

# Installs the mcp_action DSL. In an application the engine does this before
# ActiveAdmin loads its registrations; here the registrations below are plain
# top-level code, so it has to happen before them.
ActiveadminMcp::ActiveAdminExt.apply_dsl!

module McpSpec
  # In the shape of the application concerns this gem has to support: the DSL
  # calls live in self.included and are shared verbatim across resources, so
  # nothing here can carry an mcp: key of its own without describing every
  # resource that includes it identically.
  #
  # Deliberately awkward in the same three ways a real one is: the same name
  # used for both a member and a batch action, a member action answering to two
  # verbs, and a batch action whose form: is a proc rather than a hash.
  module SharedFlagActions
    def self.included(dsl)
      dsl.send(:member_action, :flag, method: [:post, :delete]) do
        if request.delete?
          resource.update(location: nil)
          redirect_to resource_path(resource), notice: "Flag removed"
        else
          resource.update(location: params[:label])
          redirect_to resource_path(resource), notice: "Flagged"
        end
      end

      # ActiveAdmin hides a batch action from the UI when its :if proc refuses.
      dsl.send(:batch_action, :purge, if: proc { current_admin_user&.email == "superuser@example.com" }) do |ids|
        Shift.where(id: ids).delete_all
        redirect_to collection_path, notice: "Purged"
      end

      dsl.send(:batch_action, :flag, form: proc { { reason: :text, notify: :checkbox } }) do |ids, inputs|
        Shift.where(id: ids).update_all(location: inputs["reason"])
        redirect_to collection_path, notice: "Flagged #{ids.size}"
      end
    end
  end
end

ActiveAdmin.register Shift do
  include McpSpec::SharedFlagActions

  mcp_action :flag, kind: :batch, tool_name: "shift_bulk_flag",
             description: "Flag the selected shifts",
             params: { reason: { type: :string, required: true } }

  mcp_action :flag, kind: :member, tool_name: "shift_flag",
             description: "Flag a shift",
             params: { reason: { type: :string, required: true } }

  mcp_action :purge, kind: :batch, description: "Purge the selected shifts"

  mcp_action :flag, kind: :member, http_verb: :delete, tool_name: "shift_unflag",
             description: "Remove a shift's flag"

  permit_params :name, :location, :starts_at

  form do |f|
    f.inputs "Shift" do
      f.input :name, hint: "How the shift appears on the rota"
      f.input :location, as: :select, collection: %w[kitchen warehouse]
      f.input :starts_at, as: :datetime_select, label: "Starts"
    end
    f.has_many :sightings do |sighting|
      sighting.input :species
    end
    f.actions
  end
end

ActiveAdmin.register Placement do
  permit_params do
    current_admin_user ? %i[name notes] : %i[name]
  end
end

ActiveAdmin.register Roster do
  permit_params :name, :notes

  form do |f|
    f.inputs
    f.actions
  end
end

ActiveAdmin.register Note do
  actions :index, :show
end

ActiveAdmin.register Sighting do
end

# An authorization adapter that denies everything, used to prove that
# neutralising the namespace's authentication_method (see
# ControllerDispatcher#controller_with_mcp_user) does not also neutralise
# authorization, which must keep running in full.
class DenyingAuthorizationAdapter < ActiveAdmin::AuthorizationAdapter
  def authorized?(_action, _subject = nil)
    false
  end
end

Rails.application.routes.draw do
  ActiveAdmin.routes(self)
end
