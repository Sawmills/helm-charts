#!/bin/zsh
#
# Sibling Fallback Test Suite (SAW-6360)
# ======================================
# Tests the 3-tier HAProxy fallback routing:
#   Tier 1: Local otel collector (same pod)
#   Tier 2: Sibling LB pods (via headless service DNS)
#   Tier 3: External vendor fallback (e.g., Datadog)
#
# Prerequisites:
#   - kubectl configured for the target cluster (with valid credentials)
#   - curl, awk available locally
#
# Usage: ./test-sibling-fallback.sh

set -uo pipefail

# --- Configuration ---
STATS_PORT=28406
TRAFFIC_PORT=28000
NUM_REQUESTS=5
HAPROXY_USER="admin"
HAPROXY_PASS="admin"
STATS_BASE="http://localhost:${STATS_PORT}"
TRAFFIC_URL="http://localhost:${TRAFFIC_PORT}"
BACKEND="logs_http_10000"
DIRECT_BACKEND="logs_http_10000_direct"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
ADMIN_ENABLED=false
LB_POD=""
PF_PID=""
NAMESPACE=""

# --- Helper Functions ---

print_header() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo "---------------------------------------------"
}

print_pass() {
    echo -e "  ${GREEN}PASS${NC} - $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

print_fail() {
    echo -e "  ${RED}FAIL${NC} - $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_info() {
    echo -e "  ${BLUE}INFO${NC} $1"
}

fetch_stats_csv() {
    curl -s -u "${HAPROXY_USER}:${HAPROXY_PASS}" "${STATS_BASE}/;csv" 2>/dev/null
}

get_sessions() {
    local backend="$1"
    local server="$2"
    local result
    result=$(fetch_stats_csv | { grep "^${backend},${server}," || true; } | awk -F, '{print $8}')
    echo "${result:-0}"
}

get_status() {
    local backend="$1"
    local server="$2"
    fetch_stats_csv | { grep "^${backend},${server}," || true; } | awk -F, '{print $18}'
}

get_sibling_total_sessions() {
    local backend="$1"
    fetch_stats_csv | { grep "^${backend},sibling" || true; } | awk -F, '{s+=$8} END {print s+0}'
}

get_sibling_up_count() {
    local backend="$1"
    local count
    count=$(fetch_stats_csv | { grep "^${backend},sibling" || true; } | { grep -c ",UP," || true; })
    echo "${count:-0}"
}

send_requests() {
    local count="$1"
    local port="$2"
    local header="${3:-}"
    local label="${4:-Request}"
    local url="http://localhost:${port}/api/v2/logs"
    local all_ok=true
    local code=""
    local curl_args=()

    for i in $(seq 1 "$count"); do
        curl_args=(-s -o /dev/null -w '%{http_code}' -X POST "$url"
            -H "Content-Type: application/json"
            -d "[{\"message\":\"test-${label}-${i}\",\"ddsource\":\"sibling-fallback-test\",\"hostname\":\"test-runner\"}]")
        if [ -n "$header" ]; then
            curl_args+=(-H "$header")
        fi
        code=$(curl "${curl_args[@]}" 2>/dev/null)
        echo "  ${label} ${i}: HTTP ${code}"
        if [[ "$code" != "2"* ]]; then
            all_ok=false
        fi
    done
    $all_ok
}

admin_action() {
    local backend="$1"
    local server="$2"
    local action="$3"
    curl -s -o /dev/null -u "${HAPROXY_USER}:${HAPROXY_PASS}" -X POST "${STATS_BASE}/" \
        -d "b=${backend}&s=${server}&action=${action}" 2>/dev/null
}

start_port_forward() {
    local pod="$1"
    shift
    local ports=("$@")
    # Kill any existing port-forwards on our ports
    pkill -f "port-forward.*${STATS_PORT}" 2>/dev/null || true
    pkill -f "port-forward.*${TRAFFIC_PORT}" 2>/dev/null || true
    sleep 1
    kubectl port-forward -n "$NAMESPACE" "$pod" "${ports[@]}" >/dev/null 2>&1 &
    PF_PID=$!
    # Wait for port-forward to be ready by testing connectivity
    local ready=false
    for i in $(seq 1 15); do
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${STATS_PORT}/" 2>/dev/null || echo "000")
        if [ "$http_code" != "000" ]; then
            ready=true
            break
        fi
        sleep 2
    done
    if [ "$ready" != "true" ]; then
        echo -e "${RED}ERROR: Port-forward failed to start${NC}"
        exit 1
    fi
}

stop_port_forward() {
    if [ -n "$PF_PID" ]; then
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
        PF_PID=""
        sleep 1
    fi
}

enable_admin_mode() {
    local pod="$1"
    kubectl exec -n "$NAMESPACE" "$pod" -c haproxy -- bash -c '
        CONFIG=/usr/local/etc/haproxy/haproxy.cfg
        if grep -q "stats admin" "$CONFIG" 2>/dev/null; then
            echo "ALREADY_ENABLED"
            exit 0
        fi
        cp "$CONFIG" /tmp/haproxy-admin.cfg
        sed -i "/stats auth admin:admin/a\\  stats admin if TRUE" /tmp/haproxy-admin.cfg
        WORKER_PID=""
        for pid in /proc/[0-9]*; do
            p=$(basename "$pid")
            name=$(cat "$pid/comm" 2>/dev/null)
            ppid=$(awk "/^PPid:/{print \$2}" "$pid/status" 2>/dev/null)
            if [ "$name" = "haproxy" ] && [ "$ppid" = "1" ]; then
                WORKER_PID="$p"
            fi
        done
        if [ -z "$WORKER_PID" ]; then
            WORKER_PID=1
        fi
        haproxy -D -f /tmp/haproxy-admin.cfg -sf "$WORKER_PID" 2>&1
        echo "RELOAD_OK"
    ' 2>/dev/null
}

restore_haproxy() {
    local pod="$1"
    kubectl exec -n "$NAMESPACE" "$pod" -c haproxy -- bash -c '
        CONFIG=/usr/local/etc/haproxy/haproxy.cfg
        WORKER_PID=""
        for pid in /proc/[0-9]*; do
            p=$(basename "$pid")
            name=$(cat "$pid/comm" 2>/dev/null)
            ppid=$(awk "/^PPid:/{print \$2}" "$pid/status" 2>/dev/null)
            if [ "$name" = "haproxy" ] && [ "$ppid" = "1" ]; then
                WORKER_PID="$p"
            fi
        done
        if [ -z "$WORKER_PID" ]; then
            WORKER_PID=1
        fi
        haproxy -D -f "$CONFIG" -sf "$WORKER_PID" 2>&1
        echo "RESTORE_OK"
    ' 2>/dev/null
}

cleanup() {
    echo ""
    echo -e "${BOLD}Cleanup${NC}"
    echo "============================================="
    stop_port_forward

    if [ "$ADMIN_ENABLED" = true ] && [ -n "$LB_POD" ] && [ -n "$NAMESPACE" ]; then
        echo "  Restoring original HAProxy config in pod..."
        restore_haproxy "$LB_POD" | grep -v "^$"
        echo -e "  ${GREEN}Cleanup complete${NC}"
    else
        echo "  No cleanup needed"
    fi
}

trap cleanup EXIT

# =============================================
#   NAMESPACE SELECTION
# =============================================

echo ""
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD}  SAW-6360: Sibling Fallback Test Suite${NC}"
echo -e "${BOLD}=============================================${NC}"
echo ""

