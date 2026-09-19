require "spec_helper"

RSpec.describe ActiveadminMcp::ActionDefinition do
  def build_config(name: "Volunteer")
    double("config", resource_class: double("model", name: name))
  end

  def member_action(name, mcp:, verb: :post)
    double("controller_action", name: name, http_verb: verb, mcp_options: mcp)
  end

  def batch_action(name, mcp:, form: nil, display_if: nil)
    double("batch_action", sym: name, mcp_options: mcp, inputs: form,
                           title: name.to_s.titleize, display_if_block: display_if)
  end

  it "returns nil when the action did not opt in" do
    action = member_action(:undocumented, mcp: nil)

    expect(described_class.build(config: build_config, action: action, kind: :member)).to be_nil
  end

  it "exposes the declared metadata and a namespaced tool name" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { reason: { type: :string, required: true } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).to have_attributes(
      kind: :member,
      action_name: :create_warning,
      resource_name: "Volunteer",
      tool_name: "volunteer_create_warning",
      description: "Record a warning",
      http_verb: :post
    )
    expect(definition.params).to eq(reason: { type: :string, required: true })
    expect(definition).to be_valid
  end

  it "inherits batch action param types from the ActiveAdmin form hash" do
    action = batch_action(:suspend, mcp: { description: "Suspend" }, form: { reason: :text, notify: :checkbox })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition.params).to eq(
      reason: { type: :string },
      notify: { type: :boolean }
    )
  end

  it "lets the mcp declaration layer hints over an inherited batch form type" do
    action = batch_action(:suspend, form: { reason: :text }, mcp: {
      description: "Suspend",
      params: { reason: { hint: "Shown to the volunteer" } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition.params).to eq(reason: { type: :string, hint: "Shown to the volunteer" })
  end

  it "properly handles acronyms and namespaced resource names in tool names" do
    action_acronym = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: {}
    })
    action_namespaced = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: {}
    })

    definition_acronym = described_class.build(
      config: build_config(name: "APIKey"),
      action: action_acronym,
      kind: :member
    )
    definition_namespaced = described_class.build(
      config: build_config(name: "Admin::Volunteer"),
      action: action_namespaced,
      kind: :member
    )

    expect(definition_acronym.tool_name).to eq("api_key_create_warning")
    expect(definition_namespaced.tool_name).to eq("admin_volunteer_create_warning")
  end

  it "is invalid when a param declares an unrecognised type" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { reason: { type: :wibble } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).not_to be_valid
    expect(definition.errors.first).to include("wibble")
  end

  it "is invalid without a description" do
    action = member_action(:create_warning, mcp: { params: {} })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).not_to be_valid
    expect(definition.errors.first).to include("description")
  end

  it "is invalid when a member action declares a param named id" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { id: { type: :integer } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param id is reserved/))
  end

  it "is invalid when a batch action declares a param named ids" do
    action = batch_action(:suspend, mcp: {
      description: "Suspend",
      params: { ids: { type: :array } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param ids is reserved/))
  end

  # ActiveAdmin's batch_action controller method slices submitted inputs down
  # to the declared form: keys, so a param declared only under mcp: would be
  # advertised, required, validated, encoded — and then dropped before the
  # block ever saw it.
  it "is invalid when a batch param is missing from the ActiveAdmin form hash" do
    action = batch_action(:suspend, form: { reason: :text }, mcp: {
      description: "Suspend",
      params: { reason: { hint: "Why" }, notify_manager: { type: :boolean, required: true } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param notify_manager is not among the batch action's declared form/))
  end

  it "is valid when every batch param is in the form hash" do
    action = batch_action(:suspend, form: { reason: :text, notify: :checkbox }, mcp: {
      description: "Suspend",
      params: { reason: { hint: "Why" } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).to be_valid
  end

  # With no form: hash, ActiveAdmin's batch_action controller calls
  # `inputs.slice(*nil.try(:keys))`, i.e. `slice()`, which drops every
  # submitted input. So a form-less batch action has an empty permitted set,
  # and declaring any param is a declaration error, not a free pass.
  it "is invalid when a form-less batch action declares any param" do
    action = batch_action(:suspend, form: nil, mcp: {
      description: "Suspend",
      params: { reason: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param reason/))
  end

  # A Proc form is evaluated by ActiveAdmin in controller context via
  # MethodOrProcHelper.render_in_context, so we cannot know its keys at
  # declaration time. We skip the check rather than guess, so this must not
  # be falsely rejected.
  it "does not reject a batch action whose form is a Proc" do
    action = batch_action(:suspend, form: -> { { reason: :text } }, mcp: {
      description: "Suspend",
      params: { reason: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).to be_valid
  end

  it "does not apply the batch form rule to member actions" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { reason: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).to be_valid
  end

  it "is valid when a collection action declares a param named id" do
    action = double("controller_action", name: :process, http_verb: :post, mcp_options: {
      description: "Process something",
      params: { id: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :collection)

    expect(definition).to be_valid
  end

  it "is valid when a member action declares a param named ids" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { ids: { type: :array } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).to be_valid
  end

  # An action shared by a concern may need a different tool name on each
  # resource, and one answering to several verbs needs one tool per verb.
  describe "naming and verb selection" do
    def build(mcp, verb: :post)
      described_class.new(
        config: build_config,
        action: member_action(:tag, mcp: mcp, verb: verb),
        kind: :member,
        options: mcp
      )
    end

    it "uses the tool name the declaration chose, in place of the derived one" do
      definition = build({ description: "Remove a tag", tool_name: "volunteer_untag" })

      expect(definition.tool_name).to eq("volunteer_untag")
      expect(definition).to be_valid
    end

    it "still derives a tool name when the declaration does not choose one" do
      expect(build({ description: "Tag" }).tool_name).to eq("volunteer_tag")
    end

    it "rejects a tool name that is not a usable MCP tool name" do
      definition = build({ description: "Tag", tool_name: "volunteer tag!" })

      expect(definition).not_to be_valid
      expect(definition.errors.join).to match(/tool_name/)
    end

    it "dispatches with the verb the declaration chose, when the action answers to several" do
      definition = build({ description: "Remove a tag", http_verb: :delete }, verb: %i[post delete])

      expect(definition.http_verb).to eq(:delete)
      expect(definition).to be_valid
    end

    it "still takes the action's first verb when the declaration does not choose one" do
      definition = build({ description: "Tag" }, verb: %i[post delete])

      expect(definition.http_verb).to eq(:post)
    end

    # Dispatching a verb the action never declared would route to nothing, or
    # worse, to a different branch of the action's own body.
    it "refuses a verb the action does not answer to" do
      definition = build({ description: "Tag", http_verb: :put }, verb: %i[post delete])

      expect(definition).not_to be_valid
      expect(definition.errors.join).to match(/put/)
    end

    it "ignores a declared verb on a batch action, which ActiveAdmin always posts" do
      definition = described_class.new(
        config: build_config,
        action: batch_action(:tag, mcp: nil),
        kind: :batch,
        options: { description: "Tag", http_verb: :delete }
      )

      expect(definition.http_verb).to eq(:post)
    end
  end
  # ActiveAdmin hides a batch action whose :if proc refuses. Exposing it over
  # MCP regardless would offer an action the admin UI itself will not show.
  describe "a batch action guarded by an :if proc" do
    it "exposes the proc so the caller can evaluate it in controller context" do
      guard = proc { false }
      definition = described_class.new(
        config: build_config, action: batch_action(:purge, mcp: nil, display_if: guard),
        kind: :batch, options: { description: "Purge" }
      )

      expect(definition.display_if).to be(guard)
    end

    it "has nothing to evaluate for a member action, which ActiveAdmin does not gate this way" do
      definition = described_class.new(
        config: build_config, action: member_action(:tag, mcp: nil),
        kind: :member, options: { description: "Tag" }
      )

      expect(definition.display_if).to be_nil
    end
  end
end
