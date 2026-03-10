# ── Route 53 Hosted Zone ──────────────────────────────────────────────────────
resource "aws_route53_zone" "main" {
  name = "jenom.com"

  tags = { Name = "jenom.com" }
}

# ── A records — root + www ─────────────────────────────────────────────────────
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "jenom.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.ghost.public_ip]
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.jenom.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.ghost.public_ip]
}

# ── CAA — restrict SSL issuance to Let's Encrypt only ─────────────────────────
resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "jenom.com"
  type    = "CAA"
  ttl     = 3600
  records = [
    "0 issue \"letsencrypt.org\"",
    "0 issuewild \"letsencrypt.org\"",
    "0 iodef \"mailto:admin@jenom.com\"",
  ]
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "nameservers" {
  description = "Route 53 nameservers — update these at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}

output "zone_id" {
  description = "Route 53 hosted zone ID (set as ROUTE53_ZONE_ID GitHub secret)"
  value       = aws_route53_zone.main.zone_id
}
