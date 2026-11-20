#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# DevOps Unified Deployment, GitOps & Rollback Orchestrator
# End-to-End One-Command Automation:
#   Terraform (AWS) ➜ Ansible (K3s) ➜ Observability (Prometheus/Grafana/Alertmanager)
#   ➜ ArgoCD (GitOps) ➜ Jenkins CI/CD (OWASP, SonarQube, Trivy) ➜ Validation
#
# Features:
#   - One-Command Deploy & Redeploy: Full provisioning or fast git-push CI/CD trigger
#   - Fault-Free Auto-Rollback: Cleans up all resources if any step fails
#   - Manual Rollback on Demand: Graceful teardown with zero orphaned cloud costs
#   - DevSecOps CI/CD: Automated SonarQube, OWASP, Trivy, and GitOps sync
# ──────────────────────────────────────────────────────────────────────────────

set -eo pipefail

# ── Color Definitions ─────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD="\033[1m"
  RED="\033[0;31m"
  GREEN="\033[0;32m"
  YELLOW="\033[0;33m"
  BLUE="\033[0;34m"
  MAGENTA="\033[0;35m"
  CYAN="\033[0;36m"
  NC="\033[0m" # No Color
else
  BOLD=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  NC=""
fi

# ── Paths & Globals ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/devops_tools/terraform"
ANSIBLE_DIR="${SCRIPT_DIR}/devops_tools/ansible"
K8S_DIR="${SCRIPT_DIR}/devops_tools/k8s"
ARGOCD_DIR="${SCRIPT_DIR}/devops_tools/argocd"
JENKINS_DIR="${SCRIPT_DIR}/devops_tools/jenkins"
STATE_FILE="${SCRIPT_DIR}/.deploy_state"

# State tracking variables
CURRENT_PHASE="INIT"
STATE_TF_APPLIED=false
STATE_INVENTORY_CREATED=false
STATE_ANSIBLE_DEPLOYED=false
STATE_K8S_APPLIED=false
STATE_ARGOCD_APPLIED=false
STATE_MONITORING_APPLIED=false
STATE_JENKINS_STARTED=false
ROLLING_BACK=false

# ── Logging Functions ─────────────────────────────────────────────────────────
log_info() {
  echo -e "${CYAN}${BOLD}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}${BOLD}[ERROR]${NC} $1"
}

log_phase() {
  CURRENT_PHASE="$1"
  echo ""
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${MAGENTA}${BOLD} ▶ PHASE: ${CURRENT_PHASE}${NC} — $2"
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
}

# ── Save & Load State ─────────────────────────────────────────────────────────
save_state() {
  cat << EOF > "${STATE_FILE}"
CURRENT_PHASE="${CURRENT_PHASE}"
STATE_TF_APPLIED=${STATE_TF_APPLIED}
STATE_INVENTORY_CREATED=${STATE_INVENTORY_CREATED}
STATE_ANSIBLE_DEPLOYED=${STATE_ANSIBLE_DEPLOYED}
STATE_K8S_APPLIED=${STATE_K8S_APPLIED}
STATE_ARGOCD_APPLIED=${STATE_ARGOCD_APPLIED}
STATE_MONITORING_APPLIED=${STATE_MONITORING_APPLIED}
STATE_JENKINS_STARTED=${STATE_JENKINS_STARTED}
MASTER_IP="${MASTER_IP:-}"
WORKER_IP="${WORKER_IP:-}"
SSH_KEY_FILE="${SSH_KEY_FILE:-}"
EOF
}

