CLUSTER_NAME ?= kind-stack-dev
NAMESPACE    ?= dev

# Load local environment config if it exists
-include .env.local

# Feature-focused workflow: List real services, rest are mocked
# All services always deploy - this determines mode (real or mock)
SERVICES_REAL ?=
SEED_DATABASE ?= false

# Helper: Determine service deployment mode
# Returns: "real" if service is in SERVICES_REAL, "mock" otherwise
service-mode = $(if $(findstring $(1),$(SERVICES_REAL)),real,mock)

.DEFAULT_GOAL := help

.PHONY: help kind-up kind-down deploy deploy-custom destroy status validate test-comms \
        ingress-install deploy-db destroy-db db-shell build-api deploy-api \
        pf-app pf-backend pf-db pf-api pf-all pf-stop

help:
	@echo ""
	@echo "kind-stack-dev Help"
	@echo "========================================"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Cluster Management:"
	@echo "  kind-up      Create KIND cluster"
	@echo "  kind-down    Delete KIND cluster"
	@echo ""
	@echo "Deployment:"
	@echo "  ingress-install  Install ingress-nginx controller"
	@echo "  deploy           Deploy podinfo-frontend + podinfo-backend"
	@echo "  deploy-custom    Deploy all services (set SERVICES_REAL for mode)"
	@echo "  destroy          Remove all Helm releases"
	@echo "  status           Show all pods across namespaces"
	@echo "  validate         Validate Helm charts"
	@echo "  test-comms       Test cross-service communication"
	@echo ""
	@echo "Database:"
	@echo "  deploy-db        Deploy PostgreSQL database (with migrations)"
	@echo "  destroy-db       Remove database"
	@echo "  db-shell         Connect to database shell"
	@echo ""
	@echo "API Service:"
	@echo "  build-api        Build and load API service image"
	@echo "  deploy-api       Deploy API service (requires database)"
	@echo ""
	@echo "Port Forwarding (optional fallback):"
	@echo "  pf-app       Port-forward podinfo-frontend (8080)"
	@echo "  pf-backend   Port-forward podinfo-backend (8082)"
	@echo "  pf-db        Port-forward postgres (5432)"
	@echo "  pf-api       Port-forward api service (8083)"
	@echo "  pf-all       Port-forward all services"
	@echo "  pf-stop      Stop all port-forwards"
	@echo ""
	@echo "Quick Start:"
	@echo "  make kind-up && make ingress-install && make deploy"
	@echo "  Services available at http://localhost:8000/[service-name]"
	@echo ""

kind-up:
	kind create cluster --name $(CLUSTER_NAME) --config kind/kind-config.yaml
	@echo "Waiting for cluster to be ready..."
	@kubectl wait --for=condition=Ready nodes --all --timeout=60s

kind-down:
	kind delete cluster --name $(CLUSTER_NAME) || true

# run validate before deploy (target: dependency)
deploy: validate
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install podinfo-frontend ./charts/podinfo -n $(NAMESPACE) --create-namespace --set backend.url=http://podinfo-backend:9898
	helm upgrade --install podinfo-backend ./charts/podinfo -n $(NAMESPACE) --create-namespace --set ingress.enabled=false

# Deploy services based on SERVICES_REAL configuration
# All services always deploy; SERVICES_REAL determines mode (real or mock)
deploy-custom: validate
	@echo "Deploying services..."
	@echo "  SERVICES_REAL=\"$(SERVICES_REAL)\""
	@echo ""
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
# Frontend
	@echo "→ Installing podinfo-frontend (mode=$(call service-mode,frontend))"
	helm upgrade --install podinfo-frontend ./charts/podinfo -n $(NAMESPACE) --create-namespace --set backend.url=http://podinfo-backend:9898
# Backend
	@echo "→ Installing podinfo-backend (mode=$(call service-mode,backend), internal only)"
	helm upgrade --install podinfo-backend ./charts/podinfo -n $(NAMESPACE) --create-namespace --set ingress.enabled=false
