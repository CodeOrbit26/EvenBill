# EvenBill Production Readiness & Release Checklist

> **Crucial Notice:** EvenBill has been architecturally and technically hardened, with 100% passing automated test suites across both the Python FastAPI backend (60/60 tests) and Flutter mobile application (34/34 tests). However, **it is NOT claimed to be production-ready simply because it builds**. True production readiness requires completing the external approvals, store configurations, cryptographic signing keys, and compliance audits cataloged below.

---

## 1. Technical Hardening Implemented to Date

| Domain | Hardened Capability | Verification Status |
| :--- | :--- | :--- |
| **Security: Authorization** | Object-level authorization (IDOR protection) on all expense edit/delete, invitation revoke/accept, and split template endpoints. | Verified (`test_idor_protection_expense_and_invitation`) |
| **Security: Concurrency** | Optimistic Concurrency Control via integer `version` field. Version collisions reject with `HTTP 409 Conflict` (no silent overwrites). | Verified (`test_optimistic_concurrency_conflict_detection`) |
| **Security: Sessions & Tokens**| JWT with sliding refresh token rotation and replay-attack detection (revoked JTI ledger). Password complexity enforcement (min 8 chars, 1 digit, 1 letter). | Verified (`test_refresh_token_rotation_and_replay_detection`) |
| **Security: Rate Limiting** | Sliding window rate limiting on `/register` (60/min), `/login` (60/min), invitations (25/hr), uploads (15/min), and search (60/min). | Verified (`test_rate_limiting_enforcement`) |
| **Security: Headers & CSRF** | Injected `HSTS` (31536000s), `CSP`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and CSRF protection for cookie-authenticated sessions. | Verified (`test_security_headers_and_correlation_id`) |
| **Privacy: Data Portability** | GDPR Article 20 / CCPA data export (`POST /api/v1/users/me/export`) bundling profile, groups, expenses, splits, and subscriptions. | Verified (`test_privacy_data_export_and_ledger_preserving_deletion`) |
| **Privacy: Account Deletion** | GDPR Article 17 Right to Erasure (`DELETE /api/v1/users/me`) anonymizing PII ("Former Member") while preserving historical ledger invariant so group math never breaks. | Verified (`test_privacy_data_export_and_ledger_preserving_deletion`) |
| **Privacy: Receipts** | 15-minute time-limited signed S3 URLs. 30-day statutory audit retention quarantine before automated permanent purge. | Verified (`purge_expired_quarantined_receipts`) |
| **Offline Sync Engine** | Durable client outbox queue, unique operation IDs, server idempotency keys, bounded retries with exponential backoff & jitter, and explicit UI conflict status. | Verified (`offline_sync_test.dart`) |
| **Observability** | Structured JSON logging with `X-Correlation-ID` distributed tracing, request duration metrics, and automated regex financial/PII masking. | Verified (`app/core/logging.py`) |
| **Reliability: Health** | Kubernetes/Docker orchestration `/health/live` (process alive) and `/health/ready` (DB connection probe) returning HTTP 200/503. | Verified (`test_health_and_readiness_probes`) |
| **Disaster Recovery** | Automated database backup (`backup_db.sh`) with SHA-256 checksums and restore procedures (`restore_db.sh`). | Verified |

---

## 2. External Credentials & Secret Manager Configurations Still Required

Before deploying EvenBill to production infrastructure, the following external cloud platform credentials must be provisioned into **AWS Secrets Manager**, **GCP Secret Manager**, or **HashiCorp Vault** (never committed to git):

- [ ] **Production JWT Secret Key (`SECRET_KEY`):** Minimum 256-bit cryptographically random entropy string (`openssl rand -hex 64`).
- [ ] **Production Database Credentials (`DATABASE_URL`):** Multi-AZ PostgreSQL 16 cluster credentials with SSL forced (`?ssl=require`).
- [ ] **Production Redis Cluster Auth (`REDIS_URL`):** TLS-enabled Redis Sentinel / AWS ElastiCache auth token.
- [ ] **Private S3 Bucket Credentials:** IAM Role ARN with least-privilege scoped permissions for `s3:GetObject`, `s3:PutObject`, and KMS envelope encryption on `evenbill-receipts-production`.
- [ ] **App Store Connect API Key:** Issuer ID, Key ID, and `.p8` private key for server-to-server App Store Server Notifications v2 and subscription entitlement verification.
- [ ] **Google Play Developer Service Account:** Google Cloud service account JSON credentials with `Android Publisher` API permissions for Google Play Real-Time Developer Notifications (RTDN).
- [ ] **Open Banking / Plaid Production Keys:** Production Client ID, Secret, and mTLS certificates for regulated bank transaction imports.
- [ ] **SendGrid / Postmark SMTP Credentials:** Verified domain records (DKIM, SPF, DMARC) for group invitation emails.

