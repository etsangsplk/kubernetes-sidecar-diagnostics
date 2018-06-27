# kubernetes-sidecar-diagnostics
This project is the experimental effort to demonstrate the idea of using a sidecar container for logging in kubernetes, as apposed to node level logging (https://github.com/fluent/fluentd-kubernetes-daemonset)

The are couple yaml files you can easily deploy with
* WebFrontEnd

  This is an asp.net core application configured with Application Insights sdk. The AI sdk will capture interesting information like incoming / outgoing request, unhandled exceptions, etc. By default, AI sdk will send events to AI backend directly. But a custom HttpChannel is added in this app, making the SDK send events to the sidecar. An example of ILogger provider is also provided, which will reroute events from ILogger to the sidecar.
  
  Deploy this application and you can see how the sidecar work along with the main application.

* TestHttpLog

  This is for testing purpose, to demonstrate how the main application send data to the sidecar through the fluentd Http input plugin.

* TestFileLog

  This is for testing purpose, to demonstrate how the sidecar monitor log files of the main application.

* TestCustomConfig

  This is for testing purpose, to demonstrate how to provide a custom config file for the fluentd sidecar.

## Project Setup
The images are stored in a private docker registry. To set the project up, you need to use your own images.
1. Build docker images for the main application and sidecar app
2. Publish the docker images
3. Update the deployment yaml file, replace the container images with your own image, and update the Application Insights instrumentation key
4. Run ```kubectl create -f WebFrontEndSidecar.yaml``` and that's it

If you have modified the yaml file and deploy.cmd file to your registry accordingly, then simply run ```deploy.cmd```.

## Fluentd Sidecar Configurations
The fluentd sidecar is intended to enrich the logs with kubernetes metadata and forward to the Application Insights. Add the following snippet to the yaml file, update the configurations and that's it.
* `image` The sidecar docker image (TODO: this will be removed when we have a public one)
* `APPINSIGHTS_INSTRUMENTATIONKEY` The instrumentation key of Application Insights
* `source_container_name` The container name of the main application.

``` yaml
- name: fluentdsidecar
  image: <image>
  env:
    - name:  APPINSIGHTS_INSTRUMENTATIONKEY
      value: <instrumentation_key>
    - name: NAMESPACE_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: SOURCE_CONTAINER_NAME
      value: <source_container_name>
```

The sidecar image has three sources of inputs:  
1) Application console log, which is redirected by Kubernetes to a file in json format.
2) Http input plugin listening at port 8887 for Application Insights telemetry.
3) Tail input plugin where you can specify the files to monitor other than the one redirected by Kubernetes.

The reason of adding the http plugin is that you can hide some automatically generated logs, network traffic for example. And get the logs you're really interested in from console with no latency. If you want custom plugins, simply build new images based on this one, add the plugins you want and provide your custom config. And here is the full list of options of this sidecar, you can specify them through the envrionment variables:

* `APPINSIGHTS_INSTRUMENTATIONKEY` - Required. The instrumentation key of the Application Insights.
* `NAMESPACE_NAME` - The name space name where the application runs in. You can pass it through the [downward API](https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#the-downward-api).
* `POD_NAME` - The pod name where the application run in. You can pass it through the [downward API](https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/#the-downward-api).
* `SOURCE_CONTAINER_NAME` The container name of the main application. Unfortunately, this option can't be parameterized in yaml unless you using tools like [Helm](https://helm.sh/). So make sure it is set correctly, otherwise you will get unexpected result.
* `FLUENTD_OPT` - Fluentd [command line options](https://docs.fluentd.org/v1.0/articles/command-line-option). (default `''`)
* `APP_INSIGHTS_HTTP_CHANNEL_PORT` - The port of the http input plugin that is listening for Application Insights telemetry. (default `8887`)
* `SEND_SIDECAR_LOG` - Whether send the logs of the sidecar to the Application Insights. (default `false`)
* `SIDECAR_CONTAINER_NAME` - The container name of the side car. It's only used when `SEND_SIDECAR_LOG` is true. (default `fluentdsidecar`)
* `TAIL_INPUT_POS_FILE_DIR` - The directory of the tail input position file. (default `/var/log`)  
The default directory has the same lifespan as the container. So if the sidecar container restarts accidentally, you will have duplicated logs. To prevent that, you can set the directory to some persistent locations. For example, add a [emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/) volume, which has the same lifespan as the pod.
* `LOG_FILE_PATH` - The path of the files if the logs are saved in files, multiple paths can be specified. Here is the supported file [path format](https://docs.fluentd.org/v1.0/articles/in_tail#path). (default `''`)
* `LOG_FILE_EXCLUDE_PATH` - The path of the files to exclude. (default `''`)
* `FLUENTD_CUSTOM_CONF` - The custom configuration file. You can create a custom configuration file through [config map](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/). (TODO: link to a concreate example.)
