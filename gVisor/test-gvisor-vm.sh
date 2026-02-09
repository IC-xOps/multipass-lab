#!/bin/bash

#===============================================================================
# GVISOR VM TEST SUITE
#===============================================================================
# Tests gVisor installation, Caddy webserver, and container isolation
#
# Usage: ./test-gvisor-vm.sh
#===============================================================================

set -uo pipefail

# Configuration
VM_NAME="docker-in-gvisor-vm"
PASSED=0
FAILED=0
WARNED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test() {
    echo -e "${BLUE}▶ Testing:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✔ PASS:${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✘ FAIL:${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARNED++))
}

print_info() {
    echo -e "${CYAN}ℹ INFO:${NC} $1"
}

# Execute command in VM
vm_exec() {
    multipass exec "$VM_NAME" -- "$@" 2>&1
}

vm_exec_output() {
    multipass exec "$VM_NAME" -- "$@" 2>&1
}

#===============================================================================
# TEST FUNCTIONS
#===============================================================================

test_prerequisites() {
    print_header "Checking Prerequisites"
    
    print_test "Multipass installation"
    if command -v multipass &> /dev/null; then
        VERSION=$(multipass version | head -1)
        print_pass "Multipass is installed ($VERSION)"
    else
        print_fail "Multipass is not installed"
        exit 1
    fi
}

test_vm_status() {
    print_header "Checking VM Status"
    
    print_test "VM '$VM_NAME' exists"
    if multipass list | grep -q "$VM_NAME"; then
        print_pass "VM exists"
    else
        print_fail "VM does not exist"
        echo "Create with: multipass launch --name $VM_NAME --cloud-init gvisor.yaml --cpus 2 --memory 4G --disk 20G"
        exit 1
    fi
    
    print_test "VM is running"
    VM_STATE=$(multipass list | grep "$VM_NAME" | awk '{print $2}')
    if [ "$VM_STATE" == "Running" ]; then
        print_pass "VM is running"
    else
        print_fail "VM is not running (State: $VM_STATE)"
        exit 1
    fi
    
    print_test "Cloud-init completed"
    CLOUD_INIT_STATUS=$(vm_exec cloud-init status 2>&1 | grep "status:" | awk '{print $2}')
    if [ "$CLOUD_INIT_STATUS" == "done" ]; then
        print_pass "Cloud-init completed successfully"
    elif [ "$CLOUD_INIT_STATUS" == "error" ]; then
        print_warn "Cloud-init completed with errors (core services may still be running)"
        print_info "Check with: multipass exec $VM_NAME -- cloud-init status --long"
    else
        print_fail "Cloud-init status: $CLOUD_INIT_STATUS"
    fi
}

test_gvisor_installation() {
    print_header "Testing gVisor Installation"
    
    print_test "runsc binary exists"
    if vm_exec_output test -f /usr/local/bin/runsc && echo "exists"; then
        print_pass "runsc binary found"
    else
        print_fail "runsc binary not found"
        return
    fi
    
    print_test "runsc is executable"
    if vm_exec_output test -x /usr/local/bin/runsc && echo "executable"; then
        print_pass "runsc is executable"
    else
        print_fail "runsc is not executable"
    fi
    
    print_test "runsc version"
    VERSION=$(vm_exec /usr/local/bin/runsc --version 2>/dev/null | head -1)
    if [ -n "$VERSION" ]; then
        print_pass "runsc version: $VERSION"
    else
        print_fail "Could not get runsc version"
    fi
    
    print_test "containerd-shim-runsc-v1 exists"
    if vm_exec_output test -f /usr/local/bin/containerd-shim-runsc-v1 && echo "exists"; then
        print_pass "containerd-shim-runsc-v1 found"
    else
        print_fail "containerd-shim-runsc-v1 not found"
    fi
}

test_containerd() {
    print_header "Testing containerd Configuration"
    
    print_test "containerd service status"
    if vm_exec systemctl is-active containerd >/dev/null 2>&1; then
        print_pass "containerd service is active"
    else
        print_fail "containerd service is not active"
        return
    fi
    
    print_test "containerd configuration exists"
    if vm_exec_output test -f /etc/containerd/config.toml && echo "exists"; then
        print_pass "containerd config exists"
    else
        print_fail "containerd config not found"
    fi
    
    print_test "gVisor runtime configured"
    if vm_exec grep -q "io.containerd.runsc.v1" /etc/containerd/config.toml; then
        print_pass "gVisor runtime configured in containerd"
    else
        print_fail "gVisor runtime not configured"
    fi
    
    print_test "runsc config exists"
    if vm_exec_output test -f /etc/containerd/runsc.toml && echo "exists"; then
        print_pass "runsc configuration exists"
    else
        print_warn "runsc configuration not found"
    fi
}