---

## 3. Store Configurations & Approvals Required

### Apple App Store (iOS)
- [ ] **Distribution Certificate & Provisioning Profile:** Production Apple Distribution Certificate and explicit App Store provisioning profile with App Group and Push Notification entitlements.
- [ ] **Universal Links / Associated Domains:** Host `apple-app-site-association` file on `https://evenbill.app/.well-known/apple-app-site-association` with matching App ID for group invite deep linking.
- [ ] **App Store Privacy Nutrition Labels:**
  - *Financial Info (Payment Info, Other Financial Info):* Linked to User, Used for App Functionality.
  - *Contact Info (Email, Name, Phone Number):* Linked to User, Used for Account Management.
  - *User Content (Photos/Receipts):* Linked to User, Used for App Functionality.
  - *Diagnostics (Crash Data, Performance Data):* Not Linked to User.
- [ ] **In-App Purchase Configuration:**
  - Monthly Pro Auto-Renewable Subscription (`evenbill.pro.monthly`, $4.99)
  - Annual Pro Auto-Renewable Subscription (`evenbill.pro.annual`, $39.99)
  - App Store Server Notifications v2 webhook endpoint configured to `https://api.evenbill.app/api/v1/subscriptions/webhooks/apple`.

### Google Play Store (Android)
- [ ] **Android App Signing:** Upload key generated in secure HSM/vault; Google Play App Signing key registered in Play Console.
- [ ] **App Links Verification:** Host Digital Asset Links JSON on `https://evenbill.app/.well-known/assetlinks.json` with matching SHA-256 certificate fingerprint.
- [ ] **Data Safety Section:**
  - Disclose collection of Financial information, Personal info, and Photos/Receipts.
  - Certify encryption in transit (HTTPS/TLS) and compliance with deletion requests via `DELETE /api/v1/users/me`.
- [ ] **Google Play Subscriptions Configuration:**
  - Base plan products created with grace period (16 days) and account hold enabled.
  - Cloud Pub/Sub topic linked for Real-Time Developer Notifications to `https://api.evenbill.app/api/v1/subscriptions/webhooks/google`.

---

## 4. Audits & Compliance Gates

- [ ] **Third-Party Penetration Test:** Engage a certified cybersecurity firm to conduct an OWASP ASVS (Application Security Verification Standard) Level 2 assessment covering IDOR, injection, auth bypass, and cryptographic implementations.
- [ ] **GDPR / CCPA Legal Review:** Validate privacy policy, terms of service, and statutory data retention periods (30-day receipt audit window vs. Right to Erasure ledger preservation).
- [ ] **SOC 2 Type I/II Readiness Audit:** Document access control policies, change management workflows, CI/CD code freeze requirements, and incident response runbooks.

---

## 5. Zero-Downtime Deployment & Rollback Runbook

### Deployment Procedure (Blue/Green or Rolling Update)
1. **Database Migration Phase (Expand-Contract):**
   ```bash
   # Run additive migrations only (never drop columns in the first deploy step)
   alembic upgrade head
   ```
2. **Container Image Build & Vulnerability Scan:**
   ```bash
   docker build -t evenbill/backend:v1.0.0 -f Dockerfile .
   trivy image evenbill/backend:v1.0.0
   ```
3. **Deploy Canary / Green Replica Pool:**
   - Launch new container task pool using image `v1.0.0`.
   - Wait for `/health/live` (process up) and `/health/ready` (DB connected) probes to report 200 OK across all containers.
4. **Shift Production Traffic:**
   - Shift 10% -> 50% -> 100% traffic via ALB / Nginx reverse proxy.
   - Monitor error rate, 4xx/5xx spikes, and latency on Datadog / CloudWatch.
5. **Drain & Terminate Old Replicas:**
   - Allow existing connections 60 seconds to terminate cleanly before decommissioning previous task pool.

### Rollback Procedure
If 5xx error rate exceeds 0.1% or latency p99 exceeds 500ms post-deployment:
1. **Immediate Traffic Reversion:**
   - Reroute 100% ingress traffic back to the previous stable container task pool.
2. **Database Migration Rollback (if applicable):**
   ```bash
   alembic downgrade -1
   ```
3. **Emergency Point-In-Time Restore (in case of catastrophic corruption):**
   ```bash
   ./scripts/restore_db.sh /var/backups/evenbill/evenbill_pre_release_snapshot.sql.gz
   ```
