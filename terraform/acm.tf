# ── ACM Certificate ────────────────────────────────────────────────────────────
resource "aws_acm_certificate" "ghost" {
  domain_name               = aws_route53_zone.main.name
  subject_alternative_names = ["www.${aws_route53_zone.main.name}"]
  validation_method         = "DNS"

  # Create new cert before destroying old one to avoid downtime on renewals
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "ghost-blog-${var.environment}" }
}

# ── DNS validation records (auto-created in the hosted zone) ──────────────────
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ghost.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

# Blocks until ACM confirms the certificate is issued
resource "aws_acm_certificate_validation" "ghost" {
  certificate_arn         = aws_acm_certificate.ghost.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