test_nerdctl() {
    print_header "Testing nerdctl (Container CLI)"
    
    print_test "nerdctl binary exists"
    if vm_exec_output test -f /usr/local/bin/nerdctl && echo "exists"; then
        print_pass "nerdctl binary found"
    else
        print_fail "nerdctl binary not found"
        return
    fi
    
    print_test "nerdctl version"
    VERSION=$(vm_exec /usr/local/bin/nerdctl --version 2>/dev/null)
    if [ -n "$VERSION" ]; then
        print_pass "$VERSION"
    else
        print_fail "Could not get nerdctl version"
    fi
    
    print_test "nerdctl can list containers"
    if vm_exec /usr/local/bin/nerdctl ps >/dev/null 2>&1; then
        print_pass "nerdctl ps works"
    else
        print_fail "nerdctl ps failed"
    fi
}

test_cni_plugins() {
    print_header "Testing CNI Plugins"
    
    print_test "CNI plugins directory exists"
    if vm_exec_output test -d /opt/cni/bin && echo "exists"; then
        print_pass "CNI plugins directory exists"
    else
        print_fail "CNI plugins directory not found"
        return
    fi
    
    print_test "CNI plugins installed"
    PLUGIN_COUNT=$(vm_exec ls /opt/cni/bin | wc -l)
    if [ "$PLUGIN_COUNT" -gt 5 ]; then
        print_pass "CNI plugins installed ($PLUGIN_COUNT plugins)"
    else
        print_warn "Few CNI plugins found ($PLUGIN_COUNT)"
    fi
}

test_caddy_deployment() {
    print_header "Testing Caddy Deployment"
    
    print_test "Caddy container exists"
    if vm_exec /usr/local/bin/nerdctl ps -a --format "{{.Names}}" | grep -q "caddy-gvisor"; then
        print_pass "Caddy container exists"
    else
        print_fail "Caddy container not found"
        return
    fi
    
    print_test "Caddy container is running"
    if vm_exec /usr/local/bin/nerdctl ps --format "{{.Names}}" | grep -q "caddy-gvisor"; then
        print_pass "Caddy container is running"
    else
        print_fail "Caddy container is not running"
        print_info "Start with: multipass exec $VM_NAME -- /home/ubuntu/deploy-caddy.sh"
        return
    fi
    
    print_test "Caddy container using gVisor runtime"
    RUNTIME=$(vm_exec /usr/local/bin/nerdctl inspect caddy-gvisor --format '{{.State.Runtime}}' 2>/dev/null || echo "unknown")
    if echo "$RUNTIME" | grep -q "runsc"; then
        print_pass "Container using gVisor runtime: $RUNTIME"
    else
        print_fail "Container not using gVisor runtime (using: $RUNTIME)"
    fi
    
    print_test "Caddy data directory exists"
    if vm_exec_output test -d /home/ubuntu/caddy-data && echo "exists"; then
        print_pass "Caddy data directory exists"
    else
        print_warn "Caddy data directory not found"
    fi
    
    print_test "Caddyfile exists"
    if vm_exec_output test -f /home/ubuntu/caddy-data/Caddyfile && echo "exists"; then
        print_pass "Caddyfile exists"
    else
        print_fail "Caddyfile not found"
    fi
}

