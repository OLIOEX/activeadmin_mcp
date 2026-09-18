# frozen_string_literal: true

require "spec_helper"
require "support/active_admin"

# An authorization adapter that denies everything, used to prove that
# neutralising the namespace's authentication_method (see controller_with_mcp_user)
# does not also neutralise authorization, which must keep running in full.
class DenyingAuthorizationAdapter < ActiveAdmin::AuthorizationAdapter
  def authorized?(_action, _subject = nil)
    false
  end
end

RSpec.describe ActiveadminMcp::ControllerDispatcher do
  let(:config) { McpSpec::ActiveAdminHarness.volunteer_config }
  let(:admin) { AdminUser.create!(email: "admin@example.com") }
  let(:volunteer) { Volunteer.create!(name: "Ann") }

  after do
    Volunteer.delete_all
    AdminUser.delete_all
  end

  def dispatch(action:, params: {}, path: nil, path_params: {})
    described_class.new(config: config, current_user: admin).call(
      action: action,
      path: path || config.route_member_action_path(action, volunteer),
      verb: :post,
      params: params,
      path_params: { id: volunteer.id.to_s }.merge(path_params)
    )
  end

  it "runs the action and captures the redirect and flash" do
    result = dispatch(action: :create_warning, params: { reason: "Late again" })

    expect(result[:status]).to eq(302)
    expect(result[:redirect_to]).to include("/admin/volunteers/#{volunteer.id}")
    expect(result[:flash]).to eq("notice" => "Warning recorded")
    expect(result).not_to have_key(:error)
  end

  it "actually performs the action's side effect" do
    dispatch(action: :create_warning, params: { reason: "Late again" })

    expect(volunteer.reload.name).to eq("Late again")
  end

  it "exposes the MCP user to the controller as the current admin user" do
    dispatcher = described_class.new(config: config, current_user: admin)
    controller = dispatcher.controller_with_mcp_user

    expect(controller.send(ActiveadminMcp.config.current_user_method)).to eq(admin)
    expect(controller.send(:current_active_admin_user)).to eq(admin)
  end

  it "returns an error hash rather than raising when the action blows up" do
    allow_any_instance_of(config.controller).to receive(:create_warning).and_raise("kaboom")
    allow_any_instance_of(described_class).to receive(:warn)

    result = dispatch(action: :create_warning, params: { reason: "Late" })

    expect(result[:error]).to eq("Volunteer#create_warning failed")
  end

  # An exception message can carry SQL, table names and file paths. The client
  # gets a generic failure; the detail goes to the log.
  it "keeps the exception message out of the client's result and logs it instead" do
    allow_any_instance_of(config.controller).to receive(:create_warning)
      .and_raise("SQLite3::SQLException: no such table: nope_secret: SELECT * FROM nope_secret")
    messages = []
    allow_any_instance_of(described_class).to receive(:warn) { |_, message| messages << message }

    result = dispatch(action: :create_warning, params: { reason: "Late" })

    expect(result[:error]).not_to include("nope_secret")
    expect(messages.join).to include("nope_secret")
  end

  # ActiveadminMcp.config.current_user_method and the ActiveAdmin namespace's
  # own current_user_method can disagree; an action body calling either one must
  # get the MCP user, not nil.
  context "when the namespace names a different current user method" do
    around do |example|
      namespace = ActiveAdmin.application.namespaces[:admin]
      previous = namespace.current_user_method
      namespace.current_user_method = :current_namespace_admin
      example.run
      namespace.current_user_method = previous
    end

    it "stubs the namespace's method as well as the configured one" do
      controller = described_class.new(config: config, current_user: admin).controller_with_mcp_user

      expect(controller.send(:current_namespace_admin)).to eq(admin)
      expect(controller.send(ActiveadminMcp.config.current_user_method)).to eq(admin)
      expect(controller.send(:current_active_admin_user)).to eq(admin)
    end
  end

  it "defines each current user method once when the two settings agree" do
    namespace = ActiveAdmin.application.namespaces[:admin]
    allow(namespace).to receive(:current_user_method).and_return(ActiveadminMcp.config.current_user_method)

    controller = described_class.new(config: config, current_user: admin).controller_with_mcp_user

    defined_names = controller.singleton_methods.map(&:to_s)
    expect(defined_names.count(ActiveadminMcp.config.current_user_method.to_s)).to eq(1)
  end

  it "reports a rendered response without returning the body" do
    result = dispatch(action: :undocumented)

    expect(result[:status]).to eq(200)
    expect(result[:rendered]).to be(true)
    expect(result).not_to have_key(:body)
  end

  context "when the namespace has an authentication method" do
    around do |example|
      namespace = ActiveAdmin.application.namespaces[:admin]
      previous = namespace.authentication_method
      namespace.authentication_method = :authenticate_admin_user!
      example.run
      namespace.authentication_method = previous
    end

    it "neutralises it rather than redirecting to a login page" do
      result = dispatch(action: :create_warning, params: { reason: "Late again" })

      expect(result[:redirect_to]).to include("/admin/volunteers/#{volunteer.id}")
      expect(volunteer.reload.name).to eq("Late again")
    end
  end

  context "when the authorization adapter denies the action" do
    around do |example|
      namespace = ActiveAdmin.application.namespaces[:admin]
      previous = namespace.authorization_adapter
      namespace.authorization_adapter = DenyingAuthorizationAdapter
      example.run
      namespace.authorization_adapter = previous
    end

    it "blocks the action instead of running it" do
      result = dispatch(action: :create_warning, params: { reason: "Late again" })

      # ActiveAdmin's default on_unauthorized_access handler rescues
      # ActiveAdmin::AccessDenied internally and turns it into a redirect
      # with a flash message, rather than letting the exception reach
      # ControllerDispatcher's own rescue — so the denial surfaces as a
      # flash entry, not a top-level :error key. What actually matters is
      # proven below: the write never happened.
      expect(result).not_to have_key(:error)
      expect(result[:flash]&.values&.join).to match(/not authorized/i)

      expect(volunteer.reload.name).to eq("Ann")
    end
  end
end
