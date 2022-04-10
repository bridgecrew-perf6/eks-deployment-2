#!/bin/bash
kubectl -n traefik port-forward $(kubectl -n traefik get pods --selector "app.kubernetes.io/name=traefik" --output=name | head -n 1) 9000:9000
start localhost:9000/dashboard/