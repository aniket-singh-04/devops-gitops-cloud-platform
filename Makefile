# ──────────────────────────────────────────────────────────────
# Master DevOps Makefile
# Unified control center for Docker, Jenkins, Terraform, Ansible,
# Kubernetes (K3s), and ArgoCD workflows
# ──────────────────────────────────────────────────────────────

DOC_COM        := docker compose
OS             := $(shell uname -s)
IMAGE_NAME     ?= devops-app
IMAGE_TAG      ?= latest
CONTAINER_NAME ?= express-app
SERVICE        ?= app
TF_DIR         := devops_tools/terraform
ANSIBLE_DIR    := devops_tools/ansible
K8S_DIR        := devops_tools/k8s
ARGOCD_DIR     := devops_tools/argocd
JENKINS_DIR    := devops_tools/jenkins

.DEFAULT_GOAL  := help

.PHONY: help deploy rollback deploy-status deploy-plan \
	build up up-build down restart logs ps status clean shell exec test-api health scan \
	tf-init tf-plan tf-apply tf-output tf-destroy \
	ansible-ping ansible-deploy \
	k8s-apply k8s-status k8s-delete \
	argocd-apply argocd-status \
	jenkins-up jenkins-down jenkins-logs

# ──────────────────────────────────────────────────────────────
# 📖 Help & Usage
# ──────────────────────────────────────────────────────────────
help: ## Show this help menu
	@echo "======================================================================"
	@echo "           🚀 DevOps Complete Project Automation CLI                  "
	@echo "======================================================================"
	@echo "Operating System: $(OS)"
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ──────────────────────────────────────────────────────────────
# ⚡ One-Command Deployment & Automated Rollback
# ──────────────────────────────────────────────────────────────
deploy: ## Run full automated deployment with auto-rollback on error
	@./orchestrate.sh deploy

rollback: ## Smoothly teardown all cloud & cluster resources fault-free
	@./orchestrate.sh rollback

deploy-status: ## Check live status of deployment and infrastructure
	@./orchestrate.sh status

deploy-plan: ## Run preflight check and show Terraform execution plan
	@./orchestrate.sh plan

# ──────────────────────────────────────────────────────────────
# 🐳 Docker & Local Application
# ──────────────────────────────────────────────────────────────
build: ## Build the application Docker image
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) CONTAINER_NAME=$(CONTAINER_NAME) $(DOC_COM) build

up: ## Start local application container in background
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) CONTAINER_NAME=$(CONTAINER_NAME) $(DOC_COM) up -d

up-build: ## Build image and start local container
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) CONTAINER_NAME=$(CONTAINER_NAME) $(DOC_COM) up -d --build

down: ## Stop and remove local application containers
	$(DOC_COM) down

restart: ## Restart the local application container
	$(DOC_COM) restart $(SERVICE)

logs: ## Tail application container logs
	$(DOC_COM) logs -f $(SERVICE)

ps: ## View running container status and health
	$(DOC_COM) ps

status: ps ## Alias for ps

clean: ## Remove containers, volumes, networks, and orphans
	$(DOC_COM) down -v --remove-orphans

shell: ## Open interactive shell inside application container
	$(DOC_COM) exec $(SERVICE) sh

test-api: ## Test application endpoints (GET / and GET /health)
	@echo "=== Testing GET / ==="
	@curl -s -w "\nHTTP Status: %{http_code}\n\n" http://localhost:4444/ || echo "Failed to connect to http://localhost:4444/"
	@echo "=== Testing GET /health ==="
	@curl -s -w "\nHTTP Status: %{http_code}\n\n" http://localhost:4444/health || echo "Failed to connect to http://localhost:4444/health"

health: ## Quick healthcheck test
	@curl -s http://localhost:4444/health || echo "Health check failed"

scan: ## Run Trivy vulnerability scan on application image
	@trivy image --severity HIGH,CRITICAL $(IMAGE_NAME):$(IMAGE_TAG) || echo "Trivy scan finished"

# ──────────────────────────────────────────────────────────────
# 🏗️ Terraform (AWS Infrastructure)
# ──────────────────────────────────────────────────────────────
tf-init: ## Initialize Terraform working directory
	cd $(TF_DIR) && terraform init

tf-plan: ## Generate and show Terraform execution plan
	cd $(TF_DIR) && terraform plan

tf-apply: ## Build or change AWS infrastructure
	cd $(TF_DIR) && terraform apply -auto-approve

tf-output: ## Show Terraform outputs (EC2 IPs, Atlas whitelist CIDRs)
	cd $(TF_DIR) && terraform output

tf-destroy: ## Destroy all AWS resources
	cd $(TF_DIR) && terraform destroy -auto-approve

# ──────────────────────────────────────────────────────────────
# ⚙️ Ansible (K3s Cluster Configuration)
# ──────────────────────────────────────────────────────────────
ansible-ping: ## Test Ansible SSH connectivity to K3s cluster nodes
	cd $(ANSIBLE_DIR) && ansible k3s_cluster -m ping

ansible-deploy: ## Run Ansible playbook to harden nodes and install K3s
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/site.yml

# ──────────────────────────────────────────────────────────────
# ☸️ Kubernetes (K3s Manifests)
# ──────────────────────────────────────────────────────────────
k8s-apply: ## Apply all Kubernetes manifests to current cluster
	kubectl apply -f $(K8S_DIR)/

k8s-status: ## Check status of application pods, services, ingress, and HPA
	kubectl get all,ingress,hpa -n devops-app

k8s-delete: ## Delete application workloads from cluster
	kubectl delete -f $(K8S_DIR)/

# ──────────────────────────────────────────────────────────────
# 🐙 ArgoCD (GitOps)
# ──────────────────────────────────────────────────────────────
argocd-apply: ## Apply ArgoCD project and application manifests
	kubectl apply -f $(ARGOCD_DIR)/project.yaml
	kubectl apply -f $(ARGOCD_DIR)/application.yaml

argocd-status: ## View ArgoCD application sync and health status
	kubectl get applications -n argocd

# ──────────────────────────────────────────────────────────────
# 🚀 Jenkins CI/CD
# ──────────────────────────────────────────────────────────────
jenkins-up: ## Start local Jenkins server and Buildah agent
	cd $(JENKINS_DIR) && docker compose up -d

jenkins-down: ## Stop Jenkins server
	cd $(JENKINS_DIR) && docker compose down

jenkins-logs: ## View Jenkins container logs
	cd $(JENKINS_DIR) && docker compose logs -f
