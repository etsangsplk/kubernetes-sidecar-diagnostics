FROM fluent/fluentd:v1.1.2-debian

MAINTAINER Azure Diagnostics <azdiag@microsoft.com>
USER root

# TODO: install our k8s metatada sidecar filter, instead of the general filter based on file name
RUN buildDeps="sudo make gcc g++ libc-dev ruby-dev libffi-dev" \
     && apt-get update \
     && apt-get upgrade -y \
     && apt-get install \
     -y --no-install-recommends \
     $buildDeps \
    && echo 'gem: --no-document' >> /etc/gemrc \
    && gem install fluent-plugin-secure-forward \
    && gem install fluent-plugin-record-reformer \
    && gem install fluent-plugin-kubernetes_metadata_filter \
    && gem install fluent-plugin-application-insights \
    && gem install ffi \
    && gem install fluent-plugin-systemd -v 0.0.8 \
    && SUDO_FORCE_REMOVE=yes \
    apt-get purge -y --auto-remove \
                  -o APT::AutoRemove::RecommendsImportant=false \
                  $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
    && gem sources --clear-all \
    && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

# Copy configuration files
COPY ./conf/ /fluentd/etc/

# Copy plugins
COPY ./plugins/ /fluentd/plugins/
COPY entrypoint.sh /fluentd/entrypoint.sh

# There are some problems with AI ruby sdk 0.5.3, e.g, can't track dependency, no cloud context. So we tweak the source code and override the file inside the container to make the sidecar work.
copy ./sdkhack/telemetry_client.rb /var/lib/gems/2.3.0/gems/application_insights-0.5.3/lib/application_insights/telemetry_client.rb
copy ./sdkhack/remote_dependency_data.rb /var/lib/gems/2.3.0/gems/application_insights-0.5.3/lib/application_insights/channel/contracts/remote_dependency_data.rb

# Environment variables
ENV FLUENTD_OPT=""

# jemalloc is memory optimization only available for td-agent
# td-agent is provided and QA'ed by treasuredata as rpm/deb/.. package
# -> td-agent (stable) vs fluentd (edge)
#ENV LD_PRELOAD="/usr/lib/libjemalloc.so.2"

# Run Fluentd
CMD ["/fluentd/entrypoint.sh"]