# Prompt for namespace
echo -e "  Available contexts:"
echo -e "    Current: $(kubectl config current-context 2>/dev/null || echo 'none')"
echo ""

if [ -n "${1:-}" ]; then
    NAMESPACE="$1"
    echo -e "  Using namespace: ${YELLOW}${NAMESPACE}${NC} (from argument)"
else
    read -rp "  Enter namespace: " NAMESPACE
    if [ -z "$NAMESPACE" ]; then
        echo -e "${RED}ERROR: Namespace is required${NC}"
        exit 1
    fi
fi

echo ""
echo -e "  Namespace: ${YELLOW}${NAMESPACE}${NC}"
echo -e "  Date:      $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --- Verify prerequisites ---
print_header "SETUP: Verifying prerequisites"

if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot access namespace '${NAMESPACE}'.${NC}"
    echo ""
    echo "  Check your kubectl context and AWS credentials."
    exit 1
fi
print_info "kubectl connectivity OK"

# Find LB pods (pick a Running pod, prefer newest)
LB_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers --sort-by=.metadata.creationTimestamp 2>/dev/null | grep "collector-lb" | grep "Running" | tail -1 | awk '{print $1}')
if [ -z "$LB_POD" ]; then
    echo -e "${RED}ERROR: No collector-lb pods found in namespace '${NAMESPACE}'${NC}"
    exit 1
