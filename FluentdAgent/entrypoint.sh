#!/bin/bash

set -e

if [[ -z ${FLUENTD_CUSTOM_CONF} ]]; then
    if [[ -z ${POD_NAME} ]]; then
    sed -i  '/POD_NAME/d' /fluentd/etc/fluent.conf
    fi

    if [[ -z ${NAMESPACE_NAME} ]]; then
    sed -i  '/NAMESPACE_NAME/d' /fluentd/etc/fluent.conf
    fi

    if [[ -z ${LOG_FILE_PATH} ]]; then
        sed -i  '/@include file.conf/d' /fluentd/etc/fluent.conf
    fi

    exec fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins ${FLUENTD_OPT}
else
    exec fluentd -c ${FLUENTD_CUSTOM_CONF} -p /fluentd/plugins ${FLUENTD_OPT}
fi

