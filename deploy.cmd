docker build .\WebFrontEnd -f .\WebFrontEnd\WebFrontEnd\Dockerfile -t yanmingacr.azurecr.io/webfrontend
docker push yanmingacr.azurecr.io/webfrontend

docker build .\FluentdAgent -t yanmingacr.azurecr.io/fluentdsidecar
docker push yanmingacr.azurecr.io/fluentdsidecar

kubectl delete services --all
kubectl delete deployments --all

kubectl create -f WebFrontEndSidecar.yaml