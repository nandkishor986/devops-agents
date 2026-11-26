#!/usr/bin/env bash
mkdir -p infra && cat > infra/ec2.tf <<'TF'
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
resource "aws_security_group" "web" {
  name = "web"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_instance" "web" {
  ami                         = "ami-0abcdef1234567890"
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web.id]
}
TF
