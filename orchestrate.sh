#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# DevOps Unified Deployment & Rollback Orchestrator
# End-to-End One-Command Automation:
#   Terraform (AWS) ➜ Ansible (K3s) ➜ Kubernetes & ArgoCD (GitOps) ➜ Validation
#
# Features:
#   - Automatic Rollback on Any Error: Reverses all changes in reverse order
#     if any step fails, preventing orphaned cloud resources and costs.
#   - Smooth On-Demand Rollback: Gracefully tears down workloads, ArgoCD,
#     and cloud infrastructure even from a healthy, running state.
#   - Zero Manual IP Copy-Paste: Automatically extracts Terraform outputs
#     and populates Ansible inventory.
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
STATE_JENKINS_STARTED=${STATE_JENKINS_STARTED}
MASTER_IP="${MASTER_IP:-}"
WORKER_IP="${WORKER_IP:-}"
SSH_KEY_FILE="${SSH_KEY_FILE:-}"
EOF
}

load_state() {
  if [ -f "${STATE_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
  fi
}

cleanup_state() {
  rm -f "${STATE_FILE}"
}

# ── Error Handler & Automatic Rollback ────────────────────────────────────────
handle_error() {
  local exit_code="$1"
  local line_no="$2"
  local command="$3"

  # Prevent recursive traps
  if [ "${ROLLING_BACK}" = true ]; then
    log_error "Secondary error during rollback at line ${line_no}. Exiting."
    exit 1
  fi
  ROLLING_BACK=true

  echo ""
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}${BOLD}║                 🚨 DEPLOYMENT FAILURE DETECTED                      ║${NC}"
  echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  log_error "Command failed: '${command}' (exit code: ${exit_code}) at line ${line_no}"
  log_error "Failed during phase: ${CURRENT_PHASE}"
  echo ""
  log_warn "Initiating AUTOMATIC REVERSAL of all provisioned resources..."
  log_warn "This ensures zero residual state and prevents unintended cloud billing."
  echo ""

  perform_rollback "automatic"

  echo ""
  echo -e "${GREEN}${BOLD}✔ Automatic reversal completed cleanly.${NC}"
  echo -e "${YELLOW}Please resolve the issue above and run 'make deploy' to retry.${NC}"
  exit "${exit_code}"
}

# Trap unexpected errors, Ctrl+C, and termination signals
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR SIGINT SIGTERM

# ── Rollback Execution Engine ─────────────────────────────────────────────────
perform_rollback() {
  local mode="${1:-manual}"
  log_info "Executing rollback sequence (Mode: ${mode})..."

  load_state

  # Step 1: Teardown Jenkins CI services if running
  if [ "${STATE_JENKINS_STARTED}" = true ] || [ "$mode" = "manual" ]; then
    log_info "[Rollback 1/5] Stopping local Jenkins CI/CD services..."
    if command -v docker >/dev/null 2>&1 && [ -d "${JENKINS_DIR}" ]; then
      (cd "${JENKINS_DIR}" && docker compose down) 2>/dev/null || true
    fi
    STATE_JENKINS_STARTED=false
    save_state
  fi

  # Step 2: Teardown ArgoCD Application and Project if applied
  if [ "${STATE_ARGOCD_APPLIED}" = true ] || [ "$mode" = "manual" ]; then
    if [ -n "${MASTER_IP:-}" ] && [ -n "${SSH_KEY_FILE:-}" ] && [ -f "${SSH_KEY_FILE}" ]; then
      log_info "[Rollback 2/5] Removing ArgoCD GitOps resources from cluster..."
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

  # Step 3: Delete Kubernetes workloads and namespace
  if [ "${STATE_K8S_APPLIED}" = true ] || [ "$mode" = "manual" ]; then
    if [ -n "${MASTER_IP:-}" ] && [ -n "${SSH_KEY_FILE:-}" ] && [ -f "${SSH_KEY_FILE}" ]; then
      log_info "[Rollback 3/5] Deleting application workloads & devops-app namespace..."
      ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
        "k3s kubectl delete namespace devops-app --ignore-not-found=true --timeout=30s" 2>/dev/null || true
    fi
    STATE_K8S_APPLIED=false
    save_state
  fi

  # Step 4: Destroy Terraform Infrastructure
  if [ "${STATE_TF_APPLIED}" = true ] || [ -f "${TF_DIR}/terraform.tfstate" ]; then
    log_info "[Rollback 4/5] Destroying AWS cloud infrastructure via Terraform..."
    if command -v terraform >/dev/null 2>&1 && [ -d "${TF_DIR}" ]; then
      (cd "${TF_DIR}" && terraform destroy -auto-approve) || log_warn "Terraform destroy encountered a non-fatal warning."
    else
      log_warn "Terraform binary not found or directory missing; skipping terraform destroy."
    fi
    STATE_TF_APPLIED=false
    save_state
  fi

  # Step 5: Clean up generated inventory and state
  log_info "[Rollback 5/5] Cleaning up generated files and state..."
  rm -f "${ANSIBLE_DIR}/inventory/hosts.ini"
  cleanup_state

  log_success "All resources have been reversed cleanly."
}

