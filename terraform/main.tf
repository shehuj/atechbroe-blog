# ── Data sources ──────────────────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Pin to a single AZ so EBS volume and EC2 instance are always co-located
data "aws_subnet" "primary" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── CloudWatch Log Group ───────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "ghost" {
  name              = "/ghost-blog/${var.environment}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "ghost" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.primary.id
  availability_zone      = data.aws_subnet.primary.availability_zone
  vpc_security_group_ids = [aws_security_group.ghost.id]
  iam_instance_profile   = aws_iam_instance_profile.ghost.name

  user_data = templatefile("${path.module}/userdata.sh", {
    ghost_image = var.ghost_image
    ghost_url   = var.ghost_url
    secret_arn  = aws_secretsmanager_secret.ghost_db.arn
    aws_region  = var.aws_region
    log_group   = "/ghost-blog/${var.environment}"
    environment = var.environment
  })

  # Replace instance (not update in-place) when user_data changes
  user_data_replace_on_change = true

  # IMDSv2 only — blocks SSRF attacks from stealing instance credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = aws_kms_key.ebs.arn
    delete_on_termination = true
  }

  tags = { Name = "ghost-blog-${var.environment}" }

  depends_on = [aws_secretsmanager_secret_version.ghost_db]
}

# ── Separate data EBS volume (outlives instance replacements) ─────────────────
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.primary.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.ebs.arn

  tags = { Name = "ghost-blog-data-${var.environment}" }

  lifecycle {
    prevent_destroy = true # Guard against accidental data loss
  }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.ghost.id
  force_detach = false
}

# ── Elastic IP ────────────────────────────────────────────────────────────────
resource "aws_eip" "ghost" {
  domain = "vpc"
  tags   = { Name = "ghost-blog-${var.environment}" }
}

resource "aws_eip_association" "ghost" {
  instance_id   = aws_instance.ghost.id
  allocation_id = aws_eip.ghost.id
}
