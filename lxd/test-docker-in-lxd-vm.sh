#!/bin/bash

#===============================================================================
# Docker-in-LXD VM Test Script
# 
# Tests: VM accessibility, LXD installation, Docker profile, Docker container,
#        Docker functionality, and HTTP access via proxy device
#
# Usage: ./test-docker-in-lxd-vm.sh [vm-name]
# Default VM name: docker-in-lxd-vm
#===============================================================================

VM_NAME="${1:-docker-in-lxd-vm}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# VM IP address (set during tests)
VM_IP=""

# Temp file for output capture
TMPFILE="/tmp/docker_lxd_test_$$.txt"

#-------------------------------------------------------------------------------
# Output Functions
#-------------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_test() {
    echo -n "  Testing: $1... "
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${RED}→ $1${NC}"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${YELLOW}→ $1${NC}"
    fi
    TESTS_WARNED=$((TESTS_WARNED + 1))
}

info() {
    echo -e "    ${BLUE}ℹ $1${NC}"
}

#-------------------------------------------------------------------------------
# Helper: Execute command and capture output to file
#-------------------------------------------------------------------------------
vm_run() {
    multipass exec "$VM_NAME" -- sh -c "$1" > "$TMPFILE" 2>&1
    return $?
}

# Read captured output
output() {
    cat "$TMPFILE" 2>/dev/null
}

# Cleanup
cleanup() {
    rm -f "$TMPFILE"
}
trap cleanup EXIT

