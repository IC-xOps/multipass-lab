#!/bin/bash

#===============================================================================
# Podman-in-Incus VM Test Script
# 
# Tests: VM accessibility, Incus installation, Podman profile, Podman container,
#        Podman functionality, rootless support, and HTTP access via proxy
#
# Usage: ./test-podman-in-incus-vm.sh [vm-name]
# Default VM name: podman-in-incus-vm
#===============================================================================

VM_NAME="${1:-podman-in-incus-vm}"

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
TMPFILE="/tmp/podman_incus_test_$$.txt"

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
# Test: Incus Installation
#-------------------------------------------------------------------------------
test_incus_installation() {
    print_header "Incus Installation Tests"
    
    # Check Incus version
    print_test "Incus installed"
    if vm_run "incus version"; then
        local ver=$(output | head -1)
        if [ -n "$ver" ]; then
            pass
            info "Incus version: $ver"
        else
            fail "Incus version not found"
        fi
    else
        fail "Incus not installed"
    fi
    
    # Check Incus daemon is running
    print_test "Incus daemon running"
    if vm_run "systemctl is-active incus" && [ "$(output | head -1)" = "active" ]; then
        pass
    else
        fail "Incus daemon not running"
    fi
    
    # Check ubuntu user in incus-admin group
    print_test "User in incus-admin group"
    if vm_run "groups ubuntu" && grep -q "incus-admin" "$TMPFILE"; then
        pass
    else
        fail "ubuntu user not in incus-admin group"
    fi
}

