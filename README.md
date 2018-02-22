# kubernetes-sidecar-diagnostics
This project is the experimental effort to demonstrate the idea of using a sidecar container for logging in kubernetes, as apposed to node level logging (https://github.com/fluent/fluentd-kubernetes-daemonset)

The project consist of two containers.
 1) The main application container (.net core console app) simply send logs to some remote endpoint (the sidecar container).
 2) The sidecar container is a fluentd agent listening http request, enrich the event with kubernetes metadata and send to Azure Application Insights

## Project Setup
The images are stored in a private docker registry. To set the project up, you need to use your own images.
1. Build docker images for the main application and sidecar app
2. Publish the docker images
3. Update the deployment yaml file, replace the container images with your own image, and update the Application Insights instrumentation key
4. Run ```kubectl create -f WebFrontEndSidecar.yaml``` and that's it

If you have modified the yaml file and deploy.cmd file to your registry accordingly, then simply run ```deploy.cmd```.
