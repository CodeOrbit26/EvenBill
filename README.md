# EvenBill — Precision International Expense-Sharing Platform

**EvenBill** is a modern, secure, international expense-sharing platform engineered with mathematical precision, server-side authorization, and an ethical freemium model.

---

## 1. Monorepo Architecture

```
EvenBill/
├── backend/                  # Python 3.11+ / FastAPI / SQLAlchemy 2.0 Async
│   ├── app/
│   │   ├── api/v1/           # REST endpoints (auth, groups, expenses, settlements, health)
│   │   ├── core/             # Precision money engine, debt simplifier, security, config
│   │   ├── db/               # Async session & engine management
│   │   ├── models/           # SQLAlchemy ORM models (User, Group, Expense, Settlement, Audit)
│   │   ├── schemas/          # Pydantic v2 data transfer objects & validation
│   │   └── services/         # Domain services: LedgerService, AuthService
│   ├── tests/
│   │   ├── unit/             # Money math & debt simplification invariant tests
│   │   └── integration/      # Auth & complete financial ledger lifecycle API tests
│   ├── Dockerfile
│   └── requirements.txt
├── mobile/                   # Flutter 3.x / Dart cross-platform mobile client
│   ├── lib/
│   │   ├── core/             # Design tokens, theme, money models, API constants
│   │   └── main.dart         # Material 3 navigation shell, dark/light theme, balance overview
│   └── test/                 # Flutter widget test suite
├── infrastructure/
│   └── docker/
│       ├── docker-compose.yml# Multi-container stack (FastAPI, Postgres 16, Redis 7, MinIO, Mailpit)
│       └── .env.example      # Complete environment variable documentation
└── docs/                     # Specifications and architectural blueprints
```

---

## 2. Core Engineering Principles

1. **Zero Floating-Point Financial Loss:** All calculations use Python `Decimal` and `NUMERIC(18, 4)` columns with integer minor-unit conversion.
2. **Hare-Niemeyer Remainder Allocation:** Odd divisions (e.g., $100.00 among 3 participants) allocate remaining pennies deterministically, preserving the invariant:
   $$\sum \text{AllocatedShares} \equiv \text{TotalExpenseAmount}$$
3. **Bipartite Debt Simplification:** Circular and redundant debts are greedily reduced to at most $N - 1$ minimal cash-flow transfers while strictly preserving each member's net position.
4. **Immutable Audit Ledger:** Every expense insertion, edit, deletion, and settlement records a cryptographic change event in `financial_audit_logs`.
5. **No Fake Functionality:** Real endpoints, actual password hashing (bcrypt), signed JWT authentication, and validated test suites.

---

## 3. Local Development Quickstart

### Backend Setup & Test Suite
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Run full automated test suite (15 unit & integration tests)
pytest -v

# Run backend development server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Interactive API documentation: `http://localhost:8000/api/v1/docs`

### Docker Compose Stack
```bash
cd infrastructure/docker
docker compose up -d
```
Services exposed:
* **API:** `http://localhost:8000`
* **PostgreSQL 16:** `localhost:5432`
* **Redis 7:** `localhost:6379`
* **MinIO Console (S3):** `http://localhost:9001` (user: `minioadmin`, pass: `minioadmin`)
* **Mailpit (Mock SMTP):** `http://localhost:8025`

### Flutter Mobile App
```bash
cd mobile
flutter pub get
flutter test
flutter run
```

---

## 4. Test Verification Evidence

* **Backend Test Suite:** 15/15 passed (`test_money.py`, `test_simplification.py`, `test_auth_api.py`, `test_ledger_api.py`)
* **Flutter Test Suite:** Passed (`widget_test.dart`)
