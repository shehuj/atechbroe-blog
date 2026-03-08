# ---------------------------------------------------------------
# Production-hardened Ghost blog image
# Pin to a specific patch version in production, e.g.:
#   ghost:5.87.2-alpine
# Use `docker pull ghost:5-alpine` to get the latest digest
#   then replace the tag with: ghost:5-alpine@sha256:<digest>
# ---------------------------------------------------------------
FROM ghost:5-alpine

# OCI-standard image labels for auditing and registries
LABEL org.opencontainers.image.title="atechbroe-blog" \
      org.opencontainers.image.description="Ghost blog for atechbroe" \
      org.opencontainers.image.vendor="atechbroe" \
      maintainer="atechbroe"

# Production mode: disables debug logging, enables caching, hardens defaults
ENV NODE_ENV=production

# Upgrade Alpine system packages to patch known CVEs (e.g. golang net/url, archive/zip,
# crypto/x509). Must run as root; we drop back to node immediately after.
USER root
RUN apk upgrade --no-cache
USER node

# Health check: start-period accounts for Ghost boot (DB migrations, asset compilation)
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:2368/ || exit 1

# Declare the content volume explicitly so orchestrators/compose treat it as persistent.
# Always mount this in production — it holds images, themes, and the SQLite database.
VOLUME ["/var/lib/ghost/content"]

EXPOSE 2368
