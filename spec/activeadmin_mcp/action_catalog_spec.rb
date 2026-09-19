require "spec_helper"

RSpec.describe ActiveadminMcp::ActionCatalog do
  def action(name, mcp:, verb: :post)
    double("controller_action", name: name, http_verb: verb, mcp_options: mcp)
  end

  def batch(name, mcp:, form: nil, title: nil, display_if: nil)
    double(
      "batch_action",
      sym: name,
      mcp_options: mcp,
      inputs: form,
      title: title || name.to_s.titleize,
      display_if_block: display_if
    )
  end

  def config(member: [], collection: [], batch_actions: [], batch_enabled: true, name: "Volunteer",
             annotations: [])
    double(
      "config",
      resource_class: double("model", name: name),
      member_actions: member,
      collection_actions: collection,
      batch_actions: batch_actions,
      batch_actions_enabled?: batch_enabled,
      mcp_annotations: annotations
    )
  end

  def annotation(name, kind: nil, **options)
    { action_name: name, kind: kind, options: options }
  end

  def stub_resources(*configs)
    entries = configs.map { |c| { name: c.resource_class.name, model: c.resource_class, config: c } }
    allow(ActiveadminMcp::ResourceRegistry).to receive(:resources).and_return(entries)
  end

  it "collects opted-in actions and ignores the rest" do
    stub_resources(config(member: [
      action(:create_warning, mcp: { description: "Record a warning" }),
      action(:undocumented, mcp: nil)
    ]))

    expect(described_class.all.map(&:tool_name)).to eq(["volunteer_create_warning"])
  end

  # Verified against ActiveAdmin 3.5.2: batch_actions_enabled? can be false
  # while batch actions are still registered. Exposing them would surface an
  # action the admin UI itself hides.
  it "skips batch actions when the namespace has them disabled" do
    stub_resources(config(batch_actions: [batch(:suspend, mcp: { description: "Suspend" })],
                          batch_enabled: false))

    expect(described_class.all).to be_empty
  end

  it "includes batch actions when the namespace has them enabled" do
    stub_resources(config(batch_actions: [batch(:suspend, mcp: { description: "Suspend" })]))

    expect(described_class.all.map(&:tool_name)).to eq(["volunteer_suspend"])
  end

  it "refuses a tool name that collides with a built-in tool" do
    stub_resources(config(collection: [action(:resources, mcp: { description: "Clash" })], name: "List"))

    expect(described_class.all).to be_empty
  end

  it "drops invalid declarations rather than exposing them" do
    stub_resources(config(member: [action(:create_warning, mcp: { params: {} })]))

    expect(described_class.all).to be_empty
  end

  it "finds a definition by tool name" do
    stub_resources(config(member: [action(:create_warning, mcp: { description: "Record a warning" })]))

    expect(described_class.find("volunteer_create_warning").action_name).to eq(:create_warning)
    expect(described_class.find("nope")).to be_nil
  end

  # Actions declared by a shared concern cannot carry an mcp: key of their own,
  # so the resource annotates them by name.
  describe "actions annotated with mcp_action" do
    it "exposes an action that carries no mcp: key of its own" do
      stub_resources(config(
        member: [action(:tag, mcp: nil)],
        annotations: [annotation(:tag, description: "Tag a volunteer")]
      ))

      definitions = described_class.all
      expect(definitions.map(&:tool_name)).to eq(["volunteer_tag"])
      expect(definitions.first.description).to eq("Tag a volunteer")
    end

    it "replaces an inline mcp: declaration rather than merging into it" do
      stub_resources(config(
        member: [action(:tag, mcp: { description: "Generic", params: { a: { type: :string } } })],
        annotations: [annotation(:tag, description: "This resource's own wording")]
      ))

      definition = described_class.all.first
      expect(definition.description).to eq("This resource's own wording")
      expect(definition.params).to eq({})
    end

    it "builds one tool per annotation, so one action can be exposed more than once" do
      stub_resources(config(
        member: [action(:tag, mcp: nil, verb: %i[post delete])],
        annotations: [
          annotation(:tag, tool_name: "volunteer_tag", description: "Tag"),
          annotation(:tag, tool_name: "volunteer_untag", http_verb: :delete, description: "Untag"),
        ]
      ))

      expect(described_class.all.map { |d| [d.tool_name, d.http_verb] })
        .to contain_exactly(["volunteer_tag", :post], ["volunteer_untag", :delete])
    end

    it "matches an annotation to the kind it names when one name is both a member and a batch action" do
      stub_resources(config(
        member: [action(:tag, mcp: nil)],
        batch_actions: [batch(:tag, mcp: nil, form: { label: :text })],
        annotations: [annotation(:tag, kind: :batch, description: "Tag the selected volunteers")]
      ))

      definitions = described_class.all
      expect(definitions.map(&:kind)).to eq([:batch])
    end

    it "refuses an annotation whose kind is ambiguous rather than guessing which action was meant" do
      allow(described_class).to receive(:warn)
      stub_resources(config(
        member: [action(:tag, mcp: nil)],
        batch_actions: [batch(:tag, mcp: nil, form: { label: :text })],
        annotations: [annotation(:tag, description: "Tag")]
      ))

      expect(described_class.all).to be_empty
      expect(described_class).to have_received(:warn).with(/kind/)
    end

    it "warns and skips an annotation naming an action the resource does not declare" do
      allow(described_class).to receive(:warn)
      stub_resources(config(
        member: [action(:create_warning, mcp: { description: "Record a warning" })],
        annotations: [annotation(:typo, description: "Nothing declares this")]
      ))

      expect(described_class.all.map(&:tool_name)).to eq(["volunteer_create_warning"])
      expect(described_class).to have_received(:warn).with(/typo/)
    end
  end

  # tool_name carries no kind, so a member and a batch action of the same name
  # derive the same one. Advertising it twice would leave whichever the catalog
  # happened to find second permanently unreachable.
  describe "two tools that would share a name" do
    it "hides both rather than silently shadowing one" do
      allow(described_class).to receive(:warn)
      stub_resources(config(
        member: [action(:tag, mcp: { description: "Tag one" })],
        batch_actions: [batch(:tag, mcp: { description: "Tag the selected" })]
      ))

      expect(described_class.all).to be_empty
      expect(described_class).to have_received(:warn).with(/volunteer_tag/)
    end

    it "leaves the other tools of the same resource alone" do
      allow(described_class).to receive(:warn)
      stub_resources(config(
        member: [action(:tag, mcp: { description: "Tag one" }),
                 action(:create_warning, mcp: { description: "Record a warning" })],
        batch_actions: [batch(:tag, mcp: { description: "Tag the selected" })]
      ))

      expect(described_class.all.map(&:tool_name)).to eq(["volunteer_create_warning"])
    end

    it "catches a collision between two different resources, since tool names are global" do
      allow(described_class).to receive(:warn)
      stub_resources(
        config(member: [action(:tag, mcp: { description: "A", tool_name: "shared_name" })]),
        config(name: "Shift", member: [action(:tag, mcp: { description: "B", tool_name: "shared_name" })])
      )

      expect(described_class.all).to be_empty
    end
  end

  # ActiveAdmin derives a batch action's sym from a String title by mangling it
  # (titleize, strip spaces, underscore), which can leave punctuation in the
  # symbol. Applications generate these in loops from data, so requiring the
  # annotation to name the mangled symbol would be unusable.
  describe "a batch action declared with a String title" do
    it "matches an annotation that names the action by its title" do
      stub_resources(config(
        batch_actions: [batch(:"warning:_fridge_left_open", mcp: nil,
                              title: "Warning: Fridge left open", form: { note: :text })],
        annotations: [annotation("Warning: Fridge left open", kind: :batch, description: "Send a warning")]
      ))

      expect(described_class.all.map(&:description)).to eq(["Send a warning"])
    end

    it "still matches an annotation that names the symbol ActiveAdmin derived" do
      stub_resources(config(
        batch_actions: [batch(:"warning:_fridge_left_open", mcp: nil,
                              title: "Warning: Fridge left open")],
        annotations: [annotation(:"warning:_fridge_left_open", kind: :batch, description: "Send a warning")]
      ))

      expect(described_class.all.map(&:description)).to eq(["Send a warning"])
    end

    it "derives a usable tool name from a symbol carrying punctuation, rather than refusing it" do
      stub_resources(config(
        batch_actions: [batch(:"warning:_fridge_left_open", mcp: nil,
                              title: "Warning: Fridge left open")],
        annotations: [annotation("Warning: Fridge left open", kind: :batch, description: "Send a warning")]
      ))

      expect(described_class.all.map(&:tool_name)).to eq(["volunteer_warning_fridge_left_open"])
    end
  end
end
