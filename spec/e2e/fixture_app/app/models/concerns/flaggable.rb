# A shared concern in the shape applications use when several resources need
# the same actions: the DSL calls live in self.included and are shared verbatim
# by every resource that includes it, so none of them can carry an `mcp:` key
# without describing every resource identically. A resource annotates them with
# `mcp_action` instead.
#
# Between them these declarations cover every way such a concern is written:
#
#   * the same name used for both a member and a batch action
#   * a member action answering to two verbs, one undoing the other
#   * a collection action
#   * a batch action whose `form:` is a proc rather than a hash
#   * batch actions generated in a loop from data, titled with a String, whose
#     symbols ActiveAdmin derives by mangling that title
#   * a batch action ActiveAdmin hides behind an `:if` proc
#   * a controller `before_action` guarding the batch dispatch
#
# It lives under app/models/concerns rather than app/admin only because
# ActiveAdmin excludes app/admin from the autoload paths; nothing about the
# concern depends on where it sits.
module Flaggable
  WARNING_REASONS = ["Fridge left open", "Past use by date"].freeze

  def self.included(dsl)
    dsl.send(:member_action, :flag, method: [:post, :delete]) do
      if request.delete?
        resource.update!(status: "unflagged")
        redirect_to resource_path(resource), notice: "Flag removed"
      else
        resource.update!(status: "flagged:#{params[:reason]}")
        redirect_to resource_path(resource), notice: "Flagged"
      end
    end

    dsl.send(:collection_action, :clear_flags, method: :post) do
      active_admin_config.resource_class.where("status LIKE 'flagged:%'").update_all(status: "draft")
      redirect_to collection_path, notice: "Flags cleared"
    end

    dsl.send(:batch_action, :flag, form: proc { { reason: :text, notify: :checkbox } }) do |ids, inputs|
      active_admin_config.resource_class.where(id: ids).update_all(status: "flagged:#{inputs['reason']}")
      redirect_to collection_path, notice: "Flagged #{ids.size}"
    end

    WARNING_REASONS.each do |reason|
      dsl.send(:batch_action, "Warning: #{reason}", confirm: "Send a warning?") do |ids|
        active_admin_config.resource_class.where(id: ids).update_all(status: "warned:#{reason}")
        redirect_to collection_path, notice: "Warned #{ids.size}"
      end
    end

    dsl.send(:batch_action, :purge, if: proc { current_admin_user&.email == "superuser@example.com" }) do |ids|
      active_admin_config.resource_class.where(id: ids).delete_all
      redirect_to collection_path, notice: "Purged"
    end

    dsl.send(:batch_action, :guarded_flag) do |ids|
      active_admin_config.resource_class.where(id: ids).update_all(status: "guarded")
      redirect_to collection_path, notice: "Guarded"
    end

    dsl.controller do
      before_action(only: :batch_action) do
        if params[:batch_action] == "guarded_flag"
          redirect_to collection_path, alert: "Refused by the concern's before_action"
        end
      end
    end
  end
end
