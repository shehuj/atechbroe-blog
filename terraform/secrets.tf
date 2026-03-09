# ── KMS key for Secrets Manager ───────────────────────────────────────────────
resource "aws_kms_key" "secrets" {
  description             = "Ghost blog — Secrets Manager encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/ghost-blog-secrets-${var.environment}"
  target_key_id = aws_kms_key.secrets.key_id
}

# ── Random passwords (generated once, stored in Secrets Manager) ──────────────
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#%&*()-_=+[]{}<>?"
}

resource "random_password" "db_root" {
  length           = 32
  special          = true
  override_special = "!#%&*()-_=+[]{}<>?"
}

# ── Secrets Manager secret ────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "ghost_db" {
  name                    = "ghost-blog/${var.environment}/db"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "ghost_db" {
  secret_id = aws_secretsmanager_secret.ghost_db.id
  secret_string = jsonencode({
    password      = random_password.db.result
    root_password = random_password.db_root.result
  })
}
