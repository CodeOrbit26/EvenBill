# EvenBill — Precision International Expense-Sharing Platform (v1.2)

**EvenBill** is a modern, mathematically exact international expense-sharing platform engineered with zero floating-point financial loss, bipartite debt simplification, and a local-first development stack requiring zero cloud accounts or AWS costs.

---

## 1. Monorepo Architecture

```
EvenBill/
├── docker-compose.yml        # Single-command developer stack (Postgres, MinIO, Mailpit, FastAPI)
├── .env.example              # Root developer environment configuration
├── backend/                  # Python 3.11+ / FastAPI / SQLAlchemy 2.0 Async
│   ├── app/
│   │   ├── adapters/         # Concrete adapters (LocalAuth, MinIO, Mailpit, ECB FX)
│   │   ├── api/v1/           # REST endpoints (auth, groups, expenses, settlements, sync)
│   │   ├── core/
│   │   │   ├── interfaces/   # Portable provider interfaces (IAuthProvider, IObjectStorage, etc.)
│   │   │   ├── money.py      # Exact precision money engine & penny conservation
│   │   │   └── simplification.py # Bipartite minimal cash-flow debt engine
│   │   ├── db/               # Async session & transaction management
│   │   ├── models/           # SQLAlchemy ORM models (User, Group, PendingParticipant, Expense)
│   │   └── services/         # Domain services: LedgerService, AuthService, ReceiptService
│   ├── tests/                # Automated Pytest suite (60 unit & integration tests)
│   ├── Dockerfile            # Container configuration with live hot-reload
│   └── requirements.txt
├── mobile/                   # Flutter 3.x / Dart cross-platform mobile client
│   ├── lib/
│   │   ├── core/             # Theme tokens, Riverpod providers, dynamic base URL config
│   │   ├── database/         # SQLite with Drift persistent local schema
│   │   ├── routing/          # GoRouter declarative navigation & deep links
│   │   └── main.dart         # Material 3 application shell
│   └── test/                 # Automated Flutter test suite (49 widget & journey tests)
└── docs/                     # Specifications and architectural blueprints
```

---

## 2. Core Engineering Principles

1. **Zero Floating-Point Financial Loss:** All calculations use Python `Decimal` and `NUMERIC(18, 4)` columns with integer minor-unit conversion.
2. **Hare-Niemeyer Remainder Allocation:** Odd penny divisions (e.g., $100.00 among 3 participants) allocate remaining cents deterministically, preserving the invariant:
   $$\sum \text{AllocatedShares} \equiv \text{TotalExpenseAmount}$$
3. **Bipartite Debt Simplification:** Reduces $O(N^2)$ pairwise debts to at most $N - 1$ minimal cash-flow transfers while strictly preserving each member's net position.
4. **Dedicated Guest Participant Model:** Non-account participants participate fully in group expenses, balances, and invitations, with zero-data-loss atomic claim merging.
5. **No Cloud Account Required:** 100% of the platform runs, authenticates, and tests locally using Docker Compose, MinIO, and Mailpit.

---

## 3. Quickstart: 1-Command Local Development

### Prerequisites
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
* [Flutter SDK 3.24+](https://flutter.dev/docs/get-started/install) (for mobile development).
* Python 3.11+ (optional, if running backend tests natively).

### Step 1: Start Local Docker Stack
From the project root:
```bash
docker compose up -d --build
```

**Services automatically started and healthy:**
* **API Backend:** `http://localhost:8000` (Interactive Swagger Docs: `http://localhost:8000/docs`)
* **PostgreSQL 16:** `localhost:5432` (User: `evenbill_user`, DB: `evenbill`)
* **MinIO Console (S3 Object Storage):** `http://localhost:9001` (User: `minioadmin`, Pass: `minioadmin`)
* **Mailpit (Mock SMTP Web Inbox):** `http://localhost:8025` (View verification and invitation emails)
* **Redis 7:** `localhost:6379`

### Step 2: Run Flutter Mobile Client

The mobile app automatically adapts its base URL to your development target:

```bash
cd mobile
flutter pub get
```

#### Run on iOS Simulator (macOS):
```bash
flutter run
```
*API connects to `http://127.0.0.1:8000/api/v1`*

#### Run on Android Emulator:
```bash
flutter run
```
*API connects automatically to `http://10.0.2.2:8000/api/v1`*

#### Run on Physical iPhone or Android over Local Wi-Fi:
Find your machine's local IP address (e.g. `192.168.1.150` via `ifconfig` or `ipconfig`) and pass it via `--dart-define`:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.150:8000/api/v1
```

---

## 4. Automated Test Verification

### Backend Pytest Suite (60 tests)
```bash
cd backend
source .venv/bin/activate
pytest -v
```

### Mobile Flutter Test Suite (49 tests)
```bash
cd mobile
flutter test
```
