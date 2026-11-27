# AWS Terraform patterns (load only for AWS tasks)
Provider: `hashicorp/aws` **~> 6.0** (6.x adds per-resource `region`). Verify attribute names for the pinned version via the terraform MCP / AWS MCP docs search before writing.

## Auth & state (never static keys in code or tfvars)
- Local: `aws sso login --profile <p>` (IAM Identity Center) → `AWS_PROFILE=<p>`; check with `aws sts get-caller-identity`.
- CI: GitHub Actions/Azure DevOps OIDC → `AssumeRoleWithWebIdentity` into a deploy role (no access keys).
- State: S3 backend with native locking (`use_lockfile = true`, Terraform ≥ 1.11; DynamoDB locking only for older setups), bucket versioning + SSE-KMS + public access block.
```hcl
terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
  backend "s3" { bucket = "tfstate-<acct>-<region>", key = "app/dev/terraform.tfstate", region = "ap-south-1", encrypt = true, use_lockfile = true }
}
provider "aws" {
  region = var.region
  default_tags { tags = local.tags }          # env, owner, cost-center, managed-by
}
```

## Secure EC2 baseline (what "create an EC2 with security" means here)
| Control | Terraform | Rule |
|---|---|---|
| No SSH from the internet; no key pair | SSM Session Manager via instance profile `AmazonSSMManagedInstanceCore`; SG has **no** port 22/3389 ingress | TF-SEC-004 |
| Private subnet, no public IP | `subnet_id = <private>`, `associate_public_ip_address = false`; egress via NAT or VPC endpoints (ssm, ssmmessages, ec2messages, s3) | TF-SEC-010 |
| IMDSv2 only | `metadata_options { http_tokens = "required", http_put_response_hop_limit = 1, http_endpoint = "enabled" }` | TF-SEC-009 |
| Encrypted disks | `root_block_device { encrypted = true, volume_type = "gp3", kms_key_id = <cmk or default> }` + account-level `aws_ebs_encryption_by_default { enabled = true }` | TF-SEC-005 |
| Least-privilege role | instance profile with only what the app needs; never AdministratorAccess / `*` | TF-SEC-011 |
| Patched, current AMI | `data "aws_ssm_parameter" "al2023" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }` → `ami = data.aws_ssm_parameter.al2023.value` (+ `lifecycle { ignore_changes = [ami] }` if you patch in place) | TF-MNT-006 |
| Observability | `monitoring = true`, CloudWatch agent via SSM, VPC flow logs | TF-OPS-003 |
| Prod safety | `disable_api_termination = true`, AWS Backup plan, `prevent_destroy` on data volumes | TF-REL-002 |
| No secrets in user_data | fetch from Secrets Manager / SSM Parameter Store (SecureString) at boot via the instance role | TF-SEC-001 |

```hcl
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-ec2"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-ec2"
  role = aws_iam_role.app.name
}

resource "aws_security_group" "app" {
  name   = "${local.name}-app"
  vpc_id = var.vpc_id
  # no SSH/RDP ingress: admin access is SSM Session Manager
}
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = var.alb_sg_id          # only the load balancer reaches the app port
  ip_protocol = "tcp"
  from_port   = 8080
  to_port     = 8080
}
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"                       # tighten to VPC endpoints / prefix lists where possible
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type        # validate against an allow-list per env
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = false
  monitoring                  = true
  disable_api_termination     = var.env == "prod"
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_gb
  }
  tags = { Name = "${local.name}-app" }
}
```
Typed inputs: `variable "instance_type" { type = string; validation { condition = contains(["t3.micro","t3.small","m7i.large"], var.instance_type) … } }`, `variable "env"` limited to dev/qa/prod, subnet/VPC IDs validated with `can(regex("^subnet-", …))`.

## Common AWS errors → cause
- `UnauthorizedOperation` / `AccessDenied` → IAM permission or SCP; read the encoded message with `aws sts decode-authorization-message`. Not a code fix.
- `InvalidParameterCombination` on instance type → type not offered in that AZ/region; check `aws ec2 describe-instance-type-offerings`.
- Instance not in Session Manager → missing instance profile / no route to SSM endpoints / SSM agent not running.
- `VcpuLimitExceeded` → service quota; request an increase, don't switch regions silently.

## Cost drivers to hand to FinOps
instance type × hours (730/month), EBS GB × type, NAT gateway hours + GB processed (often the surprise), data transfer out, VPC interface endpoints (per AZ per hour). `aws-price.sh ec2 <type> --region <r> --currency INR`, `aws-price.sh ebs gp3 --gb N`.
