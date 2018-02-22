docker build .\WebFrontEnd -f .\WebFrontEnd\WebFrontEnd\Dockerfile -t yanmingacr.azurecr.io/webfrontend
docker push yanmingacr.azurecr.io/webfrontend

docker build .\FluentdAgent -t yanmingacr.azurecr.io/fluentai
docker push yanmingacr.azurecr.io/fluentai

kubectl delete services --all
kubectl delete deployments --all

kubectl create -f WebFrontEndSidecar.yaml