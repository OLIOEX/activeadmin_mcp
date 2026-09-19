require "spec_helper"

RSpec.describe ActiveadminMcp::FormFieldCollector do
  def collect(&block)
    described_class.new.collect(&block)
  end

  it "records a bare input as a field with no declared options" do
    inputs = collect { |_f| input :title }

    expect(inputs).to eq([{ name: :title }])
  end

  it "records the input options a client needs in order to stop guessing" do
    inputs = collect do |_f|
      input :status, as: :select, required: true, label: "Publication status", hint: "Draft until reviewed"
    end

    expect(inputs.first).to include(
      name: :status,
      as: :select,
      required: true,
      label: "Publication status",
      hint: "Draft until reviewed"
    )
  end

  it "ignores input options that say nothing about how to fill the field in" do
    inputs = collect { |_f| input :title, wrapper_html: { class: "wide" }, input_html: { size: 40 } }

    expect(inputs).to eq([{ name: :title }])
  end

  it "descends into inputs blocks, which is where most forms declare their fields" do
    inputs = collect do |_f|
      inputs "Details" do
        input :title
        input :body
      end
      actions
    end

    expect(inputs.map { |input| input[:name] }).to eq(%i[title body])
  end

  it "tolerates helper calls and conditionals that need a view context the collector does not have" do
    inputs = collect do |_f|
      semantic_errors
      inputs do
        input :title, hint: some_undefined_helper
        input :author_id, as: :hidden
      end
      actions
    end

    expect(inputs.map { |input| input[:name] }).to eq(%i[title author_id])
    expect(inputs.first).not_to have_key(:hint)
  end

  it "records a has_many block as a nested group rather than flattening its fields into the parent" do
    inputs = collect do |_f|
      input :title
      has_many :comments do |c|
        c.input :body
      end
    end

    expect(inputs).to eq(
      [
        { name: :title },
        { name: :comments, nested: [{ name: :body }] },
      ]
    )
  end

  describe "a collection: of allowed values" do
    it "records a literal array of values" do
      inputs = collect { |_f| input :status, as: :select, collection: %w[draft published] }

      expect(inputs.first[:collection]).to eq(%w[draft published])
    end

    it "records the values of label/value pairs, which is how a select names them separately" do
      inputs = collect { |_f| input :status, as: :select, collection: [["Draft", "draft"], ["Published", "published"]] }

      expect(inputs.first[:collection]).to eq(%w[draft published])
    end

    # A relation would mean firing a query from a description call, and can be
    # arbitrarily large; a proc usually needs the view context we do not have.
    it "omits a collection that is not a literal array, rather than evaluating it" do
      queried = false
      relation = Class.new do
        define_method(:to_a) { queried = true }
      end.new

      inputs = collect { |_f| input :author, as: :select, collection: relation }

      expect(inputs.first).not_to have_key(:collection)
      expect(queried).to be(false)
    end

    it "omits a collection whose entries are neither scalars nor pairs" do
      inputs = collect { |_f| input :author, as: :select, collection: [Object.new] }

      expect(inputs.first).not_to have_key(:collection)
    end
  end

  it "records each field once when a form declares the same input twice" do
    inputs = collect do |_f|
      input :title
      input :title, hint: "Second thoughts"
    end

    expect(inputs.map { |input| input[:name] }).to eq([:title])
  end

  it "returns nothing at all for a form block that declares no inputs" do
    expect(collect { |_f| actions }).to eq([])
  end
end
