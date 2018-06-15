# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# This is a dedicated script to flatten the kubernetes metadata decorated by the fluent-plugin-kubernetes_metadata_filter.
# Thus we keep the format of the property names consistent and easy to query in Application Insights
def filter(tag, time, record)
  if (record['docker'] && record['docker'].is_a?(Hash) && record['docker']['container_id'])
    record['kubernetes_container_id'] = record['docker']['container_id']
    record['docker'].length == 1 ? record.delete('docker') : record['docker'].delete('container_id')
  end

  if (record["kubernetes"] && record["kubernetes"].is_a?(Hash))
    record["kubernetes"].each do |key, value|
      record["kubernetes_" + key] = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value
    end

    record.delete("kubernetes")
  end

  record
end