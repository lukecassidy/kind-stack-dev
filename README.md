# kind-stack-dev

Local Kubernetes environment for multi-service development using **kind** and **Helm**.

Provides production-style patterns (Helm, Jobs, Ingress) with selective deployment—run only what you need, mock the rest. Fast iteration without the complexity of running everything locally.

**What's included:**
- 2 podinfo demo services (frontend + backend)
- PostgreSQL with automated migrations
- REST API (real or mock modes)
- Ingress for external access

---

## Quickstart

**Requirements:** kind, kubectl, helm, make

**Setup:**
```bash
make kind-up
make ingress-install
make deploy
```

Access services at `http://localhost:8000/podinfo-frontend`

**Test cross-service communication:**
```bash
make test-comms
```

---

## Selective Deployment

All services always deploy. Use `SERVICES_REAL` to control which run as real vs mocked:

```bash
SERVICES_REAL="api" make deploy-custom          # API dev with database
SERVICES_REAL="frontend,backend" make deploy-custom  # Integration testing
SERVICES_REAL="" make deploy-custom              # All mocked
```

Configure persistently in `.env.local` (copy from `.env.local.example`).

---

## Database

PostgreSQL with automated migrations. Deploys automatically when `SERVICES_REAL="api"`.

**Quick start:**
```bash
make deploy-db  # Standalone
make db-shell   # Connect
```

**Enable seeding:**
```bash
SERVICES_REAL="api" SEED_DATABASE=true make deploy-custom
```

**Schema:** `users` and `posts` tables. Migrations run via Helm hooks (ConfigMaps + Jobs).

**Credentials:** `postgres.dev.svc.cluster.local:5432`, db=`appdb`, user=`appuser`, password=`devpassword`

---

## API Service

REST API with CRUD operations. Single Helm chart supports two modes:
- **real**: Connects to PostgreSQL (full-stack)
- **mock**: WireMock stub (no database)

**Deploy:**
```bash
make build-api
make deploy-api                      # Real mode
SERVICES_REAL="" make deploy-custom  # Mock mode
```

**Access:**
- Ingress: `http://localhost:8000/api/`
- Internal: `http://api:8080`
- Port-forward: `make pf-api`

**Endpoints:** `/health`, `/users`, `/posts`, `/users/<id>`, `/posts/<id>`, `/users/<id>/posts`

---

## Common Commands

```bash
make help           # Show all commands
make status         # List pods
make destroy        # Remove all services
make validate       # Lint charts
make test-comms     # Test service communication
```

Ingress access: `http://localhost:8000/<service-name>`
