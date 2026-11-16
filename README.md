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
| **Terraform** | AWS infrastructure provisioning | `devops_tools/terraform/` |
| **Ansible** | Server configuration and K3s install | `devops_tools/ansible/` |
| **K3s** | Lightweight Kubernetes cluster | `devops_tools/k8s/` |
| **ArgoCD** | GitOps continuous deployment | `devops_tools/argocd/` |
| **AWS** | Cloud provider (VPC, EC2) | `devops_tools/terraform/` |
| **MongoDB Atlas** | Managed NoSQL cloud database | `db.js`, `devops_tools/k8s/secret.yaml` |
| **Trivy** | Container image vulnerability scanning | Integrated in Jenkins |
| **Buildah** | Rootless container image builds | Integrated in Jenkins |

---

## Application

A Node.js HTTP service built with Express.js and Mongoose:

| Endpoint | Purpose |
|----------|---------|
| `GET /` | Server information & MongoDB connection status |
| `GET /health` | Health check & DB heartbeat (used by K8s probes) |

---

## Repository Layout

```
.
├── app.js                          # Express.js routes
├── db.js                           # MongoDB Atlas connection & pooling logic
├── index.js                        # Application entry point
├── package.json                    # Node.js dependencies (express, mongoose)
├── .env.example                    # Sample environment variables (MONGO_URI)
├── Dockerfile                      # Multi-stage container build
├── docker-compose.yml              # Local development setup
├── Makefile                        # CLI shortcuts for Docker
│
└── devops_tools/                   # Unified DevOps Tooling & Infrastructure
    ├── ansible/                    # Configuration Management
    │   ├── ansible.cfg             # Ansible settings
    │   ├── inventory/
    │   │   └── hosts.ini.example   # Example inventory
    │   ├── playbooks/
    │   │   └── site.yml            # Main playbook entry point
    │   └── roles/
    │       ├── common/             # Base packages, kernel tuning
    │       ├── k3s-master/         # K3s server installation
    │       └── k3s-worker/         # K3s agent join cluster
    │
    ├── argocd/                     # GitOps Configuration
    │   ├── project.yaml            # ArgoCD project (RBAC)
    │   ├── application.yaml        # ArgoCD app (sync config)
    │   └── README.md               # ArgoCD setup guide
    │
    ├── jenkins/                    # CI/CD Pipeline
    │   ├── Jenkinsfile             # CI/CD pipeline definition
    │   ├── docker-compose.yml      # Jenkins server setup
    │   └── .env                    # Jenkins environment (not committed)
    │
    ├── k8s/                        # Kubernetes Manifests
    │   ├── namespace.yaml          # App namespace
    │   ├── secret.yaml             # MongoDB Atlas connection URI secret
    │   ├── deployment.yaml         # Pod spec with health probes & DB env
    │   ├── service.yaml            # ClusterIP service
    │   ├── ingress.yaml            # Traefik ingress routing
    │   └── hpa.yaml                # Horizontal Pod Autoscaler
    │
    └── terraform/                  # AWS Infrastructure as Code
        ├── providers.tf            # AWS provider and backend config
        ├── variables.tf            # Input variables
        ├── vpc.tf                  # VPC, subnets, IGW, routes
        ├── security-groups.tf      # Firewall rules for K3s
        ├── ec2.tf                  # Master and worker instances
        ├── outputs.tf              # IPs, SSH commands, Atlas whitelist CIDRs
        └── terraform.tfvars.example # Example variable values
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
cd devops_tools/terraform

# Copy and edit the variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialise, plan, and apply
terraform init
terraform plan
terraform apply
```

Note the outputs:
- `k3s_master_public_ip` & `k3s_worker_public_ip` — used in Ansible inventory.
- `mongodb_atlas_whitelist_ips` — the exact CIDRs (`<IP>/32`) to whitelist in **MongoDB Atlas Network Access**.

---