fi
print_info "Using LB pod: ${LB_POD}"

# Show pod layout
echo ""
echo "  Pods:"
kubectl get pods -n "$NAMESPACE" -o wide --no-headers 2>/dev/null | grep "collector-lb" | \
    awk '{printf "    %-55s %-10s %-5s %s\n", $1, $3, $4, $6}'

LB_COUNT=$(kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -c "collector-lb.*Running" || echo "0")
echo ""
print_info "LB replicas: ${LB_COUNT}"

# --- Start port-forward FIRST (must be before hot-reload) ---
print_header "SETUP: Starting port-forward"
start_port_forward "$LB_POD" "${STATS_PORT}:8406" "${TRAFFIC_PORT}:10000"
print_info "Port-forward active (stats=:${STATS_PORT}, traffic=:${TRAFFIC_PORT})"

# Verify HAProxy is responsive before hot-reload
OTEL_STATUS=""
for i in $(seq 1 10); do
    # Try the stats CSV endpoint directly
    CSV_RAW=$(fetch_stats_csv 2>&1 || true)
    OTEL_LINE=$(echo "$CSV_RAW" | { grep "^${BACKEND},otel," || true; })
    OTEL_STATUS=$(echo "$OTEL_LINE" | awk -F, '{print $18}')
    if [ -n "$OTEL_STATUS" ]; then
        break
    fi
    echo "  Waiting for HAProxy to respond... (attempt $i/10)"
    sleep 2
done
if [ -z "$OTEL_STATUS" ]; then
    echo -e "${RED}ERROR: Cannot reach HAProxy stats${NC}"
    exit 1
fi
print_info "HAProxy responding, otel status: ${OTEL_STATUS}"

# --- Enable HAProxy admin mode via hot-reload (port-forward must already be active) ---
print_header "SETUP: Enabling HAProxy admin mode (in-pod hot-reload)"

RESULT=$(enable_admin_mode "$LB_POD")
if echo "$RESULT" | grep -q "RELOAD_OK\|ALREADY_ENABLED"; then
    ADMIN_ENABLED=true
    print_info "Admin mode enabled via HAProxy hot-reload (no pod restart needed)"
else
    echo -e "${RED}ERROR: Failed to enable admin mode${NC}"
    echo "  $RESULT"
    exit 1
fi
sleep 3

# Verify admin works
OTEL_STATUS=$(get_status "$BACKEND" "otel")
print_info "HAProxy responding after reload, otel status: ${OTEL_STATUS}"

# Wait for sibling DNS resolution
echo "  Waiting for sibling DNS resolution..."
for i in $(seq 1 20); do
    UP=$(get_sibling_up_count "$BACKEND")
    if [ "$UP" -ge 2 ]; then
        break
    fi
    sleep 2
done
print_info "Siblings resolved: $(get_sibling_up_count "$BACKEND") UP"

# Show initial backend state
echo ""
echo "  HAProxy backend state (${BACKEND}):"
fetch_stats_csv | grep "^${BACKEND}," | \
    awk -F, '{printf "    %-12s status=%-20s sessions=%s\n", $2, $18, $8}'

# =============================================
#   TEST 1: Normal Traffic Routing
# =============================================

print_header "TEST 1: Normal Traffic Routing"
echo -e "  ${BLUE}Expected:${NC} All requests route to local otel (Tier 1)"
echo ""

BEFORE_OTEL=$(get_sessions "$BACKEND" "otel")
BEFORE_SIBLING=$(get_sibling_total_sessions "$BACKEND")

send_requests "$NUM_REQUESTS" "$TRAFFIC_PORT" "" "Request"