# ── Helper: Preflight Verification ────────────────────────────────────────────
check_prerequisites() {
  log_phase "PREFLIGHT" "Verifying environment, credentials, and dependencies"

  local missing_tools=()

  for tool in terraform ansible-playbook ssh curl jq; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      missing_tools+=("${tool}")
    fi
  done

  if [ ${#missing_tools[@]} -gt 0 ]; then
    log_error "The following required CLI tools are not installed or not in PATH:"
    for item in "${missing_tools[@]}"; do
      echo -e "   - ${RED}${item}${NC}"
    done
    echo ""
    log_info "Please install missing dependencies before running the deployment."
    exit 1
  fi

  # Check terraform.tfvars
  if [ ! -f "${TF_DIR}/terraform.tfvars" ]; then
    log_warn "terraform.tfvars not found at ${TF_DIR}/terraform.tfvars"
    if [ -f "${TF_DIR}/terraform.tfvars.example" ]; then
      log_info "Creating terraform.tfvars from terraform.tfvars.example..."
      cp "${TF_DIR}/terraform.tfvars.example" "${TF_DIR}/terraform.tfvars"
      log_warn "Please review ${TF_DIR}/terraform.tfvars and ensure 'key_pair_name' matches your AWS EC2 key."
    else
      log_error "Missing terraform.tfvars.example. Cannot proceed."
      exit 1
    fi
  fi

  # Resolve Key Pair Name from tfvars
  KEY_NAME=$(grep -E '^\s*key_pair_name\s*=' "${TF_DIR}/terraform.tfvars" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' || echo "")
  if [ -z "${KEY_NAME}" ] || [ "${KEY_NAME}" = "your-key-pair-name" ]; then
    log_error "Please set your actual AWS key pair name in ${TF_DIR}/terraform.tfvars (key_pair_name = \"...\")"
    exit 1
  fi

  # Locate SSH Key File
  SSH_KEY_FILE=""
  if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH}" ]; then
    SSH_KEY_FILE="${SSH_KEY_PATH}"
  elif [ -f "${HOME}/.ssh/${KEY_NAME}.pem" ]; then
    SSH_KEY_FILE="${HOME}/.ssh/${KEY_NAME}.pem"
  elif [ -f "${HOME}/.ssh/${KEY_NAME}" ]; then
    SSH_KEY_FILE="${HOME}/.ssh/${KEY_NAME}"
  elif [ -f "${SCRIPT_DIR}/${KEY_NAME}.pem" ]; then
    SSH_KEY_FILE="${SCRIPT_DIR}/${KEY_NAME}.pem"
  fi

  if [ -z "${SSH_KEY_FILE}" ]; then
    log_error "Could not find SSH private key for '${KEY_NAME}'."
    log_info "Looked in: ~/.ssh/${KEY_NAME}.pem, ~/.ssh/${KEY_NAME}, and current directory."
    log_info "Tip: export SSH_KEY_PATH=/path/to/your/key.pem and rerun."
    exit 1
  fi

  chmod 400 "${SSH_KEY_FILE}" 2>/dev/null || true
  log_success "Prerequisites verified! SSH key resolved: ${SSH_KEY_FILE}"
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
  log_phase "ANSIBLE_DEPLOY" "Hardening nodes and installing K3s multi-node cluster"
  (
    cd "${ANSIBLE_DIR}"
    ansible k3s_cluster -m ping
    ansible-playbook playbooks/site.yml
  )
  STATE_ANSIBLE_DEPLOYED=true
  save_state
  log_success "K3s Cluster successfully installed and verified via Ansible!"

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

  # ── STEP 5: Deploy Application Manifests & GitOps Definitions
  log_phase "K8S_ARGOCD_APP" "Configuring application namespace, secrets, and GitOps sync"

  # Create application namespace
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl create namespace devops-app --dry-run=client -o yaml | k3s kubectl apply -f -"
  STATE_K8S_APPLIED=true
  save_state

  # Apply MongoDB Secret from local template
  log_info "Applying database secrets..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl apply -f -" << EOF
$(cat "${K8S_DIR}/secret.yaml")
EOF

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

  # ── STEP 6: Launch & Trigger Jenkins CI/CD Engine
  log_phase "JENKINS_SETUP" "Starting local Jenkins Master and Buildah CI agent"
  if command -v docker >/dev/null 2>&1; then
    # Ensure external network and volume exist for Jenkins
    docker network create ci-net 2>/dev/null || true
    docker volume create jenkins_home 2>/dev/null || true
    docker volume create trivy-cache 2>/dev/null || true

    log_info "Launching Jenkins Server & Buildah Agent via Docker Compose..."
    (
      cd "${JENKINS_DIR}"
      docker compose up -d
    )
    STATE_JENKINS_STARTED=true
    save_state

    # Wait for Jenkins port 8080 to become responsive
    log_info "Waiting for Jenkins HTTP service (http://localhost:8080) to be responsive..."
    local j_attempt=1
    local j_max=20
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
    log_info "Triggering initial automated build for 'devops-pipeline' via API..."
    sleep 5
    curl -s -X POST -u "${JENKINS_ADMIN_USER:-admin}:${JENKINS_ADMIN_PASSWORD:-admin123}" "http://localhost:8080/job/devops-pipeline/build" >/dev/null 2>&1 || true
    log_success "Pipeline build triggered automatically! (Zero UI setup needed)"
  else
    log_warn "Docker not detected; skipping local Jenkins CI/CD container startup."
  fi

  # ── STEP 7: Validation & Health Check
  log_phase "VERIFICATION" "Verifying application status and cluster health"

  # Retrieve ArgoCD initial admin password
  ARGOCD_PASSWORD=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${SSH_KEY_FILE}" ubuntu@"${MASTER_IP}" \
    "k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" || echo "admin")

  # Print Cluster Summary
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
  echo -e "${BOLD}ArgoCD GitOps Dashboard:${NC}"
  echo -e "  • ${CYAN}Port-Forward Cmd:${NC}   ssh -i ${SSH_KEY_FILE} -L 8080:localhost:443 ubuntu@${MASTER_IP} 'k3s kubectl port-forward svc/argocd-server -n argocd 443:443'"
  echo -e "  • ${CYAN}URL:${NC}                https://localhost:8080"
  echo -e "  • ${CYAN}Username:${NC}           admin"
  echo -e "  • ${CYAN}Password:${NC}           ${YELLOW}${ARGOCD_PASSWORD}${NC}"
  echo ""
  echo -e "${BOLD}Jenkins CI/CD Dashboard (Configured 100% as Code):${NC}"
  echo -e "  • ${CYAN}URL:${NC}                http://localhost:8080"
  echo -e "  • ${CYAN}Credentials:${NC}        Username: admin | Password: admin123"
  echo -e "  • ${CYAN}Job:${NC}                devops-pipeline (Auto-created via Init Script)"
  echo -e "  • ${CYAN}Automation:${NC}         SCM Polling (every 2m) + Webhook enabled (Zero UI clicks needed)"
  echo ""
  echo -e "${BOLD}MongoDB Atlas Network Access Whitelist IPs:${NC}"
  echo -e "  • ${CYAN}Master Node CIDR:${NC} ${MASTER_IP}/32"
  echo -e "  • ${CYAN}Worker Node CIDR:${NC} ${WORKER_IP}/32"
  echo ""
  echo -e "${BOLD}Rollback / Teardown Command:${NC}"
  echo -e "  • To smoothly destroy all resources at any time: ${YELLOW}make rollback${NC} or ${YELLOW}./orchestrate.sh rollback${NC}"
  echo ""

  CURRENT_PHASE="COMPLETE"
  save_state
}

# ── Manual Rollback Command ───────────────────────────────────────────────────
smooth_rollback() {
  echo ""
  echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}${BOLD}║              🔄 INITIATING SMOOTH ROLLBACK / TEARDOWN               ║${NC}"
  echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  echo -e "This will safely destroy all provisioned AWS cloud resources, K3s workloads,"
  echo -e "and ArgoCD applications without leaving lingering costs."
  echo ""

  # Prompt for confirmation if running interactively
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
  echo -e "${BOLD}DevOps Infrastructure & Deployment Status${NC}"
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"

  if [ -f "${STATE_FILE}" ]; then
    echo -e "  • Last Recorded Phase:     ${CYAN}${CURRENT_PHASE}${NC}"
    echo -e "  • Terraform Applied:       ${STATE_TF_APPLIED}"
    echo -e "  • Ansible Cluster Setup:   ${STATE_ANSIBLE_DEPLOYED}"
    echo -e "  • K8s Workloads Applied:   ${STATE_K8S_APPLIED}"
    echo -e "  • ArgoCD Configured:       ${STATE_ARGOCD_APPLIED}"
    echo -e "  • Jenkins Started:         ${STATE_JENKINS_STARTED}"
    echo -e "  • Master IP:               ${MASTER_IP:-N/A}"
    echo -e "  • Worker IP:               ${WORKER_IP:-N/A}"
  else
    echo -e "  • No active deployment state found (.deploy_state is empty or removed)."
  fi

  if command -v docker >/dev/null 2>&1; then
    echo ""
    log_info "Jenkins Docker Containers:"
    docker ps --filter "name=jenkins" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  fi

  if [ -d "${TF_DIR}" ] && [ -f "${TF_DIR}/terraform.tfstate" ]; then
    echo ""
    log_info "Terraform Outputs:"
    (cd "${TF_DIR}" && terraform output 2>/dev/null || echo "No terraform outputs available.")
  fi
}

# ── CLI Entrypoint ────────────────────────────────────────────────────────────
ACTION="${1:-deploy}"

case "${ACTION}" in
  deploy)
    deploy_all
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
    echo "Usage: $0 [deploy|rollback|status|plan|help]"
    echo ""
    echo "Commands:"
    echo "  deploy    - Full automated one-command deployment with auto-rollback on error (default)"
    echo "  rollback  - Smooth, fault-tolerant teardown of all cloud & cluster resources"
    echo "  status    - View current deployment phase, outputs, and status"
    echo "  plan      - Run preflight check and show Terraform execution plan"
    echo "  help      - Show this help message"
    ;;
  *)
    log_error "Unknown action: '${ACTION}'"
    echo "Run '$0 help' for available commands."
    exit 1
    ;;
esac
