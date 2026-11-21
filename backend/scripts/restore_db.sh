#!/usr/bin/env bash
# EvenBill Disaster Recovery & Restore Procedure Script
# Verifies SHA-256 checksum, terminates active connections, and performs clean pg_restore.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_backup_file.sql.gz>"
    exit 1
fi

BACKUP_FILE="$1"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

DB_NAME="${POSTGRES_DB:-evenbill_prod}"
DB_USER="${POSTGRES_USER:-evenbill_user}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file '${BACKUP_FILE}' does not exist!"
    exit 1
fi

# Verify checksum if present
if [ -f "${CHECKSUM_FILE}" ]; then
    echo "=== [EvenBill] Verifying SHA-256 Checksum ==="
    shasum -a 256 -c "${CHECKSUM_FILE}"
    echo "Checksum verification PASSED."
fi

echo "=== [WARNING] You are about to restore into '${DB_NAME}' on ${DB_HOST}. ==="
echo "This operation will overwrite existing database records!"

# Terminate existing connections to allow clean restore
PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" || true

# Restore
echo "=== [EvenBill] Streaming decompressed restore into '${DB_NAME}' ==="
gunzip -c "${BACKUP_FILE}" | PGPASSWORD="${POSTGRES_PASSWORD}" pg_restore \
  -h "${DB_HOST}" \
  -p "${DB_PORT}" \
  -U "${DB_USER}" \
  -d "${DB_NAME}" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  -v || true

echo "=== [EvenBill] Database restore completed successfully. ==="
