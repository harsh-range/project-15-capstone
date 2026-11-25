terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Generate SSH key pair
resource "tls_private_key" "ssh_credentials" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload public key to AWS
resource "aws_key_pair" "deployment_key" {
  key_name   = "harsh-deployment-key"
  public_key = tls_private_key.ssh_credentials.public_key_openssh
}

# Save private key locally
resource "local_file" "private_key_file" {
  filename        = "${path.module}/harsh-access.pem"
  content         = tls_private_key.ssh_credentials.private_key_pem
  file_permission = "0400"
}

# Security Group
resource "aws_security_group" "web_access_group" {
  name        = "harsh-web-access"
  description = "Allow HTTPS and HTTP traffic"

  ingress {
    description = "HTTPS Access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound Internet Access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Retrieve latest Amazon Linux 2023 AMI
data "aws_ami" "linux2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# EC2 Instance
resource "aws_instance" "application_server" {
  ami           = data.aws_ami.linux2023.id
  instance_type = "t2.micro"

  key_name               = aws_key_pair.deployment_key.key_name
  vpc_security_group_ids = [aws_security_group.web_access_group.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Port 443" >> /etc/ssh/sshd_config
              systemctl restart sshd
              EOF

  tags = {
    Name        = "Harsh-Web-Server"
  }
}

output "instance_public_ip" {
  description = "Public IP Address of EC2 Instance"
  value       = aws_instance.application_server.public_ip
}

output "generated_key_name" {
  value = aws_key_pair.deployment_key.key_name
}