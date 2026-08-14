# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::RecordUpdater do
  # A stand-in for an ActiveAdmin controller compiled from `permit_params`.
  # `permitted` is the set of fields the admin form would allow.
  def build_controller(param_key:, permitted:)
    Class.new do
      attr_accessor :params

      define_method(:permitted_params) do
        params.permit(param_key => permitted)
      end
      private :permitted_params
    end
  end

  def build_resource(model:, actions: %i[index show new create edit update destroy],
                     adapter:, param_key: :widget, permitted: %i[name role])
    namespace = double("namespace", authorization_adapter: adapter)
    config = double(
      "config",
      defined_actions: actions,
      namespace: namespace,
      controller: build_controller(param_key: param_key, permitted: permitted),
      param_key: param_key,
    )
    { name: "Widget", model: model, config: config }
  end

  def model_finding(record, id: 1)
    double("model").tap { |m| allow(m).to receive(:find_by).with(id: id).and_return(record) }
  end

  let(:permit_all) do
    Class.new do
      def initialize(*); end
      def authorized?(*) = true
    end
  end

  let(:deny_all) do
    Class.new do
      def initialize(*); end
      def authorized?(*) = false
    end
  end

  def update(resource, id: 1, attributes:, current_user: :admin)
    described_class.new(resource: resource, current_user: current_user).call(id: id, attributes: attributes)
  end

  it "writes permitted attributes and returns the updated record" do
    record = double("record", id: 1, as_json: { "id" => 1, "name" => "Renamed" })
    allow(record).to receive(:update).and_return(true)
    resource = build_resource(model: model_finding(record), adapter: permit_all)

    result = update(resource, attributes: { "name" => "Renamed" })

    expect(record).to have_received(:update).with(name: "Renamed")
    expect(result[:updated]).to eq([:name])
    expect(result[:record]).to eq("id" => 1, "name" => "Renamed")
  end

  it "drops attributes the admin form does not permit" do
    record = double("record", id: 1, as_json: {})
    allow(record).to receive(:update).and_return(true)
    resource = build_resource(model: model_finding(record), adapter: permit_all, permitted: %i[name])

    update(resource, attributes: { "name" => "Renamed", "role" => "admin" })

    expect(record).to have_received(:update).with(name: "Renamed")
  end

  it "refuses when ActiveAdmin does not expose the update action" do
    resource = build_resource(model: double("model"), adapter: permit_all, actions: %i[index show])

    result = update(resource, attributes: { "name" => "Renamed" })

    expect(result[:error]).to match(/not editable/i)
  end

  it "refuses when the user is not authorized to update the record" do
    record = double("record", id: 1)
    resource = build_resource(model: model_finding(record), adapter: deny_all)

    result = update(resource, attributes: { "name" => "Renamed" })

    expect(result[:error]).to match(/not authorized/i)
  end

  it "returns an error when the record does not exist" do
    resource = build_resource(model: model_finding(nil, id: 999), adapter: permit_all)

    result = update(resource, id: 999, attributes: { "name" => "Renamed" })

    expect(result[:error]).to match(/not found/i)
  end

  it "returns validation errors when the update is rejected" do
    record = double("record", id: 1, errors: double("errors", full_messages: ["Name can't be blank"]))
    allow(record).to receive(:update).and_return(false)
    resource = build_resource(model: model_finding(record), adapter: permit_all)

    result = update(resource, attributes: { "name" => "" })

    expect(result[:error]).to match(/validation/i)
    expect(result[:details]).to eq(["Name can't be blank"])
  end

  it "returns an error when no permitted attributes remain after filtering" do
    record = double("record", id: 1)
    resource = build_resource(model: model_finding(record), adapter: permit_all, permitted: %i[name])

    result = update(resource, attributes: { "role" => "admin" })

    expect(result[:error]).to match(/no permitted attributes/i)
  end

  it "updates an attribute literally named 'error' without treating it as a failure" do
    record = double("record", id: 1, as_json: { "id" => 1, "error" => "boom" })
    allow(record).to receive(:update).and_return(true)
    resource = build_resource(model: model_finding(record), adapter: permit_all, permitted: %i[error])

    result = update(resource, attributes: { "error" => "boom" })

    expect(record).to have_received(:update).with(error: "boom")
    expect(result[:updated]).to eq([:error])
  end
end
