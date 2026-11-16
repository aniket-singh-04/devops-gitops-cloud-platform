# ──────────────────────────────────────────────────────────────
# EC2 Instances
# Provisions K3s master and worker nodes
# ──────────────────────────────────────────────────────────────

# ────────────── K3s Master Node ──────────────

resource "aws_instance" "k3s_master" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.k3s_master.id]

  # Root volume — 20 GB is enough for K3s master
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-k3s-master-vol"
    }
  }

  # User data script runs on first boot to install base packages
  user_data = <<-EOF
    #!/bin/bash
    # Update system packages
    apt-get update -y && apt-get upgrade -y

    # Install essential tools
    apt-get install -y curl wget git unzip software-properties-common

    # Tag the instance for Ansible dynamic inventory (optional)
    echo "role=k3s-master" > /etc/instance-role
  EOF

  tags = {
    Name = "${var.project_name}-k3s-master"
    Role = "master"
  }
}

# ────────────── K3s Worker Node ──────────────

resource "aws_instance" "k3s_worker" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.k3s_worker.id]

  # Root volume — 20 GB for worker node
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-k3s-worker-vol"
    }
  }

  # User data script runs on first boot
  user_data = <<-EOF
    #!/bin/bash
    # Update system packages
    apt-get update -y && apt-get upgrade -y

    # Install essential tools
    apt-get install -y curl wget git unzip software-properties-common

    # Tag the instance for Ansible dynamic inventory (optional)
    echo "role=k3s-worker" > /etc/instance-role
  EOF

  # Worker depends on master being available first
  depends_on = [aws_instance.k3s_master]

  tags = {
    Name = "${var.project_name}-k3s-worker"
    Role = "worker"
  }
}
