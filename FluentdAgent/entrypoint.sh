#!/bin/bash

set -e

if [[ -z ${POD_NAME} ]] ; then
   sed -i  '/POD_NAME/d' /fluentd/etc/${FLUENTD_CONF}
fi

if [[ -z ${NAMESPACE_NAME} ]] ; then
   sed -i  '/NAMESPACE_NAME/d' /fluentd/etc/${FLUENTD_CONF}
fi

exec fluentd -c /fluentd/etc/${FLUENTD_CONF} -p /fluentd/plugins ${FLUENTD_OPT}
