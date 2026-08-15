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

  # Resources that declare writable fields through a `form do ... end` block
  # rather than `permit_params`. ActiveAdmin's default `permitted_params` for
  # such a resource returns nil, so the updater derives the allowed fields from
  # the form inputs instead.
  describe "deriving permitted fields from the form block" do
    # A controller that has not declared permit_params: `permitted_params` is nil.
    def build_formless_controller
      Class.new do
        attr_accessor :params
        def permitted_params = nil
        private :permitted_params
      end
    end

    def build_form_resource(model:, adapter:, param_key: :widget, form_block:,
                            page_presenters: nil)
      namespace = double("namespace", authorization_adapter: adapter)
      presenters = page_presenters
      presenters ||= { form: double("form presenter", block: form_block) } if form_block
      config = double(
        "config",
        defined_actions: %i[index show new create edit update destroy],
        namespace: namespace,
        controller: build_formless_controller,
        param_key: param_key,
        page_presenters: presenters || {},
      )
      { name: "Widget", model: model, config: config }
    end

    it "permits fields declared as form inputs and drops the rest" do
      record = double("record", id: 1, as_json: {})
      allow(record).to receive(:update).and_return(true)
      form_block = proc do |_f|
        inputs do
          input :name
          input :role
        end
        actions
      end
      resource = build_form_resource(model: model_finding(record), adapter: permit_all, form_block: form_block)

      update(resource, attributes: { "name" => "Renamed", "role" => "admin", "secret" => "x" })

      expect(record).to have_received(:update).with(name: "Renamed", role: "admin")
    end

    it "tolerates arbitrary input options, helper calls and nesting in the form block" do
      record = double("record", id: 1, as_json: {})
      allow(record).to receive(:update).and_return(true)
      form_block = proc do |_f|
        semantic_errors
        inputs "Details" do
          input :user_id, as: :hidden
          input :name, as: :string, hint: some_undefined_helper
          input :country, as: :select, collection: %w[UK IE]
        end
        actions
      end
      resource = build_form_resource(model: model_finding(record), adapter: permit_all, form_block: form_block)

      update(resource, attributes: { "user_id" => 5, "name" => "N", "country" => "UK", "nope" => 1 })

      expect(record).to have_received(:update).with(user_id: 5, name: "N", country: "UK")
    end

    it "fails closed when neither permit_params nor a form block is available" do
      record = double("record", id: 1)
      resource = build_form_resource(model: model_finding(record), adapter: permit_all,
                                     form_block: nil, page_presenters: {})

      result = update(resource, attributes: { "name" => "x" })

      expect(result[:error]).to match(/could not determine permitted attributes/i)
    end

    it "fails closed when the form block raises during introspection" do
      record = double("record", id: 1)
      form_block = proc { |_f| raise "boom" }
      resource = build_form_resource(model: model_finding(record), adapter: permit_all, form_block: form_block)

      result = update(resource, attributes: { "name" => "x" })

      expect(result[:error]).to match(/could not determine permitted attributes/i)
    end
  end
end
