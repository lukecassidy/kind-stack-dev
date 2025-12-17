#!/bin/bash

NAMESPACE=${1:-dev}

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'
PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARNING="${ORANGE}⚠${NC}"
FAILED=0

# Test service-to-service communication
test_communication() {
    local from_pod=$1
    local to_service=$2
    local to_port=$3
    local test_name=$4
    local validation_string=$5
    local endpoint=${6:-/}

    local result=$(kubectl exec -n "$NAMESPACE" "$from_pod" -- wget -qO- "http://${to_service}:${to_port}${endpoint}" 2>&1)

    if echo "$result" | grep -q "$validation_string"; then
        echo -e "  ${PASS} ${test_name}"
        return 0
    else
        echo -e "  ${FAIL} ${test_name}"
        FAILED=1
        return 1
    fi
}

# Get pod names
get_pod_name() {
    local label=$1
    kubectl get pods -n "$NAMESPACE" -l "app=${label}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Main execution
echo "Service Communication Test"

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "  ${FAIL} Cluster: not reachable"
    exit 1
fi
echo -e "  ${PASS} Cluster: reachable"

# Get pod names
FRONTEND_POD=$(get_pod_name "podinfo-frontend")
BACKEND_POD=$(get_pod_name "podinfo-backend")

if [ -z "$FRONTEND_POD" ] || [ -z "$BACKEND_POD" ]; then
    echo -e "  ${FAIL} Pods: unable to find required pods"
    exit 1
fi
echo -e "  ${PASS} Pods: frontend and backend found"

# Service-to-service communication tests
test_communication "$FRONTEND_POD" "podinfo-backend" "9898" "Frontend → Backend" "podinfo-backend"
test_communication "$BACKEND_POD" "podinfo-frontend" "9898" "Backend → Frontend" "podinfo-frontend"

# Optional: API service tests (if deployed)
API_POD=$(get_pod_name "api")
if [ -n "$API_POD" ]; then
    echo -e "  ${PASS} API: found (testing public access)"
    # Test API via ingress (public route)
    # Wait briefly for ingress to update endpoints
    sleep 5
    api_response=$(curl -s http://localhost:8000/api/health 2>&1)
    if echo "$api_response" | grep -q "healthy"; then
        echo -e "  ${PASS} API ingress (http://localhost:8000/api/)"
    else
        echo -e "  ${FAIL} API ingress (http://localhost:8000/api/)"
        FAILED=1
    fi
else
    echo -e "  ${WARNING} API: not deployed (skipping tests)"
fi

# Final result
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}Communication Test Passed${NC}"
    exit 0
else
    echo -e "${RED}Communication Test Failed${NC}"
    exit 1
fi
