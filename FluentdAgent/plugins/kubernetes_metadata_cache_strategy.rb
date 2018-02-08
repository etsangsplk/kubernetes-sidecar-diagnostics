#
# Fluentd Kubernetes Metadata Filter Plugin - Enrich Fluentd events with
# Kubernetes metadata
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
module KubernetesMetadata
  module CacheStrategy
    def get_pod_metadata
      metadata = {}
      metadata = @metadata_cache.fetch(:pod_metadata) do
        @stats.bump(:pod_metadata_cache_miss)
        fetch_pod_metadata(@namespace_name, @pod_name)
      end

      metadata.merge!(@metadata_cache.fetch(:namespace_metadata) do
        @stats.bump(:namespace_metadata_cache_miss)
        fetch_namespace_metadata(@namespace_name)
      end)

      metadata.delete_if{|k,v| v.nil?}
    end
  end
end
