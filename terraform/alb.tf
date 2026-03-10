# ── ALB Security Group (internet-facing) ─────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "ghost-blog-alb-${var.environment}"
  description = "Ghost blog ALB - HTTP and HTTPS from internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "All outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "ghost-blog-alb-${var.environment}" }
}

# ── Application Load Balancer ──────────────────────────────────────────────────
# Spans all default subnets (multi-AZ) — ALB requires at least two AZs
resource "aws_lb" "ghost" {
  name               = "ghost-blog-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = { Name = "ghost-blog-${var.environment}" }
}

# ── Target Group — EC2 Nginx on port 80 ───────────────────────────────────────
resource "aws_lb_target_group" "ghost" {
  name     = "ghost-blog-${var.environment}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "ghost-blog-${var.environment}" }
}

resource "aws_lb_target_group_attachment" "ghost" {
  target_group_arn = aws_lb_target_group.ghost.arn
  target_id        = aws_instance.ghost.id
  port             = 80
}

# ── HTTP → HTTPS redirect (port 80) ───────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ghost.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ── HTTPS listener with ACM certificate (port 443) ────────────────────────────
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ghost.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.ghost.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ghost.arn
  }
}