AFTER_OTEL=$(get_sessions "$BACKEND" "otel")
AFTER_SIBLING=$(get_sibling_total_sessions "$BACKEND")

OTEL_DELTA=$((AFTER_OTEL - BEFORE_OTEL))
SIBLING_DELTA=$((AFTER_SIBLING - BEFORE_SIBLING))

echo ""
echo "  otel sessions:    ${BEFORE_OTEL} -> ${AFTER_OTEL}  (+${OTEL_DELTA})"
echo "  sibling sessions: ${BEFORE_SIBLING} -> ${AFTER_SIBLING}  (+${SIBLING_DELTA})"

if [ "$OTEL_DELTA" -eq "$NUM_REQUESTS" ] && [ "$SIBLING_DELTA" -eq 0 ]; then
    print_pass "All ${NUM_REQUESTS} requests routed to local otel"
else
    print_fail "Expected ${NUM_REQUESTS} to otel, got ${OTEL_DELTA}. Expected 0 to siblings, got ${SIBLING_DELTA}"
fi

# =============================================
#   TEST 2: Loop Prevention (X-Sibling-Hop)
# =============================================

print_header "TEST 2: Loop Prevention (X-Sibling-Hop header)"
echo -e "  ${BLUE}Expected:${NC} Requests with X-Sibling-Hop bypass sibling tier, go to _direct backend"
echo ""

BEFORE_DIRECT=$(get_sessions "$DIRECT_BACKEND" "otel")
BEFORE_MAIN=$(get_sessions "$BACKEND" "BACKEND")

send_requests 3 "$TRAFFIC_PORT" "X-Sibling-Hop: 1" "Hop-Request"

AFTER_DIRECT=$(get_sessions "$DIRECT_BACKEND" "otel")
AFTER_MAIN=$(get_sessions "$BACKEND" "BACKEND")

DIRECT_DELTA=$((AFTER_DIRECT - BEFORE_DIRECT))
MAIN_DELTA=$((AFTER_MAIN - BEFORE_MAIN))

echo ""
echo "  _direct/otel sessions:  ${BEFORE_DIRECT} -> ${AFTER_DIRECT}  (+${DIRECT_DELTA})"
echo "  main backend sessions:  ${BEFORE_MAIN} -> ${AFTER_MAIN}  (+${MAIN_DELTA})"

if [ "$DIRECT_DELTA" -eq 3 ] && [ "$MAIN_DELTA" -eq 0 ]; then
    print_pass "Hop requests correctly routed to _direct backend (loop prevention active)"
else
    print_fail "Expected 3 to _direct, got ${DIRECT_DELTA}. Expected 0 to main, got ${MAIN_DELTA}"
fi

# =============================================
#   TEST 3: Sibling Failover
# =============================================

print_header "TEST 3: Sibling Failover (local otel DOWN)"
echo -e "  ${BLUE}Expected:${NC} When local otel is in maintenance, traffic goes to sibling LB pods (Tier 2)"
echo ""

SIBLING_UP=$(get_sibling_up_count "$BACKEND")
print_info "Sibling servers UP: ${SIBLING_UP}"

echo -e "  ${YELLOW}Disabling local otel via HAProxy admin...${NC}"
admin_action "$BACKEND" "otel" "maint"
sleep 1

OTEL_STATUS=$(get_status "$BACKEND" "otel")
echo "  otel status: ${OTEL_STATUS}"

if [[ "$OTEL_STATUS" != *"MAINT"* ]]; then
    print_fail "Failed to put otel in MAINT mode (status: ${OTEL_STATUS})"
    admin_action "$BACKEND" "otel" "ready"
