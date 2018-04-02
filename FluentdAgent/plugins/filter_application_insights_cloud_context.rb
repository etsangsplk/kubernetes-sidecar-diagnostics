#
# Fluentd Application Insights Cloud Context Filter Plugin
# This is a dedicated small plugin to support the Application Insights app map feature by setting the property of cloud context.
#
# Copyright 2017 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Fluent
  class ApplicationInsightsCloudContextFilter < Fluent::Filter
    Fluent::Plugin.register_filter('application_insights_cloud_context', self)

    config_param :role_name, :string, default: nil
    config_param :role_instance, :string, default: nil
    config_param :role_name_property, :string, default: nil
    config_param :role_instance_property, :string, default: nil

    # Whether create a "tags" property if it doesn't exist. The cloud context is inside the "tags" property. 
    config_param :force, :bool, default: false
    # Whether override the existing value
    config_param :override, :bool, default: false

    def initialize
      super
      @prev_time = Time.now
    end

    def configure(conf)
      super

      if @role_name && @role_name_property
        raise Fluent::ConfigError, "Only one of the role_name, role_name_property parameter can be set."
      end

      if @role_instance && @role_instance_property
        raise Fluent::ConfigError, "Only one of the role_instance, role_instance_property parameter can be set."
      end

      if role_name_property
        @role_name_path = parse_property_path role_name_property
      end

      if role_instance_property
        @role_instance_path = parse_property_path role_instance_property
      end
    end

    def filter_stream(tag, es)
      new_es = MultiEventStream.new

      es.each do |time, record|
        set_role_name record
        set_role_instance record
        new_es.add(time, record)
      end

      new_es
    end

    private

    # Property path schema is prop1.prop2.#0, where #0 means the first element of an array.
    # For an index propery path, it can only start with # and the suffix as a valid integer. All other cases will make it a property name.
    def parse_property_path(property_path)
      result = property_path.split('.')
      result.each_with_index do |property, index|
        begin
          if property[0] == '#'
            result[index] = Integer(property[1..- 1])
          end
        rescue
        end
      end

      return result
    end

    def set_role_name(record)
      if @role_name_property
        @role_name = fetch_property record, @role_name_path
      end

      if !record["tags"]
        if !@force
          log.warn "tags property doesn't exist, skipping decorating"
          return
        else
          record["tags"] = {}
        end
      end

      if !record["tags"]["ai.cloud.role"] || @override
        record["tags"]["ai.cloud.role"] = @role_name
      end
    end

    def set_role_instance(record)
      if @role_name_property
        @role_instance = fetch_property record, @role_instance_path
      end

      if !record["tags"]
        if !@force
          log.warn "tags property doesn't exist, skipping decorating application insights cloud context"
          return
        else
          record["tags"] = {}
        end
      end

      if !record["tags"]["ai.cloud.roleInstance"] || @override
        record["tags"]["ai.cloud.roleInstance"] = @role_instance
      end
    end

    def fetch_property(record, property_path)
      property = record
      property_path.each do |path|
        if property.is_a?(Hash) && path.is_a?(String)
            property = property[path]
        elsif property.is_a?(Array) && path.is_a?(Integer)
            property = property[path]
        else
          log.warn "Failed to fetch property path #{property_path.join('.')} for event: #{record.to_s}"
          return nil
        end
      end

      return property
    end

  end
end