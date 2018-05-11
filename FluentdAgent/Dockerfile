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
    && gem install fluent-plugin-systemd \
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

# Environment variables
ENV FLUENTD_OPT=""
ENV FLUENT_UID=0

# jemalloc is memory optimization only available for td-agent
# td-agent is provided and QA'ed by treasuredata as rpm/deb/.. package
# -> td-agent (stable) vs fluentd (edge)
#ENV LD_PRELOAD="/usr/lib/libjemalloc.so.2"

# Run Fluentd
CMD ["/fluentd/entrypoint.sh"]