# Database (if API is real OR if seeding is enabled)
ifneq ($(or $(filter real,$(call service-mode,api)),$(filter true,$(SEED_DATABASE))),)
	@echo "→ Installing PostgreSQL database"
	helm upgrade --install postgres ./charts/postgres -n $(NAMESPACE) --create-namespace \
	  --set seed.enabled=$(SEED_DATABASE) --wait --timeout 3m
endif
# API service
	@echo "→ Installing API service (mode=$(call service-mode,api))"
	helm upgrade --install api ./charts/api -n $(NAMESPACE) --create-namespace --set mode=$(call service-mode,api)
	@echo ""
	@echo "✓ Deployment complete"

destroy:
	helm uninstall podinfo-frontend -n $(NAMESPACE) >/dev/null 2>&1 || true
	helm uninstall podinfo-backend -n $(NAMESPACE) >/dev/null 2>&1 || true
	helm uninstall postgres -n $(NAMESPACE) >/dev/null 2>&1 || true
	helm uninstall api -n $(NAMESPACE) >/dev/null 2>&1 || true

status:
	kubectl get pods -A

validate:
	@echo "Validating configuration"
	@echo "========================================"
	@helm lint ./charts/podinfo
	@helm lint ./charts/postgres
	@helm lint ./charts/api
	@echo "✓ Validation passed"

test-comms:
	@./scripts/test-service-communication.sh $(NAMESPACE)

ingress-install:
	@echo "Installing ingress-nginx..."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	@echo "Waiting for ingress-nginx to be ready..."
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=90s

# port forwarding helpers
pf-app:
	kubectl port-forward svc/podinfo-frontend -n $(NAMESPACE) 8080:9898

pf-backend:
	kubectl port-forward svc/podinfo-backend -n $(NAMESPACE) 8082:9898

pf-db:
	kubectl port-forward svc/postgres -n $(NAMESPACE) 5432:5432

pf-api:
	kubectl port-forward svc/api -n $(NAMESPACE) 8083:8080

pf-all:
	kubectl port-forward svc/podinfo-frontend -n $(NAMESPACE) 8080:9898 &
	kubectl port-forward svc/podinfo-backend -n $(NAMESPACE) 8082:9898 &
	wait

pf-stop:
	@echo "Stopping all port-forwards..."
	@pkill -f "kubectl port-forward" || true

# API Service management
build-api:
	@echo "Building API service image..."
	docker build -t api-service:latest ./services/api
	@echo "Loading image into KIND cluster..."
	kind load docker-image api-service:latest --name $(CLUSTER_NAME)
	@echo "✓ API service image built and loaded"

deploy-api:
	@echo "Deploying API service..."
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install api ./charts/api -n $(NAMESPACE) --create-namespace
	@echo "✓ API service deployed"
	@echo ""
	@echo "API endpoints available at:"
	@echo "  Ingress: http://localhost:8000/api/"
	@echo "  Port-forward: make pf-api (then http://localhost:8083)"

# Database management
deploy-db:
	@echo "Deploying PostgreSQL database..."
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install postgres ./charts/postgres -n $(NAMESPACE) --create-namespace --wait --timeout 3m
	@echo "✓ Database deployed successfully"
	@echo ""
	@echo "Database connection details:"
	@echo "  Host: postgres.$(NAMESPACE).svc.cluster.local"
	@echo "  Port: 5432"
	@echo "  Database: appdb"
	@echo "  User: appuser"
	@echo "  Password: devpassword"

destroy-db:
	@echo "→ Removing postgres database"
	helm uninstall postgres -n $(NAMESPACE) || true
	@echo "→ Cleaning up persistent volume claims"
	kubectl delete pvc postgres-data -n $(NAMESPACE) --ignore-not-found=true
	@echo "→ Waiting for resources to be deleted"
	@kubectl wait --for=delete pvc/postgres-data -n $(NAMESPACE) --timeout=30s 2>/dev/null || true
	@echo "✓ Database cleanup complete"

db-shell:
	@kubectl exec -it -n $(NAMESPACE) deployment/postgres -- psql -U appuser -d appdb
