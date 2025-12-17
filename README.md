# kind-stack-dev

A local, production-shaped Kubernetes environment for developing and testing multiple services using **kind** and **Helm**.

This repository focuses on **application and service development**.

---

## Motivation

Developing multiple services locally can get messy pretty quickly:

- too many dependencies to run everything
- local setups drifting away from production
- lots of undocumented steps and tribal knowledge
- more time spent wiring things together than actually building features

**kind-stack-dev** aims to make this easier with a **simple, repeatable local Kubernetes setup** that mirrors production where it matters, while staying fast and flexible for daily development.

---

## What this does

Provides a fast, repeatable local Kubernetes environment that:
- Supports multi-service development with selective deployment (run only what you need)
- Uses production-style patterns (Kubernetes, Helm, Jobs, Ingress)
- Handles missing dependencies with local stubs

The focus is good feedback, clarity, and iteration speed—not perfect production mirroring.

---

## What's in this repo

- Minimal kind-based Kubernetes cluster
- Helm charts for application services (currently: 2 podinfo instances)
- PostgreSQL database with automated migrations and optional seed data
- REST API service connected to PostgreSQL (demonstrating full-stack integration)
- Basic tooling to get things running quickly

Demo environment includes:
- **podinfo-frontend**: Frontend service accessible via ingress at `/podinfo-frontend`
- **podinfo-backend**: Backend service (internal only, no ingress)
- **postgres**: PostgreSQL database (optional, disabled by default, internal only)
- **api**: REST API service with CRUD operations (optional, requires database)
- **ingress-nginx**: Path-based routing for public services

**Public services** (accessible via ingress):
- Frontend: `http://localhost:8000/podinfo-frontend`
- API: `http://localhost:8000/api` (when deployed)

**Internal services** (accessible only within cluster):
- Backend: `http://podinfo-backend:9898`
- Database: `http://postgres:5432`

Port-forward fallback for internal services:
- Backend: `make pf-backend` (then `localhost:8082`)
- Database: `make pf-db` (then `localhost:5432`)

---

## Quickstart

### Requirements

- kind
- kubectl
- helm
- make

### Setup

```bash
make kind-up
make ingress-install
make deploy
```

Services are now accessible via ingress at `http://localhost:8000/[service-name]`.

**Deploy with selective real/mock modes:**
```bash
# Deploy all services (all mocked by default)
make deploy-custom

# Deploy with API as real (includes database)
SERVICES_REAL="api" make deploy-custom

# Deploy multiple services as real
SERVICES_REAL="frontend,backend,api" make deploy-custom
```

For local development without ingress:
```bash
make pf-all  # Port-forward all services
```

### Test

**Via Ingress (public services):**
```bash
# podinfo-frontend service
curl -i http://localhost:8000/podinfo-frontend/
```

**Via Port-Forward (internal services):**
```bash
# Backend (internal only)
make pf-backend
curl -i http://localhost:8082/
```

### Validate Cross-Service Communication

Test that services can communicate with each other within the cluster:

```bash
make test-comms
```

This validates:
- Frontend ↔ Backend internal communication (using Kubernetes service DNS)

The test script runs `kubectl exec` commands from within pods to test internal service-to-service communication, showing that:
- Frontend can reach backend at `http://podinfo-backend:9898`
- Backend can reach frontend at `http://podinfo-frontend:9898`
- Services communicate internally without requiring ingress exposure

---

## Selective Service Deployment

All services always deploy - `SERVICES_REAL` determines which services run as real vs mocked implementations.

**Common patterns:**

```bash
# API development with database
SERVICES_REAL="api" make deploy-custom

# Frontend work, backends mocked
SERVICES_REAL="frontend" make deploy-custom

# Multi-service integration testing
SERVICES_REAL="frontend,backend,api" make deploy-custom

# All services mocked (testing with stubs)
SERVICES_REAL="" make deploy-custom
```

**Persistent configuration:** Copy `.env.local.example` to `.env.local` and set `SERVICES_REAL`.

### Cleanup

```bash
make destroy  # Remove all services
```

---

## Database

Optional PostgreSQL database for local development with automated schema migrations and optional seed data.

### Quick Start

Deploy the database standalone:
```bash
make deploy-db
```

Includes:
- Automated schema migrations (via Helm hooks)
- Connection details displayed after deployment
- Persistent storage (1Gi PVC)

### Using with deploy-custom

The database deploys automatically when API is set to real mode. Enable seeding in your `.env.local`:
```bash
SERVICES_REAL="api"
SEED_DATABASE=true  # Optional: load sample data
```

Or via command-line:
```bash
SERVICES_REAL="api" SEED_DATABASE=true make deploy-custom
```

### Connection Details

**From within the cluster:**
```
Host: postgres.dev.svc.cluster.local
Port: 5432
Database: appdb
User: appuser
Password: devpassword
```

**From your local machine (via port-forward):**
```bash
make pf-db
psql -h localhost -p 5432 -U appuser -d appdb
```

