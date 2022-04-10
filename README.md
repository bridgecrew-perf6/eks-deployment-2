# playground deployment

To Deploy the play ground you need to run in two steps. The first installs the EKS and give permissions for the new cluster. The second part deploys all core services for the cluster.

To deploy the cluster use the shell script `run-apply.sh`. This helper script, first runs the deployment of the first stage, than run the second stage.

