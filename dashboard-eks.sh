#!/bin/bash

aws eks update-kubeconfig --region=$(terraform output -json|jq -r '.eks_region.value') --name $(terraform output -json |jq -r '.eks_id.value')
echo "Your admin token will be:"
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}') | awk '/token:/ {print $2}'
echo "---------"
DASHBOARD_POD=$(kubectl get pods -n kubernetes-dashboard -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=kubernetes-dashboard" -o jsonpath="{.items[0].metadata.name}")
kubectl -n kubernetes-dashboard port-forward $DASHBOARD_POD 9090:9090