else
    echo ""
    BEFORE_OTEL=$(get_sessions "$BACKEND" "otel")
    BEFORE_SIBLING=$(get_sibling_total_sessions "$BACKEND")

    send_requests "$NUM_REQUESTS" "$TRAFFIC_PORT" "" "Failover"

    AFTER_OTEL=$(get_sessions "$BACKEND" "otel")
    AFTER_SIBLING=$(get_sibling_total_sessions "$BACKEND")

    OTEL_DELTA=$((AFTER_OTEL - BEFORE_OTEL))
    SIBLING_DELTA=$((AFTER_SIBLING - BEFORE_SIBLING))

    echo ""
    echo "  otel sessions:    ${BEFORE_OTEL} -> ${AFTER_OTEL}  (+${OTEL_DELTA})"
    echo "  sibling sessions: ${BEFORE_SIBLING} -> ${AFTER_SIBLING}  (+${SIBLING_DELTA})"

    if [ "$SIBLING_DELTA" -eq "$NUM_REQUESTS" ] && [ "$OTEL_DELTA" -eq 0 ]; then
        print_pass "All ${NUM_REQUESTS} requests routed to sibling LB pods"
    else
        print_fail "Expected ${NUM_REQUESTS} to siblings, got ${SIBLING_DELTA}. Expected 0 to otel, got ${OTEL_DELTA}"
    fi

    # Show per-sibling distribution
    echo ""
    echo "  Per-sibling session distribution:"
    fetch_stats_csv | grep "^${BACKEND},sibling" | grep ",UP," | \
        awk -F, '{printf "    %-12s sessions=%s\n", $2, $8}'
fi

# =============================================
#   TEST 4: Recovery After Failover
# =============================================

print_header "TEST 4: Recovery After Re-enabling Local Otel"
echo -e "  ${BLUE}Expected:${NC} After otel is restored, traffic returns to local (Tier 1)"
echo ""

echo -e "  ${YELLOW}Re-enabling local otel...${NC}"
admin_action "$BACKEND" "otel" "ready"
sleep 3

OTEL_STATUS=$(get_status "$BACKEND" "otel")
echo "  otel status: ${OTEL_STATUS}"
echo ""

BEFORE_OTEL=$(get_sessions "$BACKEND" "otel")
BEFORE_SIBLING=$(get_sibling_total_sessions "$BACKEND")

send_requests "$NUM_REQUESTS" "$TRAFFIC_PORT" "" "Recovery"

AFTER_OTEL=$(get_sessions "$BACKEND" "otel")
AFTER_SIBLING=$(get_sibling_total_sessions "$BACKEND")

OTEL_DELTA=$((AFTER_OTEL - BEFORE_OTEL))
SIBLING_DELTA=$((AFTER_SIBLING - BEFORE_SIBLING))

echo ""
echo "  otel sessions:    ${BEFORE_OTEL} -> ${AFTER_OTEL}  (+${OTEL_DELTA})"
echo "  sibling sessions: ${BEFORE_SIBLING} -> ${AFTER_SIBLING}  (+${SIBLING_DELTA})"

if [ "$OTEL_DELTA" -eq "$NUM_REQUESTS" ] && [ "$SIBLING_DELTA" -eq 0 ]; then
    print_pass "Traffic returned to local otel after recovery"
else
    print_fail "Expected ${NUM_REQUESTS} to otel, got ${OTEL_DELTA}. Expected 0 to siblings, got ${SIBLING_DELTA}"
fi

# =============================================
#   TEST 5: Non-Fallback Port Isolation
# =============================================

print_header "TEST 5: Non-Fallback Port Isolation (port 10001)"
echo -e "  ${BLUE}Expected:${NC} Ports without fallback_endpoint have no sibling tier"
echo ""

HAS_SIBLINGS=$(fetch_stats_csv | { grep -c "^logs_http_10001,sibling" || true; })
echo "  logs_http_10001 backend servers:"
fetch_stats_csv | grep "^logs_http_10001," | \
    awk -F, '{printf "    %-12s status=%s\n", $2, $18}'

if [ "$HAS_SIBLINGS" -eq 0 ]; then
    print_pass "Port 10001 has no sibling tier (isolation confirmed)"
else
    print_fail "Port 10001 unexpectedly has ${HAS_SIBLINGS} sibling entries"
fi

# =============================================
#   TEST 6: DNS Resolution Verification
# =============================================

print_header "TEST 6: DNS Resolution Verification"
echo -e "  ${BLUE}Expected:${NC} Headless service resolves to LB pod IPs"
echo ""

echo "  LB Pod IPs:"
kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null | grep "collector-lb" | \
    awk '{printf "    %-55s %s\n", $1, $6}'

