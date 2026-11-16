# ArgoCD Setup Guide

## Install ArgoCD on K3s

```bash
# Create the argocd namespace
kubectl create namespace argocd

# Install ArgoCD using the official manifest
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all ArgoCD pods to be ready
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s
```

## Access the ArgoCD UI

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward the ArgoCD server to localhost
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open https://localhost:8080 in your browser
# Username: admin
# Password: (from the command above)
```

## Deploy the Application

```bash
# Apply the AppProject first (defines permissions)
kubectl apply -f argocd/project.yaml

# Apply the Application (starts GitOps sync)
kubectl apply -f argocd/application.yaml

# Check sync status
kubectl -n argocd get applications
```

## ArgoCD CLI (Optional)

```bash
# Install the CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# Login
argocd login localhost:8080 --username admin --password <password> --insecure

# Sync manually
argocd app sync devops-app

# Check app health
argocd app get devops-app
```

## How GitOps Works in This Project

1. Developer pushes code changes to `main` branch
2. Jenkins pipeline builds a new Docker image and pushes to DockerHub
3. Jenkins updates the image tag in `k8s/deployment.yaml`
4. ArgoCD detects the Git change and syncs to the K3s cluster
5. K3s performs a rolling update with zero downtime
