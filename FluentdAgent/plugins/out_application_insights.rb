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

        props = extract_metadata(record)

        message = record.to_s
        @tc.track_trace message, ApplicationInsights::Channel::Contracts::SeverityLevel::INFORMATION, :properties => props
      }
      chain.next
    end

    private

    # If we don't flatten the props, it will become [object Object] in AI telemetry
    def extract_metadata(record)
      props = Hash.new

      if(!record["docker"].nil?)
        record["docker"].each do |key, value|
          props[key] = value
        end
      end

      if(!record["kubernetes"].nil?)
        record["kubernetes"].each do |key, value|
          if (value.is_a?(Hash))
            # labels and annotations
            value.each do |key2, value2|
              props[key + "_" + key2] = value2
            end
          else
            props[key] = value
          end
        end
      end

      record.delete("docker")
      record.delete("kubernetes")
      props
    end

  end
end
