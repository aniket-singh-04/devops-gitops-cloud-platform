# ──────────────────────────────────────────────────────────────
# Input Variables
# All configurable parameters for the infrastructure
# ──────────────────────────────────────────────────────────────

# ────────────── General ──────────────

variable "project_name" {
  description = "Name of the project, used for tagging and resource naming"
  type        = string
  default     = "devops-project"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ────────────── AWS ──────────────

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

# ────────────── Networking ──────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use for subnets"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ────────────── EC2 Instances ──────────────

variable "instance_type" {
  description = "EC2 instance type for K3s nodes"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances (Ubuntu 22.04 LTS in ap-south-1)"
  type        = string
  default     = "ami-0f5ee92e2d63afc18"
}

variable "key_pair_name" {
  description = "Name of the SSH key pair for EC2 access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances (use your IP/32)"
  type        = string
  default     = "0.0.0.0/0"
}

# ────────────── DockerHub ──────────────

variable "dockerhub_username" {
  description = "DockerHub username for image repository naming"
  type        = string
}
