# frozen_string_literal: true

ActiveAdmin.register_page "MCP API Tokens" do
  menu label: "MCP Tokens", parent: ActiveadminMcp.config.menu_parent, priority: 100

  content do
    @tokens = ActiveadminMcp::ApiToken.where(user: send(ActiveadminMcp.config.current_user_method)).order(created_at: :desc)

    if flash[:mcp_raw_token]
      panel "New Token Created", class: "mcp-token-created" do
        para "Copy this token now — it will not be shown again:"
        pre flash[:mcp_raw_token], class: "mcp-raw-token"
      end
    end

    panel "Your MCP API Tokens" do
      table_for @tokens do
        column :name
        column(:created_at) { |t| l(t.created_at, format: :long) }
        column(:last_used_at) { |t| t.last_used_at ? l(t.last_used_at, format: :long) : "Never" }
        column "Actions" do |token|
          link_to "Revoke", admin_mcp_api_tokens_destroy_path(token_id: token.id),
                  method: :delete,
                  data: { confirm: "Revoke token '#{token.name}'?" },
                  class: "button small"
        end
      end

      if @tokens.empty?
        para "No tokens yet. Create one to authenticate MCP clients."
      end
    end

    panel "Create New Token" do
      form action: admin_mcp_api_tokens_create_path, method: :post do
        input type: :hidden, name: :authenticity_token, value: form_authenticity_token
        label "Token Name", for: :mcp_token_name
        input type: :text, name: "mcp_token[name]", id: :mcp_token_name, placeholder: "e.g., Claude Code laptop"
        input type: :submit, value: "Generate Token"
      end
    end
  end

  page_action :create, method: :post do
    token = ActiveadminMcp::ApiToken.create!(
      user: send(ActiveadminMcp.config.current_user_method),
      name: params[:mcp_token][:name].presence || "Unnamed token"
    )
    flash[:mcp_raw_token] = token.raw_token
    redirect_to admin_mcp_api_tokens_path()
  end

  page_action :destroy, method: :delete do
    token = ActiveadminMcp::ApiToken.where(user: send(ActiveadminMcp.config.current_user_method)).find(params[:token_id])
    token.destroy!
    flash[:notice] = "Token revoked."
    redirect_to admin_mcp_api_tokens_path()
  end
end
