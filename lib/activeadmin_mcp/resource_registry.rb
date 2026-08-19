# frozen_string_literal: true

module ActiveadminMcp
  module ResourceRegistry
    class << self
      def all
        resources.map { |entry| resource_info(entry) }
      end

      def resources
        discover.map { |r| entry(r) }
      end

      def find(name)
        resources.find { |entry| entry[:name] == name }
      end

      def resource_info(entry)
        klass = entry[:model]
        {
          name: klass.name,
          table: klass.table_name,
          attributes: klass.column_names - sensitive_attributes,
        }
      end

      def sensitive_attributes
        %w[encrypted_password password_digest reset_password_token api_key secret]
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

      def entry(resource)
        { name: resource.resource_class.name, model: resource.resource_class, config: resource }
      end
    end
  end
end
