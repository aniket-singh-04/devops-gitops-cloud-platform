# Security Policy

This document outlines the security policies, standards, and vulnerability reporting procedures implemented in this project. As an end-to-end DevOps deployment platform, security is treated as a continuous, integral component across code, containers, infrastructure, and delivery pipelines (DevSecOps).

---

## 🛡️ Supported Versions

Only the latest release on the `main` branch receives active security updates and vulnerability patches:

| Version / Branch | Supported          |
| ---------------- | ------------------ |
| `main`           | :white_check_mark: |
| Historical tags  | :x:                |

---

## 🚨 Reporting a Vulnerability

We take the security of our application and infrastructure seriously. If you discover a security vulnerability, please follow responsible disclosure:

1. **Do NOT open a public issue** on GitHub.
2. Email details to: `aniketsingh.lab@gmail.com` with the subject `[SECURITY VULNERABILITY] <Summary>`.
3. Include:
   - A description of the vulnerability and its potential impact.
   - Exact steps or proof-of-concept (PoC) to reproduce the issue.
   - Affected components (Docker, Kubernetes manifests, Terraform, Ansible, CI/CD).
   - Any proposed remediation or patches if available.
4. **Response Timeline**:
   - Initial acknowledgement: within 24 hours.
   - Assessment and triage: within 72 hours.
   - Fix release: targeted within 7 days depending on severity.

---

## 🔒 Implemented DevSecOps Standards

This project follows enterprise-grade DevSecOps best practices across all 7 layers of the pipeline:

### 1. Application & Dependency Security
- **Strict Dependency Locking**: All dependencies are locked using `package-lock.json` and installed via `npm ci` to prevent untrusted dependency updates.
- **Vulnerability Auditing**: Code dependencies are audited using `npm audit` during continuous integration.
- **Graceful Error Handling**: Database and API errors do not leak stack traces or internal environment variables to clients.

### 2. Container & Image Security
- **Multi-Stage Builds**: [Dockerfile](file:///home/ashish/Original/Drive%20(B)/DevOps/04_Docker/deployment/codes/Dockerfile) uses multi-stage builds (`deps` ➜ `build` ➜ `runner`) to keep the production runtime image minimal and eliminate compiler/build tooling.
- **Non-Root Execution**: Containers run explicitly as the unprivileged `node` user (`USER node`), mitigating container breakout risks.
- **Minimal Attack Surface**: Uses `node:26-alpine` to reduce OS-level CVE footprint.
- **Rootless Image Builds**: CI utilizes **Buildah** in unprivileged/rootless isolation, avoiding exposure of the Docker daemon socket (`/var/run/docker.sock`).
- **Automated CVE Scanning**: **Trivy** scans every image for `HIGH` and `CRITICAL` vulnerabilities in the Jenkins pipeline prior to DockerHub registry push.

### 3. Secrets & Credential Management
- **Zero Secrets in Code**: No passwords, tokens, or private keys are committed to Git.
- **Repository Exclusions**: Both [.gitignore](file:///home/ashish/Original/Drive%20(B)/DevOps/04_Docker/deployment/codes/.gitignore) and [.dockerignore](file:///home/ashish/Original/Drive%20(B)/DevOps/04_Docker/deployment/codes/.dockerignore) block:
  - Local environment files (`.env`, `.env.*`)
  - Terraform state files (`*.tfstate`, `*.tfstate.*`)
  - SSH private keys (`*.pem`, `id_rsa`)
  - Ansible host inventories with plaintext credentials
- **Kubernetes Secrets**: Database URIs and API credentials are decoupled from deployments and managed via Kubernetes `Secret` resources ([devops_tools/k8s/secret.yaml](file:///home/ashish/Original/Drive%20(B)/DevOps/04_Docker/deployment/codes/devops_tools/k8s/secret.yaml)).
- **Production Recommendation**: In cloud production environments, integrate HashiCorp Vault, AWS Secrets Manager, or External Secrets Operator (ESO) with KMS encryption.

### 4. Infrastructure as Code (IaC) Security
- **State File Protection**: Terraform state files must be stored in encrypted remote backends (AWS S3 with AES-256 / AWS KMS encryption and DynamoDB state locking).
- **Least-Privilege Security Groups**: [devops_tools/terraform/security-groups.tf](file:///home/ashish/Original/Drive%20(B)/DevOps/04_Docker/deployment/codes/devops_tools/terraform/security-groups.tf) limits open ports:
  - SSH (port 22) is configurable via `allowed_ssh_cidr` (restrict to bastion or your `/32` IP).
  - Internal cluster traffic (Flannel VXLAN `8472/UDP`, Kubelet `10250/TCP`) is strictly locked to VPC CIDR (`10.0.0.0/16`).
  - Only HTTP/HTTPS (`80`/`443`) are publicly accessible via Ingress.

### 5. Host & OS Hardening (Ansible)
- **Firewall Enforcement**: UFW is enabled with a default `deny incoming` policy on all cluster instances.
- **Kernel Tuning**: Required sysctl bridges (`net.bridge.bridge-nf-call-iptables`) are explicitly defined and persisted.
- **Swap Disabled**: Swap memory is permanently disabled to comply with Kubernetes memory isolation requirements.
- **Automated Package Upgrades**: Ansible applies security patches (`dist-upgrade`) during provisioning.

### 6. Database Network Security (MongoDB Atlas)
- **IP Access Whitelisting**: Outbound cluster access is restricted strictly to the `/32` CIDR of the provisioned AWS EC2 nodes (`mongodb_atlas_whitelist_ips`), blocking unauthorized external connections.
- **TLS/SSL Encryption**: All traffic between K3s pods and MongoDB Atlas is encrypted in-transit via TLS 1.3.
- **Role-Based Database Access**: Dedicated least-privilege database users with scoped database permissions.

### 7. Kubernetes & GitOps Delivery Security
- **Resource Limits**: Pods enforce strict CPU and memory `requests` and `limits` to guard against Denial of Service (DoS) and noisy-neighbor exhaustion.
- **Health Probes**: Liveness and readiness probes prevent unready or unhealthy containers from receiving network traffic.
- **GitOps Immutability**: All cluster changes are synchronized declaratively from Git via **ArgoCD**. Manual drift on the cluster is automatically corrected (`selfHeal: true`).
- **Scoped RBAC**: ArgoCD uses project-level scoping ([devops_tools/argocd/project.yaml](file:///home/ashish/Original/Drive%20(B)/DevOps/04_Docker/deployment/codes/devops_tools/argocd/project.yaml)) restricting deployments exclusively to designated repositories and namespaces.