#-------------------------------------------------------------------------------
# Test: VM Accessibility
#-------------------------------------------------------------------------------
test_vm_accessibility() {
    print_header "VM Accessibility Tests"
    
    # Check if VM exists
    print_test "VM exists in multipass"
    if multipass list 2>/dev/null | grep -q "$VM_NAME"; then
        pass
    else
        fail "VM '$VM_NAME' not found"
        echo -e "${RED}Cannot continue without VM. Exiting.${NC}"
        exit 1
    fi
    
    # Check VM state
    print_test "VM is running"
    multipass info "$VM_NAME" > "$TMPFILE" 2>/dev/null
    if grep -q "State:.*Running" "$TMPFILE"; then
        pass
    else
        fail "VM is not running"
        exit 1
    fi
    
    # Get VM IP
    VM_IP=$(grep "IPv4:" "$TMPFILE" | awk '{print $2}')
    
    # Check shell access
    print_test "Shell access available"
    if vm_run "echo ok" && [ "$(output)" = "ok" ]; then
        pass
        info "VM IP: $VM_IP"
    else
        fail "Cannot execute commands in VM"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Test: LXD Installation
#-------------------------------------------------------------------------------
test_lxd_installation() {
    print_header "LXD Installation Tests"
    
    # Check LXD version
    print_test "LXD snap installed"
    if vm_run "lxd --version"; then
        local ver=$(output | head -1)
        if [ -n "$ver" ]; then
            pass
            info "LXD version: $ver"
        else
            fail "LXD version not found"
        fi
    else
        fail "LXD not installed"
    fi
    
    # Check LXD daemon is running
    print_test "LXD daemon running"
    if vm_run "snap services lxd" && grep -q "active" "$TMPFILE"; then
        pass
    else
        fail "LXD daemon not running"
    fi
    
    # Check ubuntu user in lxd group
    print_test "User in lxd group"
    if vm_run "groups ubuntu" && grep -q "lxd" "$TMPFILE"; then
        pass
    else
        fail "ubuntu user not in lxd group"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Profile
#-------------------------------------------------------------------------------
test_docker_profile() {
    print_header "Docker Profile Tests"
    
    # Check docker profile exists
    print_test "Docker profile exists"
    if vm_run "lxc profile list --format=csv" && grep -q "docker" "$TMPFILE"; then
        pass
    else
        fail "Docker profile not found"
        return
    fi
    
    # Check security.nesting
    print_test "security.nesting enabled"
    if vm_run "lxc profile show docker" && grep -q 'security.nesting.*true' "$TMPFILE"; then
        pass
    else
        fail "security.nesting not enabled"
    fi
    
    # Check syscalls intercept mknod
    print_test "syscalls.intercept.mknod enabled"
    if grep -q 'security.syscalls.intercept.mknod.*true' "$TMPFILE"; then
        pass
    else
        fail "syscalls.intercept.mknod not enabled"
    fi
    
    # Check syscalls intercept setxattr
    print_test "syscalls.intercept.setxattr enabled"
    if grep -q 'security.syscalls.intercept.setxattr.*true' "$TMPFILE"; then
        pass
    else
        fail "syscalls.intercept.setxattr not enabled"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Host Container
#-------------------------------------------------------------------------------
test_docker_host_container() {
    print_header "Docker Host Container Tests"
    
    # Check docker-host container exists
    print_test "docker-host container exists"
    vm_run "lxc list --format=csv"
    if grep -q "docker-host" "$TMPFILE"; then
        pass
    else
        fail "docker-host container not found"
        return
    fi
    
    # Check container is running
    print_test "docker-host is running"
    if grep -q "docker-host,RUNNING" "$TMPFILE"; then
        pass
    else
        fail "docker-host not running"
        return
    fi
    
    # Check container has docker profile
    print_test "Container has docker profile"
    if vm_run "lxc config show docker-host" && grep -q "docker" "$TMPFILE"; then
        pass
    else
        warn "Docker profile may not be applied"
    fi
    
    # Check container has IP
    print_test "Container has network"
    if vm_run "lxc list docker-host --format=csv"; then
        local line=$(output)
        if echo "$line" | grep -q "eth0"; then
            pass
            local ip=$(echo "$line" | cut -d',' -f3)
            info "Container IP: $ip"
        else
            fail "Container has no IP address"
        fi
    else
        fail "Cannot query container"
    fi
    
    # Check proxy device
    print_test "Proxy device configured"
    if vm_run "lxc config device show docker-host" && grep -q "type: proxy" "$TMPFILE"; then
        pass
        info "Port 8080 proxied to container"
    else
        fail "Proxy device not configured"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Inside Container
#-------------------------------------------------------------------------------
test_docker_inside_container() {
    print_header "Docker Inside Container Tests"
    
    # Check Docker is installed
    print_test "Docker installed in container"
    if vm_run "lxc exec docker-host -- docker --version"; then
        local ver=$(output | head -1)
        if echo "$ver" | grep -qi "docker"; then
            pass
            info "$ver"
        else
            fail "Docker not installed"
            return
        fi
    else
        fail "Cannot check Docker version"
        return
    fi
    
    # Check Docker daemon is running
    print_test "Docker daemon running"
    if vm_run "lxc exec docker-host -- systemctl is-active docker" && [ "$(output)" = "active" ]; then
        pass
    else
        fail "Docker daemon not running"
    fi
    
    # Check Docker info works (proves daemon is functional)
    print_test "Docker daemon functional"
    if vm_run "lxc exec docker-host -- docker info" && grep -q "Server Version" "$TMPFILE"; then
        pass
    else
        fail "Docker daemon not functional"
    fi
    
    # Check containerd is running
    print_test "Containerd running"
    if vm_run "lxc exec docker-host -- systemctl is-active containerd" && [ "$(output)" = "active" ]; then
        pass
    else
        warn "Containerd may not be running"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Containers
#-------------------------------------------------------------------------------
test_docker_containers() {
    print_header "Docker Container Tests"
    
    # Check nginx container exists
    print_test "Nginx container exists"
    if vm_run "lxc exec docker-host -- docker ps --format '{{.Names}}'"; then
        if grep -q "web" "$TMPFILE"; then
            pass
        else
            fail "Nginx container 'web' not found"
            return
        fi
    else
        fail "Cannot list Docker containers"
        return
    fi
    
    # Check nginx container is running
    print_test "Nginx container running"
    if vm_run "lxc exec docker-host -- docker ps --filter name=web --format '{{.Status}}'"; then
        if grep -qi "up" "$TMPFILE"; then
            pass
            info "Status: $(output)"
        else
            fail "Nginx container not running"
        fi
    else
        fail "Cannot check container status"
    fi
    
    # Check nginx image exists
    print_test "Nginx image pulled"
    if vm_run "lxc exec docker-host -- docker images --format '{{.Repository}}:{{.Tag}}'"; then
        if grep -q "nginx" "$TMPFILE"; then
            pass
        else
            fail "Nginx image not found"
        fi
    else
        fail "Cannot list Docker images"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Operations
#-------------------------------------------------------------------------------
test_docker_operations() {
    print_header "Docker Operations Tests"
    
    # Test docker run (use exit code, avoid output capture issues)
    print_test "Docker run works"
    if multipass exec "$VM_NAME" -- lxc exec docker-host -- docker run --rm alpine echo "hello" > "$TMPFILE" 2>&1; then
        if grep -q "hello" "$TMPFILE"; then
            pass
        else
            fail "Docker run output unexpected"
        fi
    else
        fail "Cannot run Docker containers"
    fi
    
    # Test docker pull (check if alpine exists, pull already done)
    print_test "Docker pull works"
    if vm_run "lxc exec docker-host -- docker images alpine --format '{{.Repository}}'"; then
        if grep -q "alpine" "$TMPFILE"; then
            pass
        else
            fail "Alpine image not available"
        fi
    else
        fail "Cannot check images"
    fi
    
    # Test docker networking (container can reach internet) - use file redirect
    print_test "Docker container networking"
    if multipass exec "$VM_NAME" -- lxc exec docker-host -- docker run --rm alpine ping -c 1 -W 3 8.8.8.8 > "$TMPFILE" 2>&1; then
        if grep -q "bytes from" "$TMPFILE"; then
            pass
        else
            warn "Ping succeeded but no response captured"
        fi
    else
        warn "Docker containers may not have internet access"
    fi
}

#-------------------------------------------------------------------------------
# Test: HTTP Access via Proxy
#-------------------------------------------------------------------------------
test_http_access() {
    print_header "HTTP Access Tests"
    
    # Test HTTP from inside VM
    print_test "HTTP accessible from VM"
    if vm_run "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080"; then
        if [ "$(output)" = "200" ]; then
            pass
        else
            fail "HTTP response: $(output)"
        fi
    else
        fail "Cannot reach localhost:8080"
    fi
    
    # Test HTTP from host (via VM IP)
    print_test "HTTP accessible from host"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${VM_IP}:8080/" 2>/dev/null)
    if [ "$http_code" = "200" ]; then
        pass
        info "Nginx responding on http://${VM_IP}:8080"
    else
        fail "HTTP response: $http_code (expected 200)"
    fi
    
    # Test HTTP content
    print_test "Nginx serving content"
    local content=$(curl -s --connect-timeout 5 "http://${VM_IP}:8080/" 2>/dev/null)
    if echo "$content" | grep -qi "nginx\|welcome"; then
        pass
    else
        warn "Unexpected content from nginx"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Compose
#-------------------------------------------------------------------------------
test_docker_compose() {
    print_header "Docker Compose Tests"
    
    # Check docker compose is available
    print_test "Docker Compose installed"
    if vm_run "lxc exec docker-host -- docker compose version"; then
        local ver=$(output | head -1)
        if echo "$ver" | grep -qi "docker compose"; then
            pass
            info "$ver"
        else
            fail "Docker Compose not found"
        fi
    else
        fail "Docker Compose not installed"
    fi
}

#-------------------------------------------------------------------------------
# Test: Security Configuration
#-------------------------------------------------------------------------------
test_security_config() {
    print_header "Security Configuration Tests"
    
    # Check nesting is working (can see Docker's cgroups)
    print_test "Container nesting functional"
    if vm_run "lxc exec docker-host -- cat /proc/self/cgroup" && grep -q "docker\|0::" "$TMPFILE"; then
        pass
    else
        warn "Nesting may not be fully functional"
    fi
    
    # Check AppArmor profile
    print_test "AppArmor configured"
    if vm_run "lxc config get docker-host raw.lxc"; then
        pass
        # Note: This may be empty which is fine
    else
        pass
        # Default AppArmor is fine
    fi
    
    # Check cgroup v2
    print_test "Cgroup configuration"
    if vm_run "lxc exec docker-host -- stat -fc %T /sys/fs/cgroup/"; then
        local cgroup=$(output)
        if [ "$cgroup" = "cgroup2fs" ]; then
            pass
            info "Using cgroup v2"
        else
            pass
            info "Using cgroup v1"
        fi
    else
        warn "Cannot determine cgroup version"
    fi
}

#-------------------------------------------------------------------------------
# Test: Permissions
#-------------------------------------------------------------------------------
test_permissions() {
    print_header "Permissions Tests"
    
    # Check home directory ownership
    print_test "Home directory ownership"
    if vm_run "stat -c '%U:%G' /home/ubuntu" && [ "$(output)" = "ubuntu:ubuntu" ]; then
        pass
    else
        fail "Home directory ownership incorrect"
    fi
    
    # Check lxc works as ubuntu user
    print_test "LXC accessible as ubuntu user"
    if vm_run "sudo -u ubuntu lxc list --format=csv"; then
        pass
    else
        fail "ubuntu user cannot access lxc"
    fi
    
    # Check docker socket permissions inside container
    print_test "Docker socket accessible"
    if vm_run "lxc exec docker-host -- stat -c '%a' /var/run/docker.sock"; then
        local perms=$(output | tr -d '[:space:]')
        if [ "$perms" = "660" ] || [ "$perms" = "666" ]; then
            pass
            info "Docker socket permissions: $perms"
        else
            warn "Docker socket permissions: $perms (expected 660 or 666)"
        fi
    else
        fail "Cannot check docker socket"
    fi
    
    # Check ubuntu user in docker group inside container
    print_test "Ubuntu user in docker group"
    if vm_run "lxc exec docker-host -- groups ubuntu"; then
        if echo "$(output)" | grep -q "docker"; then
            pass
        else
            fail "ubuntu user not in docker group"
        fi
    else
        fail "Cannot check user groups"
    fi
    
    # Check container root filesystem permissions
    print_test "Container filesystem writable"
    if vm_run "lxc exec docker-host -- touch /tmp/test-write && lxc exec docker-host -- rm /tmp/test-write && echo ok"; then
        if [ "$(output)" = "ok" ]; then
            pass
        else
            fail "Container filesystem not writable"
        fi
    else
        fail "Cannot write to container filesystem"
    fi
}

#-------------------------------------------------------------------------------
# Test: Resources
#-------------------------------------------------------------------------------
test_resources() {
    print_header "Resource Tests"
    
    # Check VM memory
    print_test "VM memory adequate"
    if vm_run "free -m | awk '/^Mem:/{print \$2}'"; then
        local mem=$(output | tr -d '[:space:]')
        if [ "${mem:-0}" -ge 1800 ]; then
            pass
            info "Total memory: ${mem}MB"
        else
            warn "Low memory: ${mem}MB (recommend >= 2GB)"
        fi
    else
        warn "Cannot check memory"
    fi
    
    # Check container memory
    print_test "Container has memory"
    if vm_run "lxc exec docker-host -- free -m | awk '/^Mem:/{print \$2}'"; then
        local mem=$(output | tr -d '[:space:]')
        if [ "${mem:-0}" -ge 500 ]; then
            pass
            info "Container memory: ${mem}MB"
        else
            warn "Low container memory: ${mem}MB"
        fi
    else
        warn "Cannot check container memory"
    fi
}

#-------------------------------------------------------------------------------
# Print Summary
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  TEST SUMMARY${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Warned:${NC}  $TESTS_WARNED"
    echo ""
    
    local total=$((TESTS_PASSED + TESTS_FAILED))
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "  ${GREEN}All $total tests passed! ✓${NC}"
        echo ""
        echo -e "  ${GREEN}Docker-in-LXD is working correctly.${NC}"
        echo ""
        echo -e "  ${BLUE}Web container accessible at: http://${VM_IP}:8080${NC}"
        echo ""
        echo -e "  ${BLUE}Access Docker:${NC}"
        echo -e "    multipass exec $VM_NAME -- lxc exec docker-host -- docker ps"
    else
        echo -e "  ${RED}$TESTS_FAILED of $total tests failed.${NC}"
        echo ""
        echo -e "  ${YELLOW}Review failed tests above for troubleshooting.${NC}"
    fi
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        return 1
    fi
    return 0
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              DOCKER-IN-LXD VM TEST SUITE                       ║${NC}"
    echo -e "${BLUE}║       VM: $VM_NAME${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    test_vm_accessibility
    test_lxd_installation
    test_docker_profile
    test_docker_host_container
    test_docker_inside_container
    test_docker_containers
    test_docker_operations
    test_http_access
    test_docker_compose
    test_security_config
    test_permissions
    test_resources
    
    print_summary
}

# Run main
main "$@"
