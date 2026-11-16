# ──────────────────────────────────────────────────────────────
# Terraform Provider Configuration
# Defines the required providers and their versions
# ──────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ────────────────────────────────────────────────────────────
  # S3 Backend for remote state storage
  # Uncomment and configure once the S3 bucket is created
  # ────────────────────────────────────────────────────────────
  # backend "s3" {
  #   bucket         = "devops-project-tfstate"
  #   key            = "infra/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock"
  # }
}

# ──────────────────────────────────────────────────────────────
# AWS Provider — uses the region defined in variables
# ──────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
