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

## Project Setup
The images are stored in a private docker registry. To set the project up, you need to use your own images.
1. Build docker images for the main application and sidecar app
2. Publish the docker images
3. Update the deployment yaml file, replace the container images with your own image, and update the Application Insights instrumentation key
4. Run ```kubectl create -f WebFrontEndSidecar.yaml``` and that's it

If you have modified the yaml file and deploy.cmd file to your registry accordingly, then simply run ```deploy.cmd```.
