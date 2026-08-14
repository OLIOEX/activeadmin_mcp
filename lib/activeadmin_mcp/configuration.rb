# frozen_string_literal: true

module ActiveadminMcp
  class Configuration
    MOUNT_STRATEGIES = %i[prepend append none].freeze

    attr_accessor :authentication_method, :user_class, :current_user_method, :menu_parent, :mount_path,
                  :auth_header_name

    attr_reader :mount_strategy

    def initialize
      @authentication_method = nil
      @user_class = "User"
      @current_user_method = :current_admin_user
      @menu_parent = nil
      @mount_path = "/mcp"
      @mount_strategy = :prepend
      @auth_header_name = "Authorization"
    end

    def mount_strategy=(strategy)
      unless MOUNT_STRATEGIES.include?(strategy)
        raise ArgumentError, "Invalid mount strategy: #{strategy}. Must be one of: #{MOUNT_STRATEGIES.join(', ')}"
      end

      @mount_strategy = strategy
    end

    def authentication_enabled?
      authentication_method == :devise_token
    end
  end
end