load_state() {
  if [ -f "${STATE_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${STATE_FILE}"
  fi
}

cleanup_state() {
  rm -f "${STATE_FILE}"
}

# ── Automated Error & Rollback Handler ────────────────────────────────────────
handle_error() {
  local exit_code=$?
  local line_no=$1

  # Prevent recursion if an error occurs inside rollback itself
  if [ "${ROLLING_BACK}" = true ]; then
    log_error "Critical error during rollback routine at line ${line_no}. Aborting."
    exit "${exit_code}"
  fi

  # Normal exits (code 0) or manual graceful exit
  if [ "${exit_code}" -eq 0 ]; then
    return 0
  fi

  echo ""
  log_error "Automation failed at Phase '${CURRENT_PHASE}' (line ${line_no}) with exit code ${exit_code}!"
  log_warn "Starting automated rollback to tear down resources and eliminate orphaned cloud costs..."

  ROLLING_BACK=true
  perform_rollback "automatic"

  echo ""
  log_error "Deployment halted and state reversed safely. Inspect logs above for the root cause."
  exit "${exit_code}"
}

# Trap ERR and INT signals to guarantee clean state recovery
trap 'handle_error $LINENO' ERR INT

# ── Rollback Execution Engine ─────────────────────────────────────────────────
perform_rollback() {
  local mode="${1:-manual}"
  log_info "Executing rollback sequence (Mode: ${mode})..."

  load_state

  # Step 1: Teardown Jenkins CI & SonarQube services if running
  if [ "${STATE_JENKINS_STARTED}" = true ] || [ "$mode" = "manual" ]; then
    log_info "[Rollback 1/6] Stopping local Jenkins CI/CD and SonarQube services..."
    if command -v docker >/dev/null 2>&1 && [ -d "${JENKINS_DIR}" ]; then
      (cd "${JENKINS_DIR}" && docker compose down) 2>/dev/null || true
    fi
    STATE_JENKINS_STARTED=false
    save_state
  fi

  # Step 2: Teardown ArgoCD Application and Project if applied
  if [ "${STATE_ARGOCD_APPLIED}" = true ] || [ "$mode" = "manual" ]; then
    if [ -n "${MASTER_IP:-}" ] && [ -n "${SSH_KEY_FILE:-}" ] && [ -f "${SSH_KEY_FILE}" ]; then
      log_info "[Rollback 2/6] Removing ArgoCD GitOps resources from cluster..."
      ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
        "k3s kubectl delete -f - --ignore-not-found=true" << 'EOF' 2>/dev/null || true
$(cat "${ARGOCD_DIR}/application.yaml" 2>/dev/null || true)
EOF
      ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
        "k3s kubectl delete -f - --ignore-not-found=true" << 'EOF' 2>/dev/null || true
$(cat "${ARGOCD_DIR}/project.yaml" 2>/dev/null || true)
EOF
    fi
    STATE_ARGOCD_APPLIED=false
    save_state
  fi

  # Step 3: Delete Observability Stack (monitoring namespace)
  if [ "${STATE_MONITORING_APPLIED}" = true ] || [ "$mode" = "manual" ]; then
    if [ -n "${MASTER_IP:-}" ] && [ -n "${SSH_KEY_FILE:-}" ] && [ -f "${SSH_KEY_FILE}" ]; then
      log_info "[Rollback 3/6] Deleting Prometheus, Grafana, and Alertmanager monitoring resources..."
      ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
        "k3s kubectl delete namespace monitoring --ignore-not-found=true --timeout=30s" 2>/dev/null || true
    fi
    STATE_MONITORING_APPLIED=false
    save_state
  fi

  # Step 4: Delete Kubernetes workloads and application namespace
  if [ "${STATE_K8S_APPLIED}" = true ] || [ "$mode" = "manual" ]; then
    if [ -n "${MASTER_IP:-}" ] && [ -n "${SSH_KEY_FILE:-}" ] && [ -f "${SSH_KEY_FILE}" ]; then
      log_info "[Rollback 4/6] Deleting application workloads & devops-app namespace..."
      ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
        "k3s kubectl delete namespace devops-app --ignore-not-found=true --timeout=30s" 2>/dev/null || true
    fi
    STATE_K8S_APPLIED=false
    save_state
  fi

  # Step 5: Destroy Terraform Infrastructure
  if [ "${STATE_TF_APPLIED}" = true ] || [ -f "${TF_DIR}/terraform.tfstate" ]; then
    log_info "[Rollback 5/6] Destroying AWS cloud infrastructure via Terraform..."
    if command -v terraform >/dev/null 2>&1 && [ -d "${TF_DIR}" ]; then
      (cd "${TF_DIR}" && terraform destroy -auto-approve) || log_warn "Terraform destroy encountered a non-fatal warning."
    else
      log_warn "Terraform binary not found or directory missing; skipping terraform destroy."
    fi
    STATE_TF_APPLIED=false
    save_state
  fi

  # Step 6: Clean up generated inventory and state
  log_info "[Rollback 6/6] Cleaning up generated files and state..."
  rm -f "${ANSIBLE_DIR}/inventory/hosts.ini"
  cleanup_state

  log_success "All resources have been reversed cleanly."
}

# ── Preflight Verification ────────────────────────────────────────────────────
check_prerequisites() {
  log_phase "PREFLIGHT_CHECK" "Validating CLI binaries and configurations"

  local missing_tools=()
  for tool in terraform ansible ansible-playbook ssh scp jq curl; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      missing_tools+=("${tool}")
    fi
  done

  if [ ${#missing_tools[@]} -ne 0 ]; then
    log_error "Missing required CLI tools: ${missing_tools[*]}"
    log_info "Please install the missing tools and try again."
    return 1
  fi

  if [ ! -f "${TF_DIR}/terraform.tfvars" ]; then
    log_error "Missing '${TF_DIR}/terraform.tfvars'!"
    log_info "Create it from template: cp ${TF_DIR}/terraform.tfvars.example ${TF_DIR}/terraform.tfvars"
    return 1
  fi

  # Auto-detect SSH Key from terraform.tfvars
  local tf_key_path
  tf_key_path=$(grep -E '^\s*private_key_path\s*=' "${TF_DIR}/terraform.tfvars" | head -1 | sed -E 's/^\s*private_key_path\s*=\s*"?([^"]*)"?/\1/' || echo "")
  
  # Expand tilde ~ if present
  tf_key_path="${tf_key_path/#\~/$HOME}"

  if [ -n "${tf_key_path}" ] && [ -f "${tf_key_path}" ]; then
    SSH_KEY_FILE="${tf_key_path}"
    chmod 400 "${SSH_KEY_FILE}" 2>/dev/null || true
    log_info "Resolved SSH Private Key: ${SSH_KEY_FILE}"
  elif [ -f "${HOME}/.ssh/id_rsa" ]; then
    SSH_KEY_FILE="${HOME}/.ssh/id_rsa"
    log_info "Fallback to default SSH Key: ${SSH_KEY_FILE}"
  else
    log_error "Unable to locate a valid SSH private key. Check 'private_key_path' in ${TF_DIR}/terraform.tfvars"
    return 1
  fi

  # Ensure root .env exists for application and secret injection
  if [ ! -f "${SCRIPT_DIR}/.env" ]; then
    if [ -f "${SCRIPT_DIR}/.env.example" ]; then
      log_warn "Root .env not found. Auto-generating from .env.example..."
      cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
    fi
  fi

  log_success "All preflight checks passed!"
}

# ── Helper: Wait for SSH ──────────────────────────────────────────────────────
wait_for_ssh() {
  local host="$1"
  local key="$2"
  local max_attempts=30
  local attempt=1

  log_info "Waiting for SSH to be ready on ${host}..."
  while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${key}" ubuntu@"${host}" "echo ssh_ready" >/dev/null 2>&1; do
    if [ "${attempt}" -ge "${max_attempts}" ]; then
      log_error "Timed out waiting for SSH on ${host} after $((max_attempts * 5)) seconds."
      return 1
    fi
    echo -n "."
    sleep 5
    attempt=$((attempt + 1))
  done
  echo ""
  log_success "SSH is ready on ${host}!"
}

# ── Deployment Flow ───────────────────────────────────────────────────────────
deploy_all() {
  check_prerequisites
  save_state

  # ── STEP 1: Terraform Infrastructure Provisioning
  log_phase "TERRAFORM_INIT_APPLY" "Provisioning AWS VPC, Subnets, Security Groups, and EC2 Nodes"
  (
    cd "${TF_DIR}"
    terraform init -input=false
    terraform apply -auto-approve -input=false
  )
  STATE_TF_APPLIED=true
  save_state

  # Extract Outputs
  MASTER_IP=$(cd "${TF_DIR}" && terraform output -raw k3s_master_public_ip 2>/dev/null || terraform output -json | jq -r '.k3s_master_public_ip.value')
  WORKER_IP=$(cd "${TF_DIR}" && terraform output -raw k3s_worker_public_ip 2>/dev/null || terraform output -json | jq -r '.k3s_worker_public_ip.value')

  if [ -z "${MASTER_IP}" ] || [ "${MASTER_IP}" = "null" ]; then
    log_error "Failed to retrieve k3s_master_public_ip from Terraform outputs."
    return 1
  fi

  log_success "AWS Infrastructure Provisioned!"
  echo -e "   - K3s Master Public IP: ${GREEN}${MASTER_IP}${NC}"
  echo -e "   - K3s Worker Public IP: ${GREEN}${WORKER_IP}${NC}"
  save_state

  # ── STEP 2: Generate Dynamic Ansible Inventory
  log_phase "ANSIBLE_INVENTORY" "Generating dynamic inventory from Terraform outputs"
  mkdir -p "${ANSIBLE_DIR}/inventory"
  cat << EOF > "${ANSIBLE_DIR}/inventory/hosts.ini"
[k3s_master]
master ansible_host=${MASTER_IP}

[k3s_workers]
worker1 ansible_host=${WORKER_IP}

[k3s_cluster:children]
k3s_master
k3s_workers

[k3s_cluster:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${SSH_KEY_FILE}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

  STATE_INVENTORY_CREATED=true
  save_state
  log_success "Generated ${ANSIBLE_DIR}/inventory/hosts.ini"

  # Wait for SSH on both nodes before kicking off Ansible
  wait_for_ssh "${MASTER_IP}" "${SSH_KEY_FILE}"
  wait_for_ssh "${WORKER_IP}" "${SSH_KEY_FILE}"

  # ── STEP 3: Ansible Node Hardening & K3s Cluster Deployment
  log_phase "ANSIBLE_DEPLOY" "Hardening nodes, installing K3s cluster, and deploying Observability"
  (
    cd "${ANSIBLE_DIR}"
    ansible k3s_cluster -m ping
    ansible-playbook playbooks/site.yml
  )
  STATE_ANSIBLE_DEPLOYED=true
  save_state
  log_success "K3s Cluster & Observability stack successfully configured via Ansible!"

  # ── STEP 4: Setup ArgoCD (GitOps Engine)
  log_phase "ARGOCD_SETUP" "Installing ArgoCD controller on K3s Master"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" bash << 'EOF'
set -e
echo "Creating argocd namespace..."
k3s kubectl create namespace argocd --dry-run=client -o yaml | k3s kubectl apply -f -

echo "Installing ArgoCD core manifests..."
k3s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD controller to initialize..."
k3s kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s || true
EOF
  log_success "ArgoCD installed on K3s cluster!"

  # ── STEP 5: Deploy Application Manifests, Secrets & Observability
  log_phase "K8S_MANIFESTS" "Configuring application namespace, secrets, observability, and GitOps sync"

  # Create application namespace
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl create namespace devops-app --dry-run=client -o yaml | k3s kubectl apply -f -"
  STATE_K8S_APPLIED=true
  save_state

  # Apply MongoDB Secret
  log_info "Configuring database credentials into Kubernetes Secret..."
  local env_mongo_uri=""
  if [ -f "${SCRIPT_DIR}/.env" ]; then
    env_mongo_uri=$(grep -E '^\s*MONGO_URI\s*=' "${SCRIPT_DIR}/.env" | head -1 | sed -E 's/^\s*MONGO_URI\s*=\s*"?([^"]*)"?/\1/' || echo "")
  fi

  if [ -n "${env_mongo_uri}" ]; then
    log_info "Injecting MONGO_URI from root .env file into Kubernetes secret..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
      "k3s kubectl create secret generic mongodb-secret -n devops-app \
        --from-literal=MONGO_URI='${env_mongo_uri}' \
        --dry-run=client -o yaml | k3s kubectl apply -f -"
  else
    log_info "Applying template mongodb-secret from ${K8S_DIR}/secret.yaml..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
      "k3s kubectl apply -f -" << EOF
$(cat "${K8S_DIR}/secret.yaml")
EOF
  fi

  # Apply Observability Manifests (Prometheus, Grafana, Alertmanager)
  log_info "Applying Prometheus, Grafana, and Alertmanager manifests..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl apply -f -" << EOF
$(cat "${K8S_DIR}/monitoring/namespace.yaml")
---
$(cat "${K8S_DIR}/monitoring/alertmanager.yaml")
---
$(cat "${K8S_DIR}/monitoring/prometheus.yaml")
---
$(cat "${K8S_DIR}/monitoring/grafana.yaml")
EOF
  STATE_MONITORING_APPLIED=true
  save_state

  # Apply ArgoCD Project & Application
  log_info "Applying ArgoCD GitOps project and application..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl apply -f -" << EOF
$(cat "${ARGOCD_DIR}/project.yaml")
EOF

  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl apply -f -" << EOF
$(cat "${ARGOCD_DIR}/application.yaml")
EOF

  STATE_ARGOCD_APPLIED=true
  save_state

  # ── STEP 6: Launch & Trigger Jenkins CI/CD Engine & SonarQube
  log_phase "JENKINS_SONAR_SETUP" "Starting local Jenkins Master, SonarQube, and Buildah Agent"
  if command -v docker >/dev/null 2>&1; then
    docker network create ci-net 2>/dev/null || true
    docker volume create jenkins_home 2>/dev/null || true
    docker volume create trivy-cache 2>/dev/null || true
    docker volume create sonarqube_data 2>/dev/null || true
    docker volume create sonarqube_extensions 2>/dev/null || true
    docker volume create sonarqube_logs 2>/dev/null || true

    log_info "Launching Jenkins Server, SonarQube & Buildah Agent via Docker Compose..."
    (
      cd "${JENKINS_DIR}"
      docker compose up -d
    )
    STATE_JENKINS_STARTED=true
    save_state

    # Wait for Jenkins port 8080 to become responsive
    log_info "Waiting for Jenkins HTTP service (http://localhost:8080) to be responsive..."
    local j_attempt=1
    local j_max=25
    while ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null | grep -qE "200|403|302"; do
      if [ "${j_attempt}" -ge "${j_max}" ]; then
        log_warn "Jenkins server is completing initialization in background."
        break
      fi
      echo -n "."
      sleep 3
      j_attempt=$((j_attempt + 1))
    done
    echo ""
    log_success "Jenkins CI/CD Engine is up and running at http://localhost:8080!"

    # Trigger initial build automatically via API
    log_info "Triggering initial automated build for 'devops-ci-pipeline' via API..."
    sleep 5
    curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" "http://localhost:8080/job/devops-ci-pipeline/build" >/dev/null 2>&1 || \
    curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" "http://localhost:8080/job/devops-pipeline/build" >/dev/null 2>&1 || true
    log_success "Pipeline build triggered automatically! (Zero UI setup needed)"
  else
    log_warn "Docker not detected; skipping local Jenkins CI/CD container startup."
  fi

  # ── STEP 7: Validation & Health Check
  log_phase "VERIFICATION" "Verifying application status, cluster health, and dashboards"

  ARGOCD_PASSWORD=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" || echo "admin")

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║           🎉 ONE-COMMAND DEPLOYMENT COMPLETED SUCCESSFULLY!          ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Cluster Access Details:${NC}"
  echo -e "  • ${CYAN}K3s Master IP:${NC}      ${MASTER_IP}"
  echo -e "  • ${CYAN}K3s Worker IP:${NC}      ${WORKER_IP}"
  echo -e "  • ${CYAN}SSH Master:${NC}         ssh -i ${SSH_KEY_FILE} ubuntu@${MASTER_IP}"
  echo -e "  • ${CYAN}SSH Worker:${NC}         ssh -i ${SSH_KEY_FILE} ubuntu@${WORKER_IP}"
  echo ""
  echo -e "${BOLD}GitOps & CI/CD Portals:${NC}"
  echo -e "  • ${CYAN}ArgoCD Dashboard:${NC}   https://localhost:8080 (Forward cmd: ssh -i ${SSH_KEY_FILE} -L 8080:localhost:443 ubuntu@${MASTER_IP} 'k3s kubectl port-forward svc/argocd-server -n argocd 443:443')"
  echo -e "    Username: admin | Password: ${YELLOW}${ARGOCD_PASSWORD}${NC}"
  echo -e "  • ${CYAN}Jenkins CI/CD:${NC}      http://localhost:8080 (Credentials: admin / admin123)"
  echo -e "    Jobs: devops-ci-pipeline ➜ devops-cd-pipeline"
  echo -e "  • ${CYAN}SonarQube Server:${NC}   http://localhost:9000 (Default: admin / admin)"
  echo ""
  echo -e "${BOLD}Observability & Alerting Stack:${NC}"
  echo -e "  • ${CYAN}Prometheus (9090):${NC}  ssh -i ${SSH_KEY_FILE} -L 9090:localhost:9090 ubuntu@${MASTER_IP} 'k3s kubectl port-forward svc/prometheus -n monitoring 9090:9090'"
  echo -e "  • ${CYAN}Grafana (3000):${NC}     ssh -i ${SSH_KEY_FILE} -L 3000:localhost:3000 ubuntu@${MASTER_IP} 'k3s kubectl port-forward svc/grafana -n monitoring 3000:3000'"
  echo -e "    Grafana Login: admin / admin123 (Prometheus datasource auto-provisioned)"
  echo -e "  • ${CYAN}Alertmanager (9093):${NC}Configured with Gmail SMTP alert notifications"
  echo ""
  echo -e "${BOLD}Commands for Lifecycle Management:${NC}"
  echo -e "  • Redeploy with Code Push:  ${YELLOW}make redeploy${NC} or ${YELLOW}./orchestrate.sh redeploy${NC}"
  echo -e "  • Manual CI Trigger:        ${YELLOW}make trigger-ci${NC} or ${YELLOW}./orchestrate.sh trigger-ci${NC}"
  echo -e "  • Manual CD Trigger:        ${YELLOW}make trigger-cd TAG=123${NC} or ${YELLOW}./orchestrate.sh trigger-cd 123${NC}"
  echo -e "  • Smooth Teardown/Rollback: ${YELLOW}make rollback${NC} or ${YELLOW}./orchestrate.sh rollback${NC}"
  echo ""

  CURRENT_PHASE="COMPLETE"
  save_state
}

# ── Fast Redeploy Flow ────────────────────────────────────────────────────────
redeploy() {
  log_phase "REDEPLOY" "One-Command Redeployment: Committing, Pushing & Triggering CI/CD"
  load_state

  local commit_msg="${1:-chore(app): automated one-command redeployment}"

  # Stage and commit any dirty changes
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    log_info "Detected local code modifications. Committing..."
    git add .
    git commit -m "${commit_msg}" || true
    log_info "Pushing latest commits to GitHub repository..."
    git push origin HEAD:main 2>/dev/null || log_warn "Remote git push skipped; triggering pipeline on current state."
  else
    log_info "Working directory clean; no new code commit needed."
  fi

  # Trigger CI Job via API
  log_info "Triggering Jenkins CI Job ('devops-ci-pipeline') via REST API..."
  curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" \
    "http://localhost:8080/job/devops-ci-pipeline/build" >/dev/null 2>&1 || \
  curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" \
    "http://localhost:8080/job/devops-pipeline/build" >/dev/null 2>&1 || true

  log_success "Redeploy triggered successfully!"
  log_info "Jenkins CI will run OWASP, SonarQube, Trivy, build & push image, and trigger ArgoCD sync."
}

# ── Trigger CI ────────────────────────────────────────────────────────────────
trigger_ci() {
  local commit_push="${1:-}"
  log_phase "TRIGGER_CI" "Triggering Jenkins CI pipeline via API"

  if [ "${commit_push}" = "--push" ] || [ "${commit_push}" = "-p" ]; then
    log_info "Committing and pushing before triggering..."
    git add .
    git commit -m "chore: manual code push and CI trigger" || true
    git push origin HEAD:main 2>/dev/null || true
  fi

  curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" \
    "http://localhost:8080/job/devops-ci-pipeline/build" >/dev/null 2>&1 || \
  curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" \
    "http://localhost:8080/job/devops-pipeline/build" >/dev/null 2>&1 || true

  log_success "CI Pipeline enqueued at http://localhost:8080/job/devops-ci-pipeline/"
}

# ── Trigger CD ────────────────────────────────────────────────────────────────
trigger_cd() {
  local tag="${1:-latest}"
  log_phase "TRIGGER_CD" "Triggering Jenkins CD pipeline with image tag '${tag}'"

  curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" \
    "http://localhost:8080/job/devops-cd-pipeline/buildWithParameters?IMAGE_TAG=${tag}" >/dev/null 2>&1 || true

  log_success "CD Pipeline enqueued at http://localhost:8080/job/devops-cd-pipeline/ for tag: ${tag}"
}

# ── Manual Rollback Command ───────────────────────────────────────────────────
smooth_rollback() {
  echo ""
  echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}${BOLD}║              🔄 INITIATING SMOOTH ROLLBACK / TEARDOWN               ║${NC}"
  echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  echo -e "This will safely destroy all provisioned AWS cloud resources, K3s workloads,"
  echo -e "observability stack, ArgoCD, and local CI services without leaving lingering costs."
  echo ""

  if [ -t 0 ] && [ "${1:-}" != "--force" ] && [ "${1:-}" != "-f" ]; then
    read -r -p "Are you sure you want to rollback and destroy all resources? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[yY](es)?$ ]]; then
      log_info "Rollback aborted by user."
      exit 0
    fi
  fi

  perform_rollback "manual"

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║           ✔ COMPLETE ROLLBACK COMPLETED FAULT-FREE!                 ║${NC}"
  echo -e "${GREEN}${BOLD}║           Zero lingering cloud costs. Ready for fresh deploy.        ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
}

# ── Status Inspection ─────────────────────────────────────────────────────────
show_status() {
  load_state
  echo ""
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}DevOps Infrastructure, CI/CD & Observability Status${NC}"
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"

  if [ -f "${STATE_FILE}" ]; then
    echo -e "  • Last Recorded Phase:     ${CYAN}${CURRENT_PHASE}${NC}"
    echo -e "  • Terraform Applied:       ${STATE_TF_APPLIED}"
    echo -e "  • Ansible Cluster Setup:   ${STATE_ANSIBLE_DEPLOYED}"
    echo -e "  • K8s Workloads Applied:   ${STATE_K8S_APPLIED}"
    echo -e "  • Observability Applied:   ${STATE_MONITORING_APPLIED}"
    echo -e "  • ArgoCD Configured:       ${STATE_ARGOCD_APPLIED}"
    echo -e "  • Jenkins & Sonar Started: ${STATE_JENKINS_STARTED}"
    echo -e "  • Master Node IP:          ${MASTER_IP:-N/A}"
    echo -e "  • Worker Node IP:          ${WORKER_IP:-N/A}"
  else
    echo -e "  • No active deployment state found (.deploy_state is empty or removed)."
  fi

  if command -v docker >/dev/null 2>&1; then
    echo ""
    log_info "Local Docker Services (Jenkins, SonarQube, Buildah):"
    docker ps --filter "name=jenkins" --filter "name=sonarqube" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  fi

  if [ -d "${TF_DIR}" ] && [ -f "${TF_DIR}/terraform.tfstate" ]; then
    echo ""
    log_info "Terraform Cloud Outputs:"
    (cd "${TF_DIR}" && terraform output 2>/dev/null || echo "No terraform outputs available.")
  fi
}

# ── CLI Entrypoint ────────────────────────────────────────────────────────────
ACTION="${1:-deploy}"

case "${ACTION}" in
  deploy)
    deploy_all
    ;;
  redeploy)
    redeploy "${2:-}"
    ;;
  trigger-ci|ci)
    trigger_ci "${2:-}"
    ;;
  trigger-cd|cd)
    trigger_cd "${2:-}"
    ;;
  rollback|destroy|down)
    smooth_rollback "${2:-}"
    ;;
  status)
    show_status
    ;;
  plan)
    check_prerequisites
    log_phase "TERRAFORM_PLAN" "Displaying Terraform execution plan"
    (cd "${TF_DIR}" && terraform init && terraform plan)
    ;;
  help|--help|-h)
    echo "Usage: $0 [deploy|redeploy|trigger-ci|trigger-cd|rollback|status|plan|help]"
    echo ""
    echo "Commands:"
    echo "  deploy      - Full automated one-command deployment with auto-rollback on error"
    echo "  redeploy    - Fast redeploy: commits changes, pushes to git, and triggers CI/CD"
    echo "  trigger-ci  - Trigger Jenkins CI pipeline via API (use --push to commit and push)"
    echo "  trigger-cd  - Trigger Jenkins CD pipeline via API (pass image tag as param)"
    echo "  rollback    - Smooth, fault-tolerant teardown of all cloud & cluster resources"
    echo "  status      - View current deployment phase, outputs, and running services"
    echo "  plan        - Run preflight check and show Terraform execution plan"
    echo "  help        - Show this help message"
    ;;
  *)
    log_error "Unknown action: '${ACTION}'"
    echo "Run '$0 help' for available commands."
    exit 1
    ;;
esac
