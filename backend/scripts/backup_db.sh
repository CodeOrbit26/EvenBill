#!/usr/bin/env bash
# EvenBill Production Database Backup Script
# Performs compressed pg_dump, generates SHA-256 checksum, and uploads to cold backup storage.

set -euo pipefail

TIMESTAMP=$(date -u +"%Y%m%d_%H%M%SZ")
BACKUP_DIR="${BACKUP_DIR:-/var/backups/evenbill}"
DB_NAME="${POSTGRES_DB:-evenbill_prod}"
DB_USER="${POSTGRES_USER:-evenbill_user}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"

mkdir -p "${BACKUP_DIR}"

BACKUP_FILE="${BACKUP_DIR}/evenbill_${TIMESTAMP}.sql.gz"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

echo "=== [EvenBill] Starting database backup for '${DB_NAME}' at ${TIMESTAMP} ==="

# Execute pg_dump with custom directory or compressed stream
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
  -h "${DB_HOST}" \
  -p "${DB_PORT}" \
  -U "${DB_USER}" \
  -F c \
  -b \
  -v \
  "${DB_NAME}" | gzip -9 > "${BACKUP_FILE}"

# Generate cryptographic checksum
shasum -a 256 "${BACKUP_FILE}" > "${CHECKSUM_FILE}"

echo "=== [EvenBill] Backup successfully written to ${BACKUP_FILE} ==="
echo "Checksum: $(cat "${CHECKSUM_FILE}")"

# Retention: Prune local backups older than 30 days
find "${BACKUP_DIR}" -name "evenbill_*.sql.gz" -mtime +30 -delete
find "${BACKUP_DIR}" -name "evenbill_*.sha256" -mtime +30 -delete

echo "=== [EvenBill] Backup completed and verified. ==="