SIBLING_UP=$(get_sibling_up_count "$BACKEND")
echo ""
echo "  HAProxy sibling resolution: ${SIBLING_UP} UP out of ${LB_COUNT} LB pods"

if [ "$SIBLING_UP" -ge 2 ]; then
    print_pass "DNS resolution working (${SIBLING_UP} siblings resolved)"
else
    print_fail "Expected at least 2 siblings UP, got ${SIBLING_UP}"
fi

# =============================================
#   TEST 7: HAProxy Configuration Verification
# =============================================

print_header "TEST 7: HAProxy Configuration Verification"
echo -e "  ${BLUE}Expected:${NC} Config has 3-tier structure with loop prevention"
echo ""

CONFIG=$(kubectl get configmap -n "$NAMESPACE" sawmills-collector-haproxy-config \
    -o jsonpath='{.data.haproxy\.cfg}' 2>/dev/null)

checks_passed=0
total_checks=6

# Check resolvers block
if echo "$CONFIG" | grep -q "^resolvers k8s"; then
    print_info "resolvers k8s block present"
    checks_passed=$((checks_passed + 1))
else
    print_fail "Missing resolvers k8s block"
fi

# Check frontend loop detection
if echo "$CONFIG" | grep -q "acl is_sibling_hop"; then
    print_info "X-Sibling-Hop ACL present in frontend"
    checks_passed=$((checks_passed + 1))
else
    print_fail "Missing X-Sibling-Hop ACL"
fi

# Check backend structure
if echo "$CONFIG" | grep -q "server-template sibling"; then
    MAX_SERVERS=$(echo "$CONFIG" | grep "server-template sibling" | awk '{print $3}')
    print_info "server-template: max ${MAX_SERVERS} siblings via headless DNS"
    checks_passed=$((checks_passed + 1))
else
    print_fail "Missing server-template sibling directive"
fi

# Check X-Sibling-Hop header injection
if echo "$CONFIG" | grep -q "http-request set-header X-Sibling-Hop"; then
    print_info "X-Sibling-Hop header injection configured"
    checks_passed=$((checks_passed + 1))
else
    print_fail "Missing X-Sibling-Hop header injection"
fi

# Check direct backend
if echo "$CONFIG" | grep -q "backend.*_direct"; then
    print_info "_direct backend present for loop prevention"
    checks_passed=$((checks_passed + 1))
else
    print_fail "Missing _direct backend"
fi

# Check sibling health check port
if echo "$CONFIG" | grep -q "check port 13135"; then
    print_info "Sibling health check on port 13135"
    checks_passed=$((checks_passed + 1))
else
    print_fail "Missing sibling health check port"
fi

if [ "$checks_passed" -eq "$total_checks" ]; then
    print_pass "HAProxy config has all ${total_checks} required 3-tier directives"
else
    print_fail "Only ${checks_passed}/${total_checks} config checks passed"
fi

# =============================================
#   SUMMARY
# =============================================

echo ""
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD}  TEST SUMMARY${NC}"
echo -e "${BOLD}=============================================${NC}"
echo ""
echo "  Namespace:  ${NAMESPACE}"
echo "  LB Pod:     ${LB_POD}"
echo "  Chart:      $(kubectl get configmap -n "$NAMESPACE" sawmills-collector-haproxy-config -o jsonpath='{.metadata.labels.helm\.sh/chart}' 2>/dev/null)"
echo ""
echo -e "  ${GREEN}Passed: ${PASS_COUNT}${NC}"
echo -e "  ${RED}Failed: ${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}${BOLD}SOME TESTS FAILED${NC}"
fi

echo ""
echo -e "${BOLD}Architecture verified:${NC}"
echo "  Frontend (port 10000)"
echo "    |-- X-Sibling-Hop header? --> _direct backend (local otel + vendor fallback)"
echo "    |-- default               --> main backend:"
echo "        |-- Tier 1: Local otel (\$MY_POD_IP:10518)"
echo "        |-- Tier 2: Sibling LB pods (headless DNS, backup)"
echo "        |-- Tier 3: Vendor fallback (SSL, backup)"
echo ""

exit "$FAIL_COUNT"
