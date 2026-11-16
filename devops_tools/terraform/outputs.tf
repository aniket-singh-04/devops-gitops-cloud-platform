# ──────────────────────────────────────────────────────────────
# Outputs
# Values exported after terraform apply for use by other tools
# ──────────────────────────────────────────────────────────────

# ────────────── VPC ──────────────

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# ────────────── K3s Master ──────────────

output "k3s_master_public_ip" {
  description = "Public IP of the K3s master node (use in Ansible inventory)"
  value       = aws_instance.k3s_master.public_ip
}

output "k3s_master_private_ip" {
  description = "Private IP of the K3s master (used by workers to join cluster)"
  value       = aws_instance.k3s_master.private_ip
}

# ────────────── K3s Worker ──────────────

output "k3s_worker_public_ip" {
  description = "Public IP of the K3s worker node (use in Ansible inventory)"
  value       = aws_instance.k3s_worker.public_ip
}

output "k3s_worker_private_ip" {
  description = "Private IP of the K3s worker node"
  value       = aws_instance.k3s_worker.private_ip
}

# ────────────── SSH Command Helpers ──────────────

output "ssh_master" {
  description = "SSH command to connect to the K3s master"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.k3s_master.public_ip}"
}

output "ssh_worker" {
  description = "SSH command to connect to the K3s worker"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.k3s_worker.public_ip}"
}

# ────────────── MongoDB Atlas Whitelist IPs ──────────────

output "mongodb_atlas_whitelist_ips" {
  description = "Public CIDR IPs of K3s nodes to add in MongoDB Atlas Network Access list"
  value = [
    "${aws_instance.k3s_master.public_ip}/32",
    "${aws_instance.k3s_worker.public_ip}/32"
  ]
}
