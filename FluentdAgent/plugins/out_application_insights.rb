#
# Copyright 2018- yantang
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/output'
require "application_insights"

module Fluent
  class ApplicationInsightsOutput < Output
    Fluent::Plugin.register_output("application_insights", self)

    attr_accessor :tc

    # The application insights instrumentation key
    config_param :instrumentation_key, :string
    # The batch size to send data to application insights service.
    config_param :send_buffer_size, :integer, default: 1000
    # The parameter indication whether the record is in standard schema. i.e., the format that can be 
    config_param :standard_schema, :bool, default: false
    # The property name for the message. It will be ignored the record is in standard schema.
    config_param :message_property, :string, default: 'message'
    # The property name for severity level. It will be ignored the record is in standard schema.
    config_param :severity_property, :string, default: 'severity'
    # TODO: add the support of the context_property.
    # One useful scenario is the kubernetes_logs input captures some logs in non standard schema, while it's decorated
    # with the application_insights_cloud_context filter plugin, it get some context thus can be updated.
    # config_param :cloud_role_name_property, :string, default: 'kubernetes.container_name'
    # config_param :cloud_role_instance_property, :string, default: 'kubernetes.pod_name'

    # The parameter indicating whether flatten the property if it's an object or array.
    # If it's not flattened, the value will become [object Object] in the final telemetry.
    # The property name will be concatenated by '_' if it's flattened.
    config_param :flatten_properties, :bool, default: true

    SEVERITY_LEVEL_MAPPING = {
      "verbose" => ApplicationInsights::Channel::Contracts::SeverityLevel::VERBOSE,
      "information" => ApplicationInsights::Channel::Contracts::SeverityLevel::INFORMATION,
      "warning" => ApplicationInsights::Channel::Contracts::SeverityLevel::WARNING,
      "error" => ApplicationInsights::Channel::Contracts::SeverityLevel::ERROR,
      "critical" => ApplicationInsights::Channel::Contracts::SeverityLevel::CRITICAL
    }

    STANDARD_SCHEMA_PROPS = ["name", "time", "iKey", "tags", "data"]

    def start
      super

      sender = ApplicationInsights::Channel::AsynchronousSender.new
      queue = ApplicationInsights::Channel::AsynchronousQueue.new sender
      channel = ApplicationInsights::Channel::TelemetryChannel.new nil, queue
      @tc = ApplicationInsights::TelemetryClient.new @instrumentation_key, channel
      @tc.channel.queue.max_queue_length = @send_buffer_size
      tc.channel.sender.send_buffer_size = @send_buffer_size
    end

    def shutdown
      super

      # Draining the events in the queue.
      # We need to make sure the work thread has finished. Otherwise, it's possible the queue is empty, but the http request to send the data is not finished.
      # However, a drawback of waiting the work thread to finish is even the events has been drained, it will still poll the queue for some time (default is 3 seconds, set by sender.send_time).
      # This can be improved if the SDK exposes another variable indicating whether the work thread is sending data or just polling the queue.
      while !tc.channel.queue.empty? || tc.channel.sender.work_thread != nil
        # It's possible the work thread has already exited but there are still items in the queue.
        # https://github.com/Microsoft/ApplicationInsights-Ruby/blob/master/lib/application_insights/channel/asynchronous_sender.rb#L115
        # Trigger flush to make the work thread working again in this case.
        if tc.channel.sender.work_thread == nil && !tc.channel.queue.empty?
          tc.flush
        end

        sleep(1)
      end
    end

    def process(tag, es)
      es.each { |time, record|
        if @standard_schema
          process_standard_schema_log record
        else
          process_non_standard_schema_log record
        end
      }
    end

    private

    def process_standard_schema_log(record)
      # TODO: The telemetry context is asscociated with the telemetry client instead of each telemetry.
      # By looking at the code, it will be assign to each telemetry as soon as track api is called, but make sure this is true.

      # TODO: The ruby sdk defined roleName and roleInstance in device context. While it seems like these properties has been moved to cloud context, which is missing in current AI ruby sdk.
      # The roleName and roleInstance is crucial for app map to work, need to check the schema later and update AI ruby sdk if necessary.
      tags = record["tags"]
      if tags != nil
        update_context(@tc.context, tags)
      end

      if record["data"] && record["data"]["baseType"] && record["data"]["baseData"]
        base_type = record["data"]["baseType"]
        base_data = record["data"]["baseData"]
        custom_properties = extract_properties(record, STANDARD_SCHEMA_PROPS)

        case base_type
        when "RequestData"
          # TODO: the "time" property will be removed by fluentd
          process_request_telemetry base_data, custom_properties, record["time"]
        when "RemoteDependencyData"
          process_dependency_telemetry base_data, custom_properties
        when "MessageData"
          process_trace_telemetry base_data, custom_properties
        when "ExceptionData"
          process_exception_telemetry base_data, custom_properties
        when "EventData"
          process_event_telemetry base_data, custom_properties
        # TODO: get an example and parse the data
        when "MetricData"
        when "PageViewData"
        when "AvailabilityData"
        else
          log.warn "Unknown telemetry type #{base_type}. Event will be treated as as non standard schema event."
          process_non_standard_schema_log record
        end
      else
        log.warn "The event does not meet the standard schema of application insights output. Missing property data, baseType or baseData. Event will be treated as as non standard schema event."
        process_non_standard_schema_log record
      end
    end

    # TODO: There is a breaking change in AI ruby SDK 0.5.4, where the mapping of json properties is defined in the contract.
    # This would greatly simplify the conversion logic to something like below, and we don't need to hardcode the property names but rely on the contract in AI sdk.
    # However, v0.5.4 is not released (the latest release in Jan 2015). We keep the logic here for future reference, considering we need to add role context to support App Map, a new release will be scheduled.
    def update_context_json_mapping(context, tags)
      [context.application,
      context.device,
      context.user,
      context.session,
      context.location,
      context.operation].each do |c|
        c.class.json_mappings.each do |attr, name|
          if (tags[name] != nil)
            c.send(:"#{attr}=", value)
          end
        end
      end
    end

    def update_context(context, tags)
      context.application.ver = tags["ai.application.ver"]
      context.application.build = tags["ai.application.build"]

      context.device.id = tags["ai.device.id"]
      context.device.ip = tags["ai.device.ip"]
      context.device.language = tags["ai.device.language"]
      context.device.locale = tags["ai.device.locale"]
      context.device.model = tags["ai.device.model"]
      context.device.network = tags["ai.device.network"]
      context.device.oem_name = tags["ai.device.oemName"]
      context.device.os = tags["ai.device.os"]
      context.device.os_version = tags["ai.device.osVersion"]
      context.device.role_instance = tags["ai.cloud.roleInstance"] || tags["ai.device.roleInstance"]
      context.device.role_name = tags["ai.cloud.roleName"] || tags["ai.device.roleName"]
      context.device.screen_resolution = tags["ai.device.screenResolution"]
      context.device.type = tags["ai.device.type"]
      context.device.machine_name = tags["ai.device.machineName"]

      context.user.account_acquisition_date = tags["ai.user.accountAcquisitionDate"]
      context.user.account_id = tags["ai.user.accountId"]
      context.user.user_agent = tags["ai.user.userAgent"]
      context.user.id = tags["ai.user.id"]
      context.user.store_region = tags["ai.user.storeRegion"]

      context.session.id = tags["ai.session.id"]
      context.session.is_first = tags["ai.session.isFirst"]
      context.session.is_new = tags["ai.session.isNew"]

      context.operation.id = tags["ai.operation.id"]
      context.operation.name = tags["ai.operation.name"]
      context.operation.parent_id = tags["ai.operation.parentId"]
      # TODO: no operation.rootId actually, the definition in the ruby sdk is not up to date
      context.operation.root_id = tags["ai.operation.rootId"]
      context.operation.synthetic_source = tags["ai.operation.syntheticSource"]
      context.operation.is_synthetic = tags["ai.operation.isSynthetic"]

      context.location.ip = tags["ai.location.ip"]

      # TODO: check the internal context, currently it will use the ruby sdk's context, but we probably want to override with the original internal context if it exists
      # TODO: grab an example of context properties and update accordingly
    end

    def process_request_telemetry(base_data, custom_properties, time)
      # TODO: Validate the parsing of measurements is correct
      http_method = base_data["properties"] ? base_data["properties"]["httpMethod"] : nil
      options = {
        :name => base_data["name"],
        :http_method => http_method,
        :url => base_data["url"],
        :properties => custom_properties.merge!(base_data["properties"] || {}),
        :measurements => base_data["measurements"]
      }
      @tc.track_request base_data["id"], time, base_data["duration"], base_data["responseCode"], base_data["success"], options
    end

    # TODO: There is no track_dependency in AI sdk, and the remote_dependency_data contract is also very different from the current schema (it's more like metric in the AI ruby sdk).
    def process_dependency_telemetry(base_data, custom_properties)
      options = {
        :name => base_data["name"],
        :data => base_data["data"],
        :target => base_data["target"],
        :type => base_data["type"],
        :properties => custom_properties.merge!(base_data["properties"] || {}),
        :measurements => base_data["measurements"]
      }
      
      @tc.track_dependency base_data["id"], base_data["duration"], base_data["resultCode"], base_data["success"], options
    end

    def process_trace_telemetry(base_data, custom_properties)
      severity_level = base_data["severityLevel"] ? SEVERITY_LEVEL_MAPPING[base_data["severityLevel"].downcase]: nil
      @tc.track_trace base_data["message"], severity_level, :properties => custom_properties.merge!(base_data["properties"] || {})
    end

    def process_exception_telemetry(base_data, custom_properties)
      # The track_exception accept an ruby exception object as the parameter.
      # Since we only have the json object, we need to parse it to Channel::Contracts::ExceptionDetails manually.
      exception_details = base_data["exceptions"]
      if !exception_details
        @tc.channel.write({}, @tc.context)
        log.warn "Event #{record} is treated as exception telemetry, but there is no exception details"
        return
      end

      parsed_exceptions = []
      exception_details.each do |exception|
        parsed_stack = []
        if exception["parsedStack"]
          exception["parsedStack"].each do |frame|
            stack_frame = Channel::Contracts::StackFrame.new
            stack_frame.assembly = frame["assembly"]
            stack_frame.file_name = frame["fileName"]
            stack_frame.level = frame["level"]
            stack_frame.line = frame['line']
            stack_frame.method = frame['method']
            parsed_stack << stack_frame
          end
        end

        details_attributes = {
          :id => exception["id"],
          :outer_id => exception["outerId"],
          :type_name => exception["typeName"],
          :message => exception["message"],
          :has_full_stack => exception["hasFullStack"],
          :stack => parsed_stack.map { |frame| "#{frame.file_name}:#{frame.line}:in `#{frame.method}'"}.join("\n"),
          :parsed_stack => parsed_stack
        }
        parsed_exceptions << (Channel::Contracts::ExceptionDetails.new details_attributes)
      end

      handledAt = base_data["properties"] ? base_data["properties"]["handledAt"] : nil
      data_attributes = {
        :handled_at => handledAt || base_data["handledAt"],
        :exceptions => parsed_exceptions,
        :properties => custom_properties.merge!(base_data["properties"] || {}),
        :measurements => base_data["measurements"] || {},
      }
      data = Channel::Contracts::ExceptionData.new data_attributes

      @tc.channel.write(data, @tc.context)
    end

    def process_event_telemetry(base_data, custom_properties)
      @tc.track_event base_data["name"], { :properties => custom_properties.merge!(base_data["properties"] || {}), :measurements => base_data["measurements"] }
    end

    def process_non_standard_schema_log(record)
      message = record[@message_property] || record.to_s
      severity_level = record[@severity_property] ? SEVERITY_LEVEL_MAPPING[record[@severity_property].downcase] : nil
      props = extract_properties(record, [@message_property, @severity_property])

      @tc.track_trace message, severity_level, :properties => props
    end

    def extract_properties(record, excluded_props, prop_prefix = nil)
      props = Hash.new

      record.each do |key, value|
        if excluded_props != nil && excluded_props.include?(key)
          next
        end

        if !@flatten_properties
          props[key] = value
          next
        end

        prop_name = prop_prefix ? "#{prop_prefix}_#{key}" : key
        if value.is_a?(Hash)
          props.merge!(extract_properties(value, nil, prop_name))
        elsif value.is_a?(Array)
          value.each_with_index do |arrayValue, index|
            indexed_prop_name = "#{prop_name}_#{index}"
            props.merge!(extract_properties(arrayValue, nil, indexed_prop_name))
          end
        else
          props[prop_name] = value
        end
      end

      props
    end

  end
end