#-------------------------------------------------------------------------------
# Test: Podman Profile
#-------------------------------------------------------------------------------
test_podman_profile() {
    print_header "Podman Profile Tests"
    
    # Check podman profile exists
    print_test "Podman profile exists"
    if vm_run "incus profile list --format=csv" && grep -q "podman" "$TMPFILE"; then
        pass
    else
        fail "Podman profile not found"
        return
    fi
    
    # Check security.nesting
    print_test "security.nesting enabled"
    if vm_run "incus profile show podman" && grep -q 'security.nesting.*true' "$TMPFILE"; then
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
# Test: Podman Host Container
#-------------------------------------------------------------------------------
test_podman_host_container() {
    print_header "Podman Host Container Tests"
    
    # Check podman-host container exists
    print_test "podman-host container exists"
    vm_run "incus list --format=csv"
    if grep -q "podman-host" "$TMPFILE"; then
        pass
    else
        fail "podman-host container not found"
        return
    fi
    
    # Check container is running
    print_test "podman-host is running"
    if grep -q "podman-host,RUNNING" "$TMPFILE"; then
        pass
    else
        fail "podman-host not running"
        return
    fi
    
    # Check container has podman profile
    print_test "Container has podman profile"
    if vm_run "incus config show podman-host" && grep -q "podman" "$TMPFILE"; then
        pass
    else
        warn "Podman profile may not be applied"
    fi
    
    # Check container has IP
    print_test "Container has network"
    if vm_run "incus list podman-host --format=csv"; then
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
    if vm_run "incus config device show podman-host" && grep -q "type: proxy" "$TMPFILE"; then
        pass
        info "Port 8080 proxied to container"
    else
        fail "Proxy device not configured"
    fi
}

#-------------------------------------------------------------------------------
# Test: Podman Inside Container
#-------------------------------------------------------------------------------
test_podman_inside_container() {
    print_header "Podman Inside Container Tests"
    
    # Check Podman is installed
    print_test "Podman installed in container"
    if vm_run "incus exec podman-host -- podman --version"; then
        local ver=$(output | head -1)
        if echo "$ver" | grep -qi "podman"; then
            pass
            info "$ver"
        else
            fail "Podman not installed"
            return
        fi
    else
        fail "Cannot check Podman version"
        return
    fi
    
    # Check Podman info works (no daemon needed)
    print_test "Podman functional"
    if vm_run "incus exec podman-host -- podman info --format '{{.Host.OCIRuntime.Name}}'"; then
        local runtime=$(output | head -1)
        if [ -n "$runtime" ]; then
            pass
            info "OCI Runtime: $runtime"
        else
            fail "Podman info failed"
        fi
    else
        fail "Podman not functional"
    fi
    
    # Check podman-compose is installed
    print_test "Podman-compose installed"
    if vm_run "incus exec podman-host -- which podman-compose"; then
        pass
    else
        warn "podman-compose not installed"
    fi
    
    # Check slirp4netns for rootless networking
    print_test "slirp4netns available"
    if vm_run "incus exec podman-host -- which slirp4netns"; then
        pass
    else
        warn "slirp4netns not installed (needed for rootless)"
    fi
}

#-------------------------------------------------------------------------------
# Test: Podman Containers
#-------------------------------------------------------------------------------
test_podman_containers() {
    print_header "Podman Container Tests"
    
    # Check nginx container exists
    print_test "Nginx container exists"
    if vm_run "incus exec podman-host -- podman ps --format '{{.Names}}'"; then
        if grep -q "web" "$TMPFILE"; then
            pass
        else
            fail "Nginx container 'web' not found"
            return
        fi
    else
        fail "Cannot list Podman containers"
        return
    fi
    
    # Check nginx container is running
    print_test "Nginx container running"
    if vm_run "incus exec podman-host -- podman ps --filter name=web --format '{{.Status}}'"; then
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
    if vm_run "incus exec podman-host -- podman images --format '{{.Repository}}:{{.Tag}}'"; then
        if grep -q "nginx" "$TMPFILE"; then
            pass
        else
            fail "Nginx image not found"
        fi
    else
        fail "Cannot list Podman images"
    fi
}

#-------------------------------------------------------------------------------
# Test: Podman Operations
#-------------------------------------------------------------------------------
test_podman_operations() {
    print_header "Podman Operations Tests"
    
    # Test podman run
    print_test "Podman run works"
    if multipass exec "$VM_NAME" -- incus exec podman-host -- podman run --rm docker.io/alpine:3.21 echo "hello" > "$TMPFILE" 2>&1; then
        if grep -q "hello" "$TMPFILE"; then
            pass
        else
            fail "Podman run output unexpected"
        fi
    else
        fail "Cannot run Podman containers"
    fi
    
    # Test podman images
    print_test "Podman pull works"
    if vm_run "incus exec podman-host -- podman images --format '{{.Repository}}'"; then
        if grep -q "alpine" "$TMPFILE"; then
            pass
        else
            fail "Alpine image not available"
        fi
    else
        fail "Cannot check images"
    fi
    
    # Test podman networking
    print_test "Podman container networking"
    if multipass exec "$VM_NAME" -- incus exec podman-host -- podman run --rm docker.io/alpine:3.21 ping -c 1 -W 3 8.8.8.8 > "$TMPFILE" 2>&1; then
        if grep -q "bytes from" "$TMPFILE"; then
            pass
        else
            warn "Ping succeeded but no response captured"
        fi
    else
        warn "Podman containers may not have internet access"
    fi
}

#-------------------------------------------------------------------------------
# Test: Rootless Podman
#-------------------------------------------------------------------------------
test_rootless_podman() {
    print_header "Rootless Podman Tests"
    
    # Check subuid configured
    print_test "subuid configured for ubuntu"
    if vm_run "incus exec podman-host -- grep ubuntu /etc/subuid"; then
        if grep -q "ubuntu" "$TMPFILE"; then
            pass
            info "subuid: $(output)"
        else
            fail "ubuntu not in subuid"
        fi
    else
        fail "Cannot check subuid"
    fi
    
    # Check subgid configured
    print_test "subgid configured for ubuntu"
    if vm_run "incus exec podman-host -- grep ubuntu /etc/subgid"; then
        if grep -q "ubuntu" "$TMPFILE"; then
            pass
        else
            fail "ubuntu not in subgid"
        fi
    else
        fail "Cannot check subgid"
    fi
    
    # Test rootless podman run
    print_test "Rootless podman works"
    if multipass exec "$VM_NAME" -- incus exec podman-host -- su - ubuntu -c 'podman run --rm docker.io/alpine:3.21 echo rootless' > "$TMPFILE" 2>&1; then
        if grep -q "rootless" "$TMPFILE"; then
            pass
        else
            warn "Rootless podman may have issues"
        fi
    else
        warn "Rootless podman failed (may need additional setup)"
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
# Test: Podman vs Docker Compatibility
#-------------------------------------------------------------------------------
test_docker_compatibility() {
    print_header "Docker Compatibility Tests"
    
    # Check if podman can be aliased as docker
    print_test "Podman docker-compatible CLI"
    if vm_run "incus exec podman-host -- podman --help" && grep -q "Manage pods, containers and images" "$TMPFILE"; then
        pass
    else
        warn "Podman CLI may differ from Docker"
    fi
    
    # Check podman socket
    print_test "Podman socket available"
    if vm_run "incus exec podman-host -- ls /run/podman/podman.sock 2>/dev/null || echo 'no socket'"; then
        if grep -q "no socket" "$TMPFILE"; then
            warn "Podman socket not running (start with: podman system service)"
        else
            pass
        fi
    else
        warn "Cannot check podman socket"
    fi
}

#-------------------------------------------------------------------------------
# Test: Security Configuration
#-------------------------------------------------------------------------------
test_security_config() {
    print_header "Security Configuration Tests"
    
    # Check nesting is working
    print_test "Container nesting functional"
    if vm_run "incus exec podman-host -- cat /proc/self/cgroup" && grep -q "0::" "$TMPFILE"; then
        pass
    else
        warn "Nesting may not be fully functional"
    fi
    
    # Check cgroup v2
    print_test "Cgroup configuration"
    if vm_run "incus exec podman-host -- stat -fc %T /sys/fs/cgroup/"; then
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
    
    # Check fuse-overlayfs available
    print_test "fuse-overlayfs available"
    if vm_run "incus exec podman-host -- which fuse-overlayfs"; then
        pass
        info "fuse-overlayfs installed for rootless storage"
    else
        warn "fuse-overlayfs not installed"
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
    
    # Check incus works as ubuntu user
    print_test "Incus accessible as ubuntu user"
    if vm_run "sudo -u ubuntu incus list --format=csv"; then
        pass
    else
        fail "ubuntu user cannot access incus"
    fi
    
    # Check podman socket permissions inside container
    print_test "Podman socket accessible"
    if vm_run "incus exec podman-host -- test -S /run/podman/podman.sock && echo exists || echo missing"; then
        if [ "$(output)" = "exists" ]; then
            pass
            info "Podman socket exists"
        else
            warn "Podman socket not present (may need systemctl enable podman.socket)"
        fi
    else
        warn "Cannot check podman socket"
    fi
    
    # Check subuid/subgid configured for rootless
    print_test "Rootless UID mapping configured"
    if vm_run "incus exec podman-host -- cat /etc/subuid"; then
        if echo "$(output)" | grep -q "ubuntu"; then
            pass
        else
            fail "ubuntu not in subuid"
        fi
    else
        fail "Cannot check subuid"
    fi
    
    # Check container root filesystem permissions
    print_test "Container filesystem writable"
    if vm_run "incus exec podman-host -- touch /tmp/test-write && incus exec podman-host -- rm /tmp/test-write && echo ok"; then
        if [ "$(output)" = "ok" ]; then
            pass
        else
            fail "Container filesystem not writable"
        fi
    else
        fail "Cannot write to container filesystem"
    fi
    
    # Check ubuntu user home directory in container
    print_test "Ubuntu home dir in container"
    if vm_run "incus exec podman-host -- stat -c '%U:%G' /home/ubuntu"; then
        if [ "$(output)" = "ubuntu:ubuntu" ]; then
            pass
        else
            fail "Container home ownership incorrect: $(output)"
        fi
    else
        fail "Cannot check container home directory"
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
    if vm_run "incus exec podman-host -- free -m | awk '/^Mem:/{print \$2}'"; then
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
        echo -e "  ${GREEN}Podman-in-Incus is working correctly.${NC}"
        echo ""
        echo -e "  ${BLUE}Web container accessible at: http://${VM_IP}:8080${NC}"
        echo ""
        echo -e "  ${BLUE}Access Podman:${NC}"
        echo -e "    multipass exec $VM_NAME -- incus exec podman-host -- podman ps"
        echo ""
        echo -e "  ${BLUE}Rootless Podman:${NC}"
        echo -e "    multipass exec $VM_NAME -- incus exec podman-host -- sudo -u ubuntu podman ps"
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
    echo -e "${BLUE}║            PODMAN-IN-INCUS VM TEST SUITE                       ║${NC}"
    echo -e "${BLUE}║       VM: $VM_NAME${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    test_vm_accessibility
    test_incus_installation
    test_podman_profile
    test_podman_host_container
    test_podman_inside_container
    test_podman_containers
    test_podman_operations
    test_rootless_podman
    test_http_access
    test_docker_compatibility
    test_security_config
    test_permissions
    test_resources
    
    print_summary
}

# Run main
main "$@"
