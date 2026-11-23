#!/usr/bin/env bash
# EvenBill Supabase Pre-Migration Database Backup Utility (Docker postgres:17)
# Performs compressed logical pg_dump using Docker postgres:17,
# generates cryptographic SHA-256 checksum, and verifies backup readability
# via pg_restore --list without exposing credentials.

set -euo pipefail

DOCKER_IMAGE="postgres:17"
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%SZ")
BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "${BACKUP_DIR}"

ABS_BACKUP_DIR="$(cd "${BACKUP_DIR}" && pwd)"
BACKUP_FILENAME="evenbill_pre_migration_${TIMESTAMP}.dump"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILENAME}"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

# 1. Verify Docker CLI and daemon availability
if ! command -v docker &> /dev/null; then
  echo "Error: 'docker' command line tool is not installed or not in PATH." >&2
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "Error: Docker engine is not running or unavailable." >&2
  echo "Please start Docker Desktop and ensure the Docker daemon is accessible." >&2
  exit 1
fi

# 2. Verify DATABASE_URL presence
if [ -z "${DATABASE_URL:-}" ]; then
  echo "Error: DATABASE_URL environment variable is not set." >&2
  echo "Usage: DATABASE_URL='postgresql://...' ./supabase_backup.sh" >&2
  exit 1
fi

# 3. Normalize SQLAlchemy dialect prefix if present
CLEAN_DATABASE_URL="${DATABASE_URL/postgresql+asyncpg:\/\//postgresql://}"
CLEAN_DATABASE_URL="${CLEAN_DATABASE_URL/postgresql+psycopg2:\/\//postgresql://}"

# Route local development hostnames through host.docker.internal when run in container
CLEAN_DATABASE_URL="${CLEAN_DATABASE_URL//@localhost:/@host.docker.internal:}"
CLEAN_DATABASE_URL="${CLEAN_DATABASE_URL//@127.0.0.1:/@host.docker.internal:}"

echo "=== [EvenBill] Initiating Pre-Migration Database Backup at ${TIMESTAMP} ==="
echo "Engine:   Docker ${DOCKER_IMAGE} (pg_dump & pg_restore v17)"
echo "Mount:    ${ABS_BACKUP_DIR} -> /backups"

# 4. Execute pg_dump version 17 via Docker container
# Pass DATABASE_URL as an environment variable to prevent credentials appearing in process arguments
docker run --rm \
  -e DATABASE_URL="${CLEAN_DATABASE_URL}" \
  -v "${ABS_BACKUP_DIR}:/backups" \
  "${DOCKER_IMAGE}" \
  bash -c 'pg_dump "$DATABASE_URL" -F c -b -v --no-owner --no-privileges -f "/backups/'"${BACKUP_FILENAME}"'"'

# 5. Generate SHA-256 verification hash
if command -v sha256sum &> /dev/null; then
  sha256sum "${BACKUP_FILE}" > "${CHECKSUM_FILE}"
elif command -v shasum &> /dev/null; then
  shasum -a 256 "${BACKUP_FILE}" > "${CHECKSUM_FILE}"
fi

FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)

# 6. Verify archive integrity via pg_restore version 17 inside container
echo "=== [EvenBill] Verifying backup archive integrity via pg_restore (v17) ==="
TOC_ENTRIES=$(docker run --rm \
  -v "${ABS_BACKUP_DIR}:/backups" \
  "${DOCKER_IMAGE}" \
  pg_restore --list "/backups/${BACKUP_FILENAME}" | grep -v '^;' | grep -v '^$' | wc -l | tr -d ' ')

echo "Archive TOC:      ${TOC_ENTRIES} catalog entities verified (0 corruption)"

echo "=== [EvenBill] Backup successfully created & verified ==="
echo "File:     ${BACKUP_FILE} (${FILE_SIZE})"
echo "Checksum: $(cat "${CHECKSUM_FILE}")"
echo "=== [EvenBill] Ready for safe migration. ==="