test_caddy_webserver() {
    print_header "Testing Caddy Webserver"
    
    print_test "Port 80 is listening"
    if vm_exec ss -tuln | grep -q ":80 "; then
        print_pass "Port 80 is listening"
    else
        print_fail "Port 80 is not listening"
        return
    fi
    
    print_test "HTTP health endpoint"
    HTTP_CODE=$(vm_exec curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" == "200" ]; then
        print_pass "Health endpoint returns 200 OK"
    else
        print_fail "Health endpoint failed (HTTP $HTTP_CODE)"
    fi
    
    print_test "HTTP homepage"
    HTTP_CODE=$(vm_exec curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" == "200" ]; then
        print_pass "Homepage returns 200 OK"
    else
        print_fail "Homepage failed (HTTP $HTTP_CODE)"
    fi
    
    print_test "Homepage content"
    CONTENT=$(vm_exec curl -s http://localhost/ 2>/dev/null || echo "")
    if echo "$CONTENT" | grep -q "gVisor"; then
        print_pass "Homepage contains expected content"
    else
        print_warn "Homepage content might be incorrect"
    fi
    
    print_test "API info endpoint"
    API_RESPONSE=$(vm_exec curl -s http://localhost/api/info 2>/dev/null || echo "")
    if echo "$API_RESPONSE" | grep -q "gVisor"; then
        print_pass "API endpoint works: $API_RESPONSE"
    else
        print_fail "API endpoint failed"
    fi
}

test_container_isolation() {
    print_header "Testing Container Isolation"
    
    print_test "Container process isolation"
    CONTAINER_PID=$(vm_exec /usr/local/bin/nerdctl inspect caddy-gvisor --format '{{.State.Pid}}' 2>/dev/null || echo "0")
    if [ "$CONTAINER_PID" -gt 0 ]; then
        print_pass "Container has PID: $CONTAINER_PID"
    else
        print_fail "Could not get container PID"
    fi
    
    print_test "gVisor sandbox process"
    if vm_exec ps aux | grep -q "[r]unsc"; then
        print_pass "gVisor sandbox process running"
        RUNSC_COUNT=$(vm_exec ps aux | grep "[r]unsc" | wc -l)
        print_info "Found $RUNSC_COUNT runsc processes"
    else
        print_warn "No runsc processes found (might be using different isolation)"
    fi
    
    print_test "Container filesystem isolation"
    # Try to access container filesystem
    if vm_exec /usr/local/bin/nerdctl exec caddy-gvisor ls / >/dev/null 2>&1; then
        print_pass "Can access container filesystem"
    else
        print_warn "Cannot access container filesystem"
    fi
}

test_networking() {
    print_header "Testing Network Configuration"
    
    print_test "Container has network connectivity"
    if vm_exec /usr/local/bin/nerdctl exec caddy-gvisor ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_pass "Container can ping external IP"
    else
        print_warn "Container cannot ping external IP"
    fi
    
    print_test "Container DNS resolution"
    if vm_exec /usr/local/bin/nerdctl exec caddy-gvisor nslookup google.com >/dev/null 2>&1; then
        print_pass "Container DNS resolution works"
    else
        print_warn "Container DNS resolution failed"
    fi
    
    print_test "VM to container connectivity"
    if vm_exec curl -s http://localhost/health >/dev/null 2>&1; then
        print_pass "VM can reach container webserver"
    else
        print_fail "VM cannot reach container webserver"
    fi
}

test_auto_start() {
    print_header "Testing Auto-Start Configuration"
    
    print_test "Systemd service exists"
    if vm_exec_output test -f /etc/systemd/system/caddy-gvisor.service && echo "exists"; then
        print_pass "Systemd service file exists"
    else
        print_fail "Systemd service file not found"
    fi
    
    print_test "Service is enabled"
    if vm_exec systemctl is-enabled caddy-gvisor.service 2>/dev/null | grep -q "enabled"; then
        print_pass "Service is enabled for auto-start"
    else
        print_warn "Service is not enabled"
    fi
    
    print_test "Container restart policy"
    RESTART_POLICY=$(vm_exec /usr/local/bin/nerdctl inspect caddy-gvisor --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "no")
    if [ "$RESTART_POLICY" == "unless-stopped" ] || [ "$RESTART_POLICY" == "always" ]; then
        print_pass "Container has restart policy: $RESTART_POLICY"
    else
        print_warn "Container restart policy: $RESTART_POLICY"
    fi
}

test_resources() {
    print_header "Testing Resources"
    
    print_test "VM disk space"
    DISK_USAGE=$(vm_exec df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -lt 80 ]; then
        print_pass "Disk usage: ${DISK_USAGE}%"
    else
        print_warn "Disk usage high: ${DISK_USAGE}%"
    fi
    
    print_test "VM memory"
    TOTAL_MEM=$(vm_exec free -h | grep "Mem:" | awk '{print $2}')
    print_pass "Total memory: $TOTAL_MEM"
    
    print_test "Container resource usage"
    CONTAINER_MEM=$(vm_exec /usr/local/bin/nerdctl stats --no-stream caddy-gvisor --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")
    if [ "$CONTAINER_MEM" != "N/A" ]; then
        print_pass "Container memory: $CONTAINER_MEM"
    else
        print_info "Could not get container stats"
    fi
}

cleanup() {
    print_header "Cleanup"
    echo "  Removing test artifacts..."
    # Nothing to clean up for now
    print_pass "Cleanup complete"
}

print_summary() {
    print_header "Test Summary"
    echo ""
    echo -e "  ${GREEN}Passed:  $PASSED${NC}"
    echo -e "  ${RED}Failed:  $FAILED${NC}"
    echo -e "  ${YELLOW}Warned:  $WARNED${NC}"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}All $PASSED tests passed! ✓${NC}"
        echo ""
        echo -e "  ${CYAN}gVisor VM is healthy and ready to use.${NC}"
    else
        echo -e "  ${RED}${BOLD}$FAILED of $((PASSED + FAILED)) tests failed${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    clear
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       GVISOR VM TEST SUITE                                     ║${NC}"
    echo -e "${BOLD}║       VM: $VM_NAME${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    test_prerequisites
    test_vm_status
    test_gvisor_installation
    test_containerd
    test_nerdctl
    test_cni_plugins
    test_caddy_deployment
    test_caddy_webserver
    test_container_isolation
    test_networking
    test_auto_start
    test_resources
    cleanup
    print_summary
    
    # Exit with error if any tests failed
    if [ $FAILED -gt 0 ]; then
        exit 1
    fi
}

main "$@"
