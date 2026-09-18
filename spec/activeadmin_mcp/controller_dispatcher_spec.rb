# frozen_string_literal: true

require "spec_helper"
require "support/active_admin"

RSpec.describe ActiveadminMcp::ControllerDispatcher do
  let(:config) { McpSpec::ActiveAdminHarness.volunteer_config }
  let(:admin) { AdminUser.create!(email: "admin@example.com") }
  let(:volunteer) { Volunteer.create!(name: "Ann") }

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
    controller = dispatcher.send(:build_controller)

    expect(controller.send(ActiveadminMcp.config.current_user_method)).to eq(admin)
    expect(controller.send(:current_active_admin_user)).to eq(admin)
  end

  it "returns an error hash rather than raising when the action blows up" do
    allow_any_instance_of(config.controller).to receive(:create_warning).and_raise("kaboom")

    result = dispatch(action: :create_warning, params: { reason: "Late" })

    expect(result[:error]).to include("kaboom")
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
end
