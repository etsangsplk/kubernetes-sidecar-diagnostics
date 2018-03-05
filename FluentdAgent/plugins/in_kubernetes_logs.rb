require 'kubeclient'

module Fluent
  class KubernetesLogsInput < Fluent::Input
    Fluent::Plugin.register_input('kubernetes_logs', self)
    K8_POD_CA_CERT = 'ca.crt'
    K8_POD_TOKEN = 'token'

    config_param :container_name, :string, default: nil
    config_param :pod_name, :string, default: nil
    config_param :namespace_name, :string, default: nil
    config_param :timestamp_file, :string, default: nil
    config_param :timestamp_written_interval, :time, default: 5
    config_param :tag, :string

    config_param :kubernetes_url, :string, default: nil
    config_param :apiVersion, :string, default: 'v1'
    config_param :client_cert, :string, default: nil
    config_param :client_key, :string, default: nil
    config_param :ca_file, :string, default: nil
    config_param :verify_ssl, :bool, default: true
    config_param :bearer_token_file, :string, default: nil
    config_param :secret_dir, :string, default: '/var/run/secrets/kubernetes.io/serviceaccount'

    def configure(conf)
      super

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
      end

      # TODO: check the parameter, if namespace name is provided, pod name and container name must be provided as well, unless there is only one.
      # If it's not provided, then default to the current container
      # Use Kubernetes default service account if we're in a pod.
      initialize_namespace_name

      pod = get_pod
      @pod_name = pod['metadata']['name']

      if @container_name.nil?
        pod['status']['containerStatuses'].each do |container|
            # TODO(yantang): check if the containerID will change if it restarts, or if it's possible the sidecar could fail to get the app container if the app container is slow to initialize
            # Drop the prefix of containerID, the format is docker://080dc8b76e049a2a910899af6238994063ad69e9567f0c20ede95c4d9699a112
            if container['containerID'][9..-1] == @container_id
              @container_name = container['name']
            end
        end
      end

    end

    def initialize_namespace_name
      if @namespace_name.nil?
        namespace_file = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'
        if (!File.exist?(namespace_file))
          raise Fluent::ConfigError, "File #{namespace_file} does not exist. Failed to get namespace name."
        end

        @namespace_name = File.read(namespace_file);
      end
    end

    def get_pod
      # cgroup format is something like: 11:cpuset:/docker/9eff9fc8c340f764725c3cee6d011a2d71c85fe456210d6683c01dff2880b110
      container_id_regexp = ".+/docker/(?<container_id>[^/]*)$"
      container_id_regexp_compiled = Regexp.compile(container_id_regexp)
      cgroup_file = '/proc/self/cgroup'
      cgroup_file_content = File.read(cgroup_file);
      match_data = cgroup_file_content.match(container_id_regexp_compiled)

      if match_data
        @container_id = match_data['container_id']
      else
        raise Fluent::ConfigError, "Failed to match container id in file #{cgroup_file} with regex #{container_id_regexp}"
      end

      @client.get_pods(namespace: @namespace_name).each do |pod|
        pod['status']['containerStatuses'].each do |container|
          if container['containerID'].end_with? @container_id
            return pod
          end
        end
      end
    end

    def start
      super

      thread = Thread.new {
        # TODO: error handling
        # TODO: pass the lastest timestamp so it doesn't always read from the start.
        watcher = @client.watch_pod_log(@pod_name, @namespace_name, container: @container_name)
        watcher.each do |line|
          # TODO: is there a way to tell it's from stdout, stderr? The log files has such information
          router.emit(tag, Fluent::Engine.now, { "log" => line })
        end
      }
      thread.abort_on_exception = true
    end

    def shutdown
      # TODO: Record the latest timestamp

      super
    end
  end
end