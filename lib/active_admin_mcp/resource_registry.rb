# frozen_string_literal: true

module ActiveAdminMcp
  module ResourceRegistry
    class << self
      def all
        discover.map { |r| resource_info(r) }
      end

      def find(name)
        resource = discover.find { |r| r.resource_class.name == name }
        return unless resource

        { name: resource.resource_class.name, model: resource.resource_class, config: resource }
      end

      private

      def discover
        return [] unless defined?(ActiveAdmin)

        ActiveAdmin.application.namespaces[:admin]&.resources&.select do |r|
          r.respond_to?(:resource_class) &&
            r.resource_class.respond_to?(:ransack) &&
            r.resource_class.table_exists?
        end || []
      end

      def resource_info(resource)
        klass = resource.resource_class
        {
          name: klass.name,
          table: klass.table_name,
          attributes: klass.column_names - sensitive_attributes,
        }
      end

      def sensitive_attributes
        %w[encrypted_password password_digest reset_password_token api_key secret]
      end
    end
  end
end
