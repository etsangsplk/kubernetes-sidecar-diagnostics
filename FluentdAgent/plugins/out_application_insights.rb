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

require "fluent/output"
require "application_insights"

module Fluent
  class ApplicationInsightsOutput < Output
    Fluent::Plugin.register_output("application_insights", self)

    attr_accessor :tc
    # define helpers

    # desc?
    config_param :instrumentation_key, :string

    def configure(conf)
      super

      log.info "AI_ Configure: "  + @instrumentation_key
    end

    def start
      super

      # TODO: async channel or sync channel?
      @tc = ApplicationInsights::TelemetryClient.new @instrumentation_key
    end

    def shutdown
        super

        log.info "Shutting down application_insights output"
        @tc.flush
    end

    def emit(tag, es, chain)
      es.each { |time, record|
        message = record["log"]
        if (message != nil)
          # handle container log and extract useful information
          record.delete("log")
          record["tag"] = tag
        else
          # TODO: handle other logs based on concrete structure
          message = tag
        end

        record = flatten_container_log_props(record)

        @tc.track_trace message, ApplicationInsights::Channel::Contracts::SeverityLevel::INFORMATION, :properties => record
      }
      chain.next
    end

    private

    # If we don't flatten the props, it will become [object Object] in AI telemetry
    def flatten_container_log_props(record)
      props = Hash.new

      record.each do |key, value|
        if key == "kubernetes" || key == "docker"
          # TODO: handle "label" property and collision of key
          value.each do |key2, value2|
            props[key2] = value2
          end
        else
          props[key] = value
        end
      end

      props
    end

  end
end