### Step 2 — Configure MongoDB Atlas Network Access

Before running the cluster workloads, allow outbound connections from your K3s EC2 nodes:
1. Log in to [MongoDB Atlas Console](https://cloud.mongodb.com/).
2. Navigate to **Security** ➜ **Network Access** ➜ **IP Access List** ➜ Click **Add IP Address**.
3. Add the two node public IPs from Terraform output (`mongodb_atlas_whitelist_ips`):
   - `k3s_master_public_ip/32` (e.g. `13.233.xx.xx/32`)
   - `k3s_worker_public_ip/32` (e.g. `13.126.xx.xx/32`)
   *(For temporary testing / local dev, add your current public IP via `curl ifconfig.me`/32 or use `0.0.0.0/0` with strong authentication).*
4. Under **Database Access**, create a user with `readWriteAnyDatabase` and copy the connection string.

---

### Step 3 — Configure Servers with Ansible

```bash
cd devops_tools/ansible

# Create inventory from the example
cp inventory/hosts.ini.example inventory/hosts.ini
# Replace MASTER_PUBLIC_IP and WORKER_PUBLIC_IP with Terraform outputs

# Run the full setup
ansible-playbook playbooks/site.yml
```

This installs K3s on the master and joins the worker to the cluster.

### Step 4 — Install ArgoCD & Configure Database Secret

```bash
# SSH into the master node
ssh -i ~/.ssh/your-key.pem ubuntu@MASTER_IP

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# Create application namespace
kubectl create namespace devops-app --dry-run=client -o yaml | kubectl apply -f -

# Create MongoDB secret (replace with your actual Atlas connection URI)
kubectl create secret generic mongodb-secret -n devops-app \
  --from-literal=MONGO_URI="mongodb+srv://<username>:<password>@cluster0.mongodb.net/devops_db?retryWrites=true&w=majority" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply the GitOps configuration
kubectl apply -f devops_tools/argocd/project.yaml
kubectl apply -f devops_tools/argocd/application.yaml
```

### Step 5 — Configure Jenkins

1. Access Jenkins at `http://localhost:8080`
2. Add DockerHub credentials (ID: `dockerhub-credentials`)
3. Create a Pipeline job pointing to this repository (`devops_tools/jenkins/Jenkinsfile`)
4. The Jenkinsfile handles the rest automatically

### Step 6 — Deploy

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

## Makefile Automation CLI Cheatsheet

The root `Makefile` provides unified shortcuts for all tools in this project:

```bash
# ── Docker & Local Dev ──
make build          # Build application Docker image
make up-build       # Build and run containers in background
make test-api       # Curl test / and /health endpoints
make scan           # Run Trivy vulnerability scan
make clean          # Remove containers, volumes, networks

# ── Terraform (AWS) ──
make tf-init        # Initialize Terraform in devops_tools/terraform
make tf-plan        # Show Terraform planned infrastructure
make tf-apply       # Provision AWS VPC, Subnets, EC2 nodes
make tf-output      # Display IPs and MongoDB Atlas whitelist CIDRs
make tf-destroy     # Teardown all AWS cloud resources

# ── Ansible (K3s) ──
make ansible-ping   # Test SSH connectivity to cluster nodes
make ansible-deploy # Execute playbook to install and configure K3s

# ── Kubernetes & ArgoCD ──
make k8s-apply      # Apply Kubernetes manifests (namespace, deployment, secret, etc.)
make k8s-status     # View pods, svc, ingress, and HPA in devops-app namespace
make argocd-apply   # Apply ArgoCD Project & Application definitions
make argocd-status  # Check ArgoCD sync and health status

# ── Jenkins CI/CD ──
make jenkins-up     # Launch local Jenkins and Buildah agent
make jenkins-logs   # Follow Jenkins server logs
make jenkins-down   # Stop Jenkins services
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
cd devops_tools/terraform && terraform destroy

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
