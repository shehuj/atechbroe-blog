#!/bin/bash
# =============================================================================
# Ghost Blog — EC2 Bootstrap Script
# Processed by Terraform templatefile(). Escaping rules:
#   $${VAR}   → becomes $${VAR} in the final script (Terraform escape)
#   $${tf_var} → replaced by Terraform with the actual value
#   $VAR      → plain bash variable, Terraform ignores
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Ghost Blog Bootstrap — $(date -u) ==="

# ── 1. System updates & dependencies ─────────────────────────────────────────
dnf update -y
dnf install -y docker aws-cli python3 xfsprogs

systemctl enable --now docker
usermod -aG docker ec2-user

# Enable automatic security updates
dnf install -y dnf-automatic
sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

# ── 2. Docker Compose plugin ──────────────────────────────────────────────────
COMPOSE_VERSION="v2.24.5"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ── 3. Wait for data EBS volume, format and mount ────────────────────────────
DATA_DEVICE=""
echo "Waiting for data EBS volume..."
for attempt in $(seq 1 30); do
  for dev in /dev/nvme1n1 /dev/xvdf; do
    if [ -b "$dev" ]; then
      DATA_DEVICE="$dev"
      break 2
    fi
  done
  echo "  attempt $${attempt}/30 — sleeping 5s"
  sleep 5
done

if [ -z "$DATA_DEVICE" ]; then
  echo "ERROR: data volume not found after 150s" >&2
  exit 1
fi

# Format only on first boot (skip if filesystem already exists)
if ! blkid "$DATA_DEVICE" &>/dev/null; then
  echo "Formatting $DATA_DEVICE as xfs..."
  mkfs.xfs "$DATA_DEVICE"
fi

mkdir -p /opt/ghost
DEV_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
echo "UUID=$${DEV_UUID} /opt/ghost xfs defaults,nofail 0 2" >> /etc/fstab
mount -a
echo "Data volume mounted at /opt/ghost"

# ── 4. Directory structure ────────────────────────────────────────────────────
mkdir -p /opt/ghost/{content,mysql,nginx/conf.d}
chown -R ec2-user:docker /opt/ghost
chmod 750 /opt/ghost

# ── 5. Retrieve secrets from AWS Secrets Manager ─────────────────────────────
echo "Fetching secrets..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

DB_PASSWORD=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
DB_ROOT_PASSWORD=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_password'])")

# Write .env — readable only by root (Docker Compose picks this up automatically)
cat > /opt/ghost/.env << ENV
GHOST_IMAGE=${ghost_image}
GHOST_URL=${ghost_url}
LOG_GROUP=${log_group}
AWS_REGION=${aws_region}
DB_PASSWORD=$${DB_PASSWORD}
DB_ROOT_PASSWORD=$${DB_ROOT_PASSWORD}
ENV
chmod 600 /opt/ghost/.env

# Erase secrets from shell memory
unset DB_PASSWORD DB_ROOT_PASSWORD SECRET_JSON

# ── 6. Nginx reverse proxy config ────────────────────────────────────────────
# TLS is terminated at the ALB (ACM certificate). Nginx receives plain HTTP
# from the ALB and proxies to Ghost on port 2368.
# X-Forwarded-Proto is set by the ALB and forwarded to Ghost so Ghost knows
# the original request was HTTPS.
cat > /opt/ghost/nginx/conf.d/ghost.conf << 'NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass         http://ghost:2368;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_read_timeout 90s;
        client_max_body_size 50m;
    }
}
NGINX

# ── 7. docker-compose.yml ─────────────────────────────────────────────────────
# Uses $${VAR} references — Docker Compose reads values from /opt/ghost/.env
cat > /opt/ghost/docker-compose.yml << 'COMPOSE'
services:

  ghost:
    image: $${GHOST_IMAGE}
    restart: always
    environment:
      url: $${GHOST_URL}
      database__client: mysql
      database__connection__host: db
      database__connection__port: 3306
      database__connection__database: ghost
      database__connection__user: ghost
      database__connection__password: $${DB_PASSWORD}
    volumes:
      - ./content:/var/lib/ghost/content
    networks:
      - ghost-net
    depends_on:
      db:
        condition: service_healthy
    logging:
      driver: awslogs
      options:
        awslogs-region: $${AWS_REGION}
        awslogs-group: $${LOG_GROUP}
        awslogs-stream: ghost

  db:
    image: mysql:8.0
    restart: always
    environment:
      MYSQL_DATABASE: ghost
      MYSQL_USER: ghost
      MYSQL_PASSWORD: $${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: $${DB_ROOT_PASSWORD}
    volumes:
      - ./mysql:/var/lib/mysql
    networks:
      - ghost-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging:
      driver: awslogs
      options:
        awslogs-region: $${AWS_REGION}
        awslogs-group: $${LOG_GROUP}
        awslogs-stream: db

  nginx:
    image: nginx:1.27-alpine
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    networks:
      - ghost-net
    depends_on:
      - ghost
    logging:
      driver: awslogs
      options:
        awslogs-region: $${AWS_REGION}
        awslogs-group: $${LOG_GROUP}
        awslogs-stream: nginx

networks:
  ghost-net:
    driver: bridge
COMPOSE

# ── 8. Systemd service ────────────────────────────────────────────────────────
cat > /etc/systemd/system/ghost.service << 'SYSTEMD'
[Unit]
Description=Ghost Blog Stack
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/ghost
Environment=HOME=/root
EnvironmentFile=/opt/ghost/.env
ExecStartPre=/usr/bin/docker compose pull --quiet
ExecStart=/usr/bin/docker compose up --remove-orphans
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=30s
TimeoutStartSec=300s

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable --now ghost

echo "=== Bootstrap complete — $(date -u) ==="
echo "Ghost starting at ${ghost_url}"
echo "TLS is terminated at the ALB (ACM certificate) — no local cert setup required."
echo "Check status: docker compose -f /opt/ghost/docker-compose.yml ps"
echo "View logs:    journalctl -u ghost -f"