Or use the db-shell helper:
```bash
make db-shell
```

### Database Schema

The migrations create a simple demo schema:
- `users` table (id, username, email, created_at)
- `posts` table (id, user_id, title, content, status, created_at)

When `SEED_DATABASE=true`, sample data is automatically loaded with 3 users and 5 posts.

### Migration System

Migrations run automatically via Helm hooks during install/upgrade:
- Migration scripts stored in ConfigMaps
- Jobs run after database deployment
- Seed job runs after migrations (if enabled)

To view migration logs:
```bash
kubectl logs -n dev job/postgres-migration-1
```

### Cleanup

Remove the database and its data:
```bash
make destroy-db
```

This removes both the Helm release and the PersistentVolumeClaim.

---

## API Service

REST API service with CRUD operations for users and posts. **Single Helm chart with mode parameter** - no separate charts needed!

### Deployment Modes

Two modes available via the `mode` parameter:
- **mode=real**: Connects to PostgreSQL database (full-stack integration)
- **mode=mock**: WireMock-based stub with static responses (no database needed)

### Quick Start

**Option 1: Real API (with Database)**

First, ensure the database is deployed:
```bash
make deploy-db
```

Build and deploy the API service:
```bash
make build-api
make deploy-api
```

**Option 2: Mock API (no Database)**

Deploy all services with API in mock mode (default when SERVICES_REAL is empty):
```bash
make deploy-custom
```

Or configure in `.env.local`:
```bash
SERVICES_REAL=""  # API deploys as mock
```

**Direct Helm usage** (bypassing Makefile):
```bash
# Deploy in real mode
helm upgrade --install api ./charts/api -n dev --set mode=real

# Deploy in mock mode
helm upgrade --install api ./charts/api -n dev --set mode=mock
```

**Both modes** are available at:
- **Within cluster**: `http://api:8080`
- **Via ingress**: `http://localhost:8000/api/` (requires ingress-nginx)
- **Via port-forward**: `make pf-api` then `http://localhost:8083`

### API Endpoints

Available endpoints:

**Service Info**
- `GET /` - API information and available endpoints
- `GET /health` - Health check (includes database connection status)

**Users**
- `GET /users` - List all users
- `GET /users/<id>` - Get a specific user
- `POST /users` - Create a new user (requires: username, email)

**Posts**
- `GET /posts` - List all posts (with author information)
- `GET /posts/<id>` - Get a specific post
- `POST /posts` - Create a new post (requires: user_id, title; optional: content, status)
- `GET /users/<id>/posts` - Get all posts by a specific user

### Testing the API

**Via ingress** (both real and mock):
```bash
curl http://localhost:8000/api/health
curl http://localhost:8000/api/users
curl http://localhost:8000/api/posts
```

**From within the cluster** (using any pod with curl):
```bash
# List all users
kubectl exec -n dev deployment/podinfo-frontend -- curl http://api:8080/users

# Get a specific user
kubectl exec -n dev deployment/podinfo-frontend -- curl http://api:8080/users/1

# List all posts
kubectl exec -n dev deployment/podinfo-frontend -- curl http://api:8080/posts

# Create a new user
kubectl exec -n dev deployment/podinfo-frontend -- curl -X POST http://api:8080/users \
  -H "Content-Type: application/json" \
  -d '{"username":"newuser","email":"new@example.com"}'
```

**Via port-forward**:
```bash
make pf-api

# Then in another terminal:
curl http://localhost:8083/health
curl http://localhost:8083/users
```

### Real vs Mock API

**Real API**:
- Connects to PostgreSQL database
- Dynamic data (reads/writes persist)
- Requires database deployment
- Useful for testing full-stack integration

**Mock API**:
- Static WireMock responses
- No database needed
- Fast startup
- Useful for frontend development or testing without database overhead
- Returns predefined data (3 users, 2 posts)

### Using with deploy-custom

Configure the API mode in your `.env.local`:

**Real API**:
```bash
SERVICES_REAL="api"
SEED_DATABASE=true  # Optional
```

**Mock API** (default):
```bash
SERVICES_REAL=""
# Database not deployed
```

Then deploy:
```bash
make deploy-custom
```

Or override on the command line:
```bash
SERVICES_REAL="api" make deploy-custom
SERVICES_REAL="api" SEED_DATABASE=true make deploy-custom
```

---

## Repository structure

```text
kind/
  kind-config.yaml        # kind cluster configuration

k8s/
  namespace.yaml          # dev namespace

charts/
  podinfo/                # podinfo demo service (prebuilt image)
  postgres/               # PostgreSQL database with migrations
  api/                    # REST API service (supports mode: real or mock)

services/
  api/                    # API service source code and Dockerfile

scripts/
  test-service-communication.sh  # validates cross-service comms

Makefile                  # common local workflows
```

---

## Direction

This repository evolves based on actual needs that come up during use.

There's no formal roadmap. Features are added gradually as they prove useful in practice, with a preference for small, clear changes that make local development easier.
