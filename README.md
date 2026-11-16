# Complete DevOps Deployment Project

A production-grade DevOps project that takes a simple Node.js application through the full deployment lifecycle — from infrastructure provisioning to GitOps-driven Kubernetes deployments.

The application is intentionally minimal. The real value is the **platform around it**: CI/CD pipelines, infrastructure as code, configuration management, container orchestration, and GitOps.

---

## Architecture Overview

```
Developer → Git Push → Jenkins CI/CD → DockerHub → ArgoCD → K3s Cluster
                              │
                    Terraform (AWS Infra)
                              │
                    Ansible (K3s Setup)
```

### How It Works

1. **Terraform** provisions AWS infrastructure (VPC, EC2 instances, security groups)
2. **Ansible** configures the EC2 instances and installs K3s (lightweight Kubernetes)
3. **Jenkins** builds the Docker image, scans for vulnerabilities, pushes to DockerHub
4. **ArgoCD** watches the Git repository and automatically deploys changes to K3s
5. **K3s** runs the application with rolling updates and health checks

---

## Tech Stack

| Tool | Purpose | Directory |
|------|---------|-----------|
| **Docker** | Containerise the application | `Dockerfile`, `docker-compose.yml` |
| **Jenkins** | CI/CD pipeline (build, scan, push) | `devops_tools/jenkins/` |
| **Terraform** | AWS infrastructure provisioning | `terraform/` |
| **Ansible** | Server configuration and K3s install | `ansible/` |
| **K3s** | Lightweight Kubernetes cluster | `k8s/` |
| **ArgoCD** | GitOps continuous deployment | `argocd/` |
| **AWS** | Cloud provider (VPC, EC2) | `terraform/` |
| **Trivy** | Container image vulnerability scanning | Integrated in Jenkins |
| **Buildah** | Rootless container image builds | Integrated in Jenkins |

---

## Application

A Node.js HTTP service built with Express.js:

| Endpoint | Purpose |
|----------|---------|
| `GET /` | Server information (port, environment) |
| `GET /health` | Health check (used by K8s probes) |

---

## Repository Layout

```
.
├── app.js                          # Express.js routes
├── index.js                        # Application entry point
├── package.json                    # Node.js dependencies
├── Dockerfile                      # Multi-stage container build
├── docker-compose.yml              # Local development setup
├── Makefile                        # CLI shortcuts for Docker
│
├── terraform/                      # AWS Infrastructure as Code
│   ├── providers.tf                # AWS provider and backend config
│   ├── variables.tf                # Input variables
│   ├── vpc.tf                      # VPC, subnets, IGW, routes
│   ├── security-groups.tf          # Firewall rules for K3s
│   ├── ec2.tf                      # Master and worker instances
│   ├── outputs.tf                  # IPs and SSH commands
│   └── terraform.tfvars.example    # Example variable values
│
├── ansible/                        # Configuration Management
│   ├── ansible.cfg                 # Ansible settings
│   ├── inventory/
│   │   └── hosts.ini.example       # Example inventory
│   ├── playbooks/
│   │   └── site.yml                # Main playbook entry point
│   └── roles/
│       ├── common/                 # Base packages, kernel tuning
│       ├── k3s-master/             # K3s server installation
│       └── k3s-worker/             # K3s agent join cluster
│
├── k8s/                            # Kubernetes Manifests
│   ├── namespace.yaml              # App namespace
│   ├── deployment.yaml             # Pod spec with health probes
│   ├── service.yaml                # ClusterIP service
│   ├── ingress.yaml                # Traefik ingress routing
│   └── hpa.yaml                    # Horizontal Pod Autoscaler
│
├── argocd/                         # GitOps Configuration
│   ├── project.yaml                # ArgoCD project (RBAC)
│   ├── application.yaml            # ArgoCD app (sync config)
│   └── README.md                   # ArgoCD setup guide
│
└── devops_tools/
    └── jenkins/
        ├── Jenkinsfile             # CI/CD pipeline definition
        ├── docker-compose.yml      # Jenkins server setup
        └── .env                    # Jenkins environment (not committed)
```

---

## Getting Started

### Prerequisites

- AWS account with IAM credentials configured (`aws configure`)
- Terraform >= 1.5.0
- Ansible >= 2.15
- Docker and Docker Compose
- SSH key pair created in AWS (`key_pair_name`)

### Step 1 — Provision AWS Infrastructure

```bash
cd terraform

# Copy and edit the variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialise, plan, and apply
terraform init
terraform plan
terraform apply
```

Note the output IPs — you need them for Ansible.

### Step 2 — Configure Servers with Ansible

```bash
cd ansible

# Create inventory from the example
cp inventory/hosts.ini.example inventory/hosts.ini
# Replace MASTER_PUBLIC_IP and WORKER_PUBLIC_IP with Terraform outputs

# Run the full setup
ansible-playbook playbooks/site.yml
```

This installs K3s on the master and joins the worker to the cluster.

### Step 3 — Install ArgoCD

```bash
# SSH into the master node
ssh -i ~/.ssh/your-key.pem ubuntu@MASTER_IP

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# Apply the GitOps configuration
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application.yaml
```

### Step 4 — Configure Jenkins

1. Access Jenkins at `http://localhost:8080`
2. Add DockerHub credentials (ID: `dockerhub-credentials`)
3. Create a Pipeline job pointing to this repository
4. The Jenkinsfile handles the rest automatically

### Step 5 — Deploy

Push any code change to `main`:

```bash
git add . && git commit -m "feat: your change" && git push
```

Jenkins builds, scans, and pushes the image. ArgoCD detects the manifest change and syncs to K3s. Zero-touch deployment. ✅

---

## CI/CD Pipeline Stages

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ Checkout │ → │ Install  │ → │  Build   │ → │  Verify  │
│   SCM    │   │  npm ci  │   │  Image   │   │  Health  │
└──────────┘   └──────────┘   └──────────┘   └──────────┘
                                                   │
┌──────────┐   ┌──────────┐   ┌──────────┐        ▼
│  Update  │ ← │  Push to │ ← │  Trivy   │   ┌──────────┐
│ K8s YAML │   │ DockerHub│   │   Scan   │   │  Health  │
└──────────┘   └──────────┘   └──────────┘   │  Check   │
     │                                        └──────────┘
     ▼
 ArgoCD Sync → K3s Rolling Update
```

---

## Security

- No credentials stored in the repository
- `.env` files excluded from Git and Docker images
- Trivy scans every image for HIGH/CRITICAL vulnerabilities
- K8s pods run with resource limits (prevent noisy-neighbour)
- SSH restricted by security group CIDR
- Non-root container user in Dockerfile

---

## Cleanup

```bash
# Destroy AWS infrastructure
cd terraform && terraform destroy

# Remove local Docker resources
make clean
```

---

## Project Status

| Phase | Area | Status |
|-------|------|--------|
| 1 | Node.js + Docker | ✅ Done |
| 2 | Docker Compose + Makefile | ✅ Done |
| 3 | Git + GitHub | ✅ Done |
| 4 | Jenkins CI/CD Pipeline | ✅ Done |
| 5 | Trivy Security Scanning | ✅ Done |
| 6 | Terraform (AWS VPC, EC2) | ✅ Done |
| 7 | Ansible (K3s provisioning) | ✅ Done |
| 8 | Kubernetes Manifests (K3s) | ✅ Done |
| 9 | ArgoCD GitOps | ✅ Done |

---

## License

ISC
