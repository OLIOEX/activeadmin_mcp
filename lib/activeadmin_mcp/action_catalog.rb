module ActiveadminMcp
  # Finds every ActiveAdmin action an application has opted in to MCP.
  #
  # Nothing is cached: ActiveAdmin reloads resources in development, and a
  # stale catalog would advertise tools that no longer exist.
  module ActionCatalog
    # Tool names the engine reserves for itself, including names Phase 2 and 3
    # will take, so an application cannot silently shadow one later.
    RESERVED = %w[list_resources query update create describe_form].freeze

    class << self
      # The authenticated user is carried through so a batch action's `form:`
      # proc can be evaluated in controller context, the way ActiveAdmin
      # evaluates it. Nothing here evaluates it — see ActionDefinition#params,
      # which does, lazily, once the caller has authorized the action.
      def all(current_user: nil)
        without_colliding_names(
          ResourceRegistry.resources.flat_map do |entry|
            definitions_for(entry[:config], current_user)
          end
        )
      end

      def find(tool_name, current_user: nil)
        all(current_user: current_user).find { |definition| definition.tool_name == tool_name }
      end

      private

      # A tool name carries no kind, so a member and a batch action of the same
      # name derive the same one — which ActiveAdmin allows, and a shared
      # concern declaring both is how it happens in practice. Advertising a
      # duplicate would leave whichever the catalog found second permanently
      # unreachable, since find returns the first match. Refuse both instead,
      # and say which name, so the declaration can choose a tool_name.
      def without_colliding_names(definitions)
        definitions.group_by(&:tool_name).flat_map do |tool_name, sharing|
          next sharing if sharing.one?

          warn_and_skip("#{sharing.length} actions would both be called #{tool_name}; " \
                        "give all but one an explicit tool_name:")
          []
        end
      end

      def definitions_for(config, current_user = nil)
        annotated, inline = partition_declarations(config)

        (annotated + inline).filter_map do |action, kind, options|
          definition = ActionDefinition.new(
            config: config, action: action, kind: kind, options: options, current_user: current_user
          )

          next warn_and_skip(definition.errors.join("; ")) unless definition.valid?
          next warn_and_skip("#{definition.tool_name} collides with a built-in tool") if reserved?(definition)

          definition
        end
      end

      # Resolves each mcp_action annotation to the action it names, and leaves
      # every unannotated action to its own inline mcp: declaration. An
      # annotation replaces an inline declaration wholesale rather than merging
      # into it: one declaration wins, and it is visible which.
      def partition_declarations(config)
        actions = candidates(config)
        annotated = []
        claimed = []

        safe_annotations(config).each do |annotation|
          matches = matching_actions(actions, annotation)

          next warn_and_skip(annotation_missing(config, annotation)) if matches.empty?
          next warn_and_skip(annotation_ambiguous(config, annotation)) unless matches.one?

          action, kind = matches.first
          claimed << action
          annotated << [action, kind, annotation[:options]]
        end

        inline = actions.filter_map do |action, kind|
          # By identity, not equality: ActiveAdmin::ControllerAction is
          # Comparable through a `priority` its instances do not all have, so
          # asking an Array whether it includes one can raise.
          next if claimed.any? { |claimed_action| claimed_action.equal?(action) }

          options = action.mcp_options
          [action, kind, options] if options.is_a?(Hash)
        end

        [annotated, inline]
      end

      def matching_actions(actions, annotation)
        wanted = annotation[:action_name].to_s

        actions.select do |action, kind|
          names_of(action, kind).include?(wanted) &&
            (annotation[:kind].nil? || annotation[:kind] == kind)
        end
      end

      # A batch action may be declared with a String title, from which
      # ActiveAdmin derives the symbol by titleizing, stripping spaces and
      # underscoring — which can leave punctuation in it. Applications generate
      # those in loops from data, so an annotation may name either the title it
      # wrote or the symbol ActiveAdmin made of it.
      def names_of(action, kind)
        names = [declared_name(action, kind).to_s]
        names << action.title.to_s if kind == :batch && action.respond_to?(:title)
        names
      end

      def declared_name(action, kind)
        (kind == :batch ? action.sym : action.name).to_sym
      end

      def annotation_missing(config, annotation)
        "#{resource_name(config)} annotates #{annotation[:action_name]}, which it does not declare"
      end

      def annotation_ambiguous(config, annotation)
        "#{resource_name(config)} annotates #{annotation[:action_name]}, which names more than one " \
          "action; say which with kind:"
      end

      def resource_name(config)
        config.resource_class.name
      end

      def safe_annotations(config)
        config.respond_to?(:mcp_annotations) ? Array(config.mcp_annotations) : []
      end

      def candidates(config)
        pairs = []
        pairs.concat(safe_actions(config, :member_actions).map { |a| [a, :member] })
        pairs.concat(safe_actions(config, :collection_actions).map { |a| [a, :collection] })
        pairs.concat(safe_actions(config, :batch_actions).map { |a| [a, :batch] }) if batch_enabled?(config)
        pairs.select { |action, _kind| action.respond_to?(:mcp_options) }
      end

      def safe_actions(config, reader)
        config.respond_to?(reader) ? Array(config.public_send(reader)) : []
      end

      # ActiveAdmin keeps registered batch actions even when the namespace has
      # batch actions switched off, and hides them in the UI. Match that.
      def batch_enabled?(config)
        return false unless config.respond_to?(:batch_actions_enabled?)

        config.batch_actions_enabled?
      end

      def reserved?(definition)
        RESERVED.include?(definition.tool_name)
      end

      def warn_and_skip(message)
        warn("[activeadmin_mcp] ignoring action: #{message}")
        nil
      end
    end
  end
end
