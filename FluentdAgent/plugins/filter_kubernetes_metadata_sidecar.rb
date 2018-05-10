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

require_relative 'kubernetes_metadata_cache_strategy'
require_relative 'kubernetes_metadata_common'
require_relative 'kubernetes_metadata_stats'
require_relative 'kubernetes_metadata_watch_namespaces'
require_relative 'kubernetes_metadata_watch_pods'

module Fluent
  class KubernetesMetadataFilter < Fluent::Filter
    K8_POD_CA_CERT = 'ca.crt'
    K8_POD_TOKEN = 'token'

    include KubernetesMetadata::CacheStrategy
    include KubernetesMetadata::Common
    include KubernetesMetadata::WatchNamespaces
    include KubernetesMetadata::WatchPods

    Fluent::Plugin.register_filter('kubernetes_metadata_sidecar', self)

    config_param :source_container_name, :string
    config_param :pod_name, :string, default: nil
    config_param :namespace_name, :string, default: nil
    config_param :kubernetes_url, :string, default: nil
    config_param :cache_size, :integer, default: 1000
    config_param :cache_ttl, :integer, default: 60 * 60
    config_param :watch, :bool, default: true
    config_param :apiVersion, :string, default: 'v1'
    config_param :client_cert, :string, default: nil
    config_param :client_key, :string, default: nil
    config_param :ca_file, :string, default: nil
    config_param :verify_ssl, :bool, default: true
    config_param :bearer_token_file, :string, default: nil
    config_param :secret_dir, :string, default: '/var/run/secrets/kubernetes.io/serviceaccount'
    config_param :de_dot, :bool, default: true
    config_param :de_dot_separator, :string, default: '_'

    config_param :annotation_match, :array, default: []
    config_param :stats_interval, :integer, default: 30
    config_param :allow_orphans, :bool, default: true
    config_param :orphaned_namespace_name, :string, default: '.orphaned'
    config_param :orphaned_namespace_id, :string, default: 'orphaned'

    def fetch_pod_metadata(namespace_name, pod_name)
      log.trace("fetching pod metadata: #{namespace_name}/#{pod_name}") if log.trace?
      begin
        metadata = @client.get_pod(pod_name, namespace_name)
        unless metadata
          log.trace("no metadata returned for: #{namespace_name}/#{pod_name}") if log.trace?
          @stats.bump(:pod_cache_api_nil_not_found)
        else
          begin
            log.trace("raw metadata for #{namespace_name}/#{pod_name}: #{metadata}") if log.trace?
            metadata = parse_pod_metadata(metadata)
            @stats.bump(:pod_cache_api_updates)
            log.trace("parsed metadata for #{namespace_name}/#{pod_name}: #{metadata}") if log.trace?
            @metadata_cache[:pod_metadata] = metadata
            return metadata
          rescue Exception=>e
            log.debug(e)
            @stats.bump(:pod_cache_api_nil_bad_resp_payload)
            log.trace("returning empty metadata for #{namespace_name}/#{pod_name} due to error") if log.trace?
          end
        end
      rescue KubeException=>e
        @stats.bump(:pod_cache_api_nil_error)
        log.debug "Exception encountered fetching pod metadata from Kubernetes API #{@apiVersion} endpoint #{@kubernetes_url}: #{e.message}"
      end
      {}
    end

    def fetch_namespace_metadata(namespace_name)
      log.trace("fetching namespace metadata: #{namespace_name}") if log.trace?
      begin
        metadata = @client.get_namespace(namespace_name)
        unless metadata
            log.trace("no metadata returned for: #{namespace_name}") if log.trace?
            @stats.bump(:namespace_cache_api_nil_not_found)
        else
          begin
            log.trace("raw metadata for #{namespace_name}: #{metadata}") if log.trace?
            metadata = parse_namespace_metadata(metadata)
            @stats.bump(:namespace_cache_api_updates)
            log.trace("parsed metadata for #{namespace_name}: #{metadata}") if log.trace?
            @metadata_cache[:namespace_metadata] = metadata
            return metadata
          rescue Exception => e
            log.debug(e)
            @stats.bump(:namespace_cache_api_nil_bad_resp_payload)
            log.trace("returning empty metadata for #{namespace_name} due to error") if log.trace?
          end
        end
      rescue KubeException => kube_error
        @stats.bump(:namespace_cache_api_nil_error)
        log.debug "Exception encountered fetching namespace metadata from Kubernetes API #{@apiVersion} endpoint #{@kubernetes_url}: #{kube_error.message}"
      end
      {}
    end

    def initialize
      super
      @prev_time = Time.now
    end

    def configure(conf)
      super

      def log.trace?
        level == Fluent::Log::LEVEL_TRACE
      end

      require 'kubeclient'
      require 'active_support/core_ext/object/blank'
      require 'lru_redux'
      @stats = KubernetesMetadata::Stats.new

      if @de_dot && (@de_dot_separator =~ /\./).present?
        raise Fluent::ConfigError, "Invalid de_dot_separator: cannot be or contain '.'"
      end

      if @cache_ttl < 0
        log.info "Setting the cache TTL to :none because it was <= 0"
        @cache_ttl = :none
      end

      @metadata_cache = LruRedux::TTL::ThreadSafeCache.new(@cache_size, @cache_ttl)

      # Use Kubernetes default service account if we're in a pod.
      if @kubernetes_url.nil?
        env_host = ENV['KUBERNETES_SERVICE_HOST']
        env_port = ENV['KUBERNETES_SERVICE_PORT']
        if env_host.present? && env_port.present?
          @kubernetes_url = "https://#{env_host}:#{env_port}/api"
        end
      end

      # Use SSL certificate and bearer token from Kubernetes service account.
      if Dir.exist?(@secret_dir)
        ca_cert = File.join(@secret_dir, K8_POD_CA_CERT)
        pod_token = File.join(@secret_dir, K8_POD_TOKEN)

        if !@ca_file.present? and File.exist?(ca_cert)
          @ca_file = ca_cert
        end

        if !@bearer_token_file.present? and File.exist?(pod_token)
          @bearer_token_file = pod_token
        end
      end

      if @kubernetes_url.present?

        ssl_options = {
            client_cert: @client_cert.present? ? OpenSSL::X509::Certificate.new(File.read(@client_cert)) : nil,
            client_key:  @client_key.present? ? OpenSSL::PKey::RSA.new(File.read(@client_key)) : nil,
            ca_file:     @ca_file,
            verify_ssl:  @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
        }

        auth_options = {}

        if @bearer_token_file.present?
          bearer_token = File.read(@bearer_token_file)
          auth_options[:bearer_token] = bearer_token
        end

        @client = Kubeclient::Client.new @kubernetes_url, @apiVersion,
                                         ssl_options: ssl_options,
                                         auth_options: auth_options

        begin
          @client.api_valid?
        rescue KubeException => kube_error
          raise Fluent::ConfigError, "Invalid Kubernetes API #{@apiVersion} endpoint #{@kubernetes_url}: #{kube_error.message}"
        end

        if @watch
          thread = Thread.new(self) { |this| this.start_pod_watch }
          thread.abort_on_exception = true
          namespace_thread = Thread.new(self) { |this| this.start_namespace_watch }
          namespace_thread.abort_on_exception = true
        end
      end

      @annotations_regexps = []
      @annotation_match.each do |regexp|
        begin
          @annotations_regexps << Regexp.compile(regexp)
        rescue RegexpError => e
          log.error "Error: invalid regular expression in annotation_match: #{e}"
        end
      end

      # # NOTE: cgroup file is not reliable, pass it through downward API only
      # initialize_namespace_name
      # pod = get_pod
      # @pod_name = pod['metadata']['name']

      if !@namespace_name || !@pod_name
        raise Fluent::ConfigError, "namespace_name and pod_name can't be nil. You can pass it through downwardAPI"
      end

      pod = @client.get_pod(@pod_name, @namespace_name)
      pod['status']['containerStatuses'].each do |container|
        if container['name'] == @source_container_name
          # TODO(yantang): check if the containerID will change if it restarts, or if it's possible the sidecar could fail to get the app container if the app container is slow to initialize
          # Drop the prefix of containerID, the format is docker://080dc8b76e049a2a910899af6238994063ad69e9567f0c20ede95c4d9699a112
          @source_container_id = container['containerID'][9..-1]
        end
      end
    end

    # # NOTE: the cgroup file is not reliable (doesn't exist on windows and format can be changed. We have seen it get changed at least 2 times)
    # def initialize_namespace_name
    #   # TODO: validate namespace_name. If an invalid namespace is provided get_pod will return something and become harder to debug
    #   if @namespace_name.nil?
    #     namespace_file = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'
    #     if (!File.exist?(namespace_file))
    #       raise Fluent::ConfigError, "File #{namespace_file} does not exist. Failed to get namespace name."
    #     end

    #     @namespace_name = File.read(namespace_file);
    #   end
    # end

    # def get_pod
    #   # cgroup format is something like: 11:cpuset:/docker/9eff9fc8c340f764725c3cee6d011a2d71c85fe456210d6683c01dff2880b110
    #   container_id_regexp = ".+/docker/(?<container_id>[^/]*)$"
    #   container_id_regexp_compiled = Regexp.compile(container_id_regexp)
    #   cgroup_file = '/proc/self/cgroup'
    #   cgroup_file_content = File.read(cgroup_file);
    #   match_data = cgroup_file_content.match(container_id_regexp_compiled)

    #   if match_data
    #     container_id = match_data['container_id']
    #   else
    #     raise Fluent::ConfigError, "Failed to match container id in file #{cgroup_file} with regex #{container_id_regexp}"
    #   end

    #   @client.get_pods(namespace: @namespace_name).each do |pod|
    #     pod['status']['containerStatuses'].each do |container|
    #       # TODO: container['containerID'] can be nil (e.g., wrong namespace name, sidecar container started first). May also happen for other places, need careful nil checking.
    #       if container['containerID'].end_with? container_id
    #         return pod
    #       end
    #     end
    #   end

    #   return nil
    # end

    def get_metadata_for_record
      metadata = {
        'container_name' => @source_container_name,
        'namespace_name' => @namespace_name,
        'pod_name'       => @pod_name
      }
      if @kubernetes_url.present?
        pod_metadata = get_pod_metadata
        metadata.merge!(pod_metadata) if pod_metadata
      end
      metadata
    end

    def filter_stream(tag, es)
      new_es = MultiEventStream.new

      metadata = {
        'docker' => {
          'container_id' => @source_container_id
        },
        'kubernetes' => get_metadata_for_record
      }

      es.each do |time, record|
        record = record.merge(Marshal.load(Marshal.dump(metadata))) if metadata
        new_es.add(time, record)
      end

      dump_stats
      new_es
    end

    def dump_stats
      @curr_time = Time.now
      return if @curr_time.to_i - @prev_time.to_i < @stats_interval
      @prev_time = @curr_time
      log.info(@stats)
      if log.level == Fluent::Log::LEVEL_TRACE
        log.trace("metadata cache: #{@metadata_cache.to_a}")
      end
    end

    def de_dot!(h)
      h.keys.each do |ref|
        if h[ref] && ref =~ /\./
          v = h.delete(ref)
          newref = ref.to_s.gsub('.', @de_dot_separator)
          h[newref] = v
        end
      end
    end

  end
end
