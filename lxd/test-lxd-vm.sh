#!/bin/bash

#===============================================================================
# LXD VM Test Script v2
# 
# Tests: VM accessibility, LXD installation, storage, networking,
#        container operations via HTTP, profiles, and security
#
# Uses a simpler test approach to avoid multipass exec capture issues
#
# Usage: ./test-lxd-vm.sh [vm-name]
# Default VM name: lxd-vm
#===============================================================================

VM_NAME="${1:-lxd-vm}"

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
TMPFILE="/tmp/lxd_test_$$.txt"

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
    
    # Check lxc client
    print_test "LXC client available"
    if vm_run "lxc --version"; then
        local ver=$(output | head -1)
        if [ -n "$ver" ]; then
            pass
            info "LXC version: $ver"
        else
            fail "LXC version not found"
        fi
    else
        fail "LXC client not found"
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
    
    # Check lxd socket
    print_test "LXD socket accessible"
    if vm_run "test -S /var/snap/lxd/common/lxd/unix.socket && echo ok" && [ "$(output)" = "ok" ]; then
        pass
    else
        fail "LXD socket not found"
    fi
}

#-------------------------------------------------------------------------------
# Test: LXD Storage
#-------------------------------------------------------------------------------
test_lxd_storage() {
    print_header "LXD Storage Tests"
    
    # Check default storage pool exists
    print_test "Default storage pool exists"
    if vm_run "lxc storage list --format=csv" && grep -q "default" "$TMPFILE"; then
        pass
        vm_run "lxc storage show default | grep 'driver:'"
        local driver=$(output | awk '{print $2}')
        info "Storage driver: $driver"
    else
        fail "Default storage pool not found"
    fi
    
    # Check storage pool is active
    print_test "Storage pool is usable"
    if vm_run "lxc storage info default" && grep -qi "used by" "$TMPFILE"; then
        pass
    else
        fail "Storage pool not usable"
    fi
}

#-------------------------------------------------------------------------------
# Test: LXD Networking
#-------------------------------------------------------------------------------
test_lxd_networking() {
    print_header "LXD Networking Tests"
    
    # Check lxdbr0 bridge exists
    print_test "LXD bridge (lxdbr0) exists"
    if vm_run "lxc network list --format=csv" && grep -q "lxdbr0" "$TMPFILE"; then
        pass
    else
        fail "lxdbr0 network not found"
    fi
    
    # Check bridge configuration
    print_test "Bridge has IPv4 address"
    if vm_run "lxc network get lxdbr0 ipv4.address"; then
        local ip=$(output | head -1)
        if [ -n "$ip" ] && [ "$ip" != "none" ]; then
            pass
            info "Bridge IP: $ip"
        else
            fail "Bridge IPv4 not configured"
        fi
    else
        fail "Cannot query bridge"
    fi
    
    # Check NAT is enabled
    print_test "NAT enabled on bridge"
    if vm_run "lxc network get lxdbr0 ipv4.nat" && [ "$(output | head -1)" = "true" ]; then
        pass
    else
        warn "NAT may not be enabled"
    fi
    
    # Check bridge interface exists in system
    print_test "Bridge interface active in system"
    if vm_run "ip link show lxdbr0" && grep -q "lxdbr0" "$TMPFILE"; then
        pass
    else
        fail "lxdbr0 interface not found in system"
    fi
}

#-------------------------------------------------------------------------------
# Test: LXD Profiles
#-------------------------------------------------------------------------------
test_lxd_profiles() {
    print_header "LXD Profile Tests"
    
    # Check default profile exists
    print_test "Default profile exists"
    if vm_run "lxc profile list --format=csv" && grep -q "default" "$TMPFILE"; then
        pass
    else
        fail "Default profile not found"
    fi
    
    # Check default profile has root disk
    print_test "Default profile has root disk"
    vm_run "lxc profile show default"
    if grep -q "type: disk" "$TMPFILE"; then
        pass
    else
        fail "Default profile missing root disk"
    fi
    
    # Check default profile has network
    print_test "Default profile has network"
    if grep -q "type: nic" "$TMPFILE"; then
        pass
    else
        fail "Default profile missing network device"
    fi
    
    # Check example profiles exist
    print_test "Example profiles available"
    if vm_run "test -f /home/ubuntu/examples/web-profile.yaml && echo ok" && [ "$(output)" = "ok" ]; then
        pass
    else
        warn "Example profiles not found"
    fi
}

#-------------------------------------------------------------------------------
# Test: LXD Images
#-------------------------------------------------------------------------------
test_lxd_images() {
    print_header "LXD Image Tests"
    
    # Check remote image servers
    print_test "Ubuntu remote configured"
    vm_run "lxc remote list --format=csv"
    if grep -q "ubuntu" "$TMPFILE"; then
        pass
    else
        fail "Ubuntu remote not configured"
    fi
    
    # Check images remote
    print_test "Images remote configured"
    if grep -q "images" "$TMPFILE"; then
        pass
    else
        warn "Images remote not configured"
    fi
    
    # Check if ubuntu image is cached
    print_test "Ubuntu image cached locally"
    if vm_run "lxc image list --format=csv" && grep -qi "ubuntu" "$TMPFILE"; then
        pass
        info "Ubuntu image available locally"
    else
        warn "Ubuntu image not pre-cached"
    fi
}

#-------------------------------------------------------------------------------
# Test: Web Container (via HTTP)
#-------------------------------------------------------------------------------
test_web_container() {
    print_header "Web Container Tests (HTTP)"
    
    # Check web-test container exists
    print_test "Web container exists"
    vm_run "lxc list --format=csv"
    if grep -q "web-test" "$TMPFILE"; then
        pass
    else
        fail "web-test container not found"
        return
    fi
    
    # Check container is running
    print_test "Web container is running"
    if grep -q "web-test,RUNNING" "$TMPFILE"; then
        pass
    else
        fail "Container not running"
        return
    fi
    
    # Check container has IP
    print_test "Container has network"
    if vm_run "lxc list web-test --format=csv"; then
        local line=$(output)
        local ip=$(echo "$line" | cut -d',' -f3)
        if [ -n "$ip" ] && [[ "$ip" == *"eth0"* ]]; then
            pass
            info "Container IP: $ip"
        else
            fail "Container has no IP address"
        fi
    else
        fail "Cannot query container"
    fi
    
    # Check proxy device is configured
    print_test "Proxy device configured"
    if vm_run "lxc config device show web-test" && grep -q "type: proxy" "$TMPFILE"; then
        pass
        info "Port 8080 proxied to container"
    else
        fail "Proxy device not configured"
    fi
    
    # Test HTTP access via VM's port 8080
    print_test "HTTP accessible on VM port 8080"
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
# Test: Container Operations (via existing container)
#-------------------------------------------------------------------------------
test_container_operations() {
    print_header "Container Operations Tests"
    
    # Test exec into container
    print_test "Exec into container"
    if vm_run "lxc exec web-test -- cat /etc/os-release" && grep -qi "ubuntu\|PRETTY" "$TMPFILE"; then
        pass
    else
        fail "Cannot exec into container"
    fi
    
    # Test container internet access
    print_test "Container internet access"
    if vm_run "lxc exec web-test -- ping -c 1 -W 3 8.8.8.8" && grep -q "bytes from" "$TMPFILE"; then
        pass
    else
        warn "Container may not have internet (ping failed)"
    fi
    
    # Test file push
    print_test "Push file to container"
    local test_id="$$"
    vm_run "echo 'test-content-${test_id}' > /tmp/test-push-${test_id}.txt"
    if vm_run "lxc file push /tmp/test-push-${test_id}.txt web-test/tmp/"; then
        pass
    else
        fail "Failed to push file"
    fi
    
    # Test file pull
    print_test "Pull file from container"
    if vm_run "lxc file pull web-test/tmp/test-push-${test_id}.txt /tmp/test-pull-${test_id}.txt && cat /tmp/test-pull-${test_id}.txt" && grep -q "test-content-${test_id}" "$TMPFILE"; then
        pass
    else
        fail "Failed to pull file or content mismatch"
    fi
    
    # Cleanup test files
    vm_run "rm -f /tmp/test-push-${test_id}.txt /tmp/test-pull-${test_id}.txt"
}

#-------------------------------------------------------------------------------
# Test: Snapshot Operations
#-------------------------------------------------------------------------------
test_snapshot_operations() {
    print_header "Snapshot Operations Tests"
    
    local snap_name="test-snap-$$"
    
    # Create a snapshot (no output capture - just check exit code)
    print_test "Create snapshot"
    if multipass exec "$VM_NAME" -- lxc snapshot web-test "$snap_name" 2>/dev/null; then
        pass
    else
        fail "Failed to create snapshot"
        return
    fi
    
    # List snapshots
    print_test "List snapshots"
    if vm_run "lxc info web-test" && grep -q "${snap_name}" "$TMPFILE"; then
        pass
    else
        fail "Snapshot not found in list"
    fi
    
    # Delete snapshot (no output capture)
    print_test "Delete snapshot"
    if multipass exec "$VM_NAME" -- lxc delete "web-test/${snap_name}" 2>/dev/null; then
        pass
    else
        fail "Failed to delete snapshot"
    fi
}

#-------------------------------------------------------------------------------
# Test: Security Features
#-------------------------------------------------------------------------------
test_security_features() {
    print_header "Security Features Tests"
    
    # Check AppArmor is available
    print_test "AppArmor available"
    if vm_run "test -d /sys/kernel/security/apparmor && echo ok" && [ "$(output)" = "ok" ]; then
        pass
    else
        warn "AppArmor not available"
    fi
    
    # Check unprivileged containers supported
    print_test "Unprivileged containers"
    if vm_run "test -f /etc/subuid && test -f /etc/subgid && echo ok" && [ "$(output)" = "ok" ]; then
        pass
    else
        warn "Unprivileged container support may be limited"
    fi
    
    # Check cgroup version
    print_test "Cgroup configuration"
    if vm_run "stat -fc %T /sys/fs/cgroup/"; then
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
# Test: API Access
#-------------------------------------------------------------------------------
test_api_access() {
    print_header "API Access Tests"
    
    # Check HTTPS API is listening
    print_test "HTTPS API listening"
    if vm_run "ss -tlnp | grep ':8443'" && grep -q "8443" "$TMPFILE"; then
        pass
        info "API available on port 8443"
    else
        warn "HTTPS API not listening on 8443"
    fi
    
    # Check core.https_address is set
    print_test "HTTPS address configured"
    if vm_run "lxc config get core.https_address"; then
        local addr=$(output | head -1)
        if [ -n "$addr" ]; then
            pass
            info "HTTPS address: $addr"
        else
            warn "HTTPS address not configured"
        fi
    else
        warn "Cannot query HTTPS address"
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
    
    # Check examples directory
    print_test "Examples directory accessible"
    if vm_run "test -d /home/ubuntu/examples && test -r /home/ubuntu/examples && echo ok" && [ "$(output)" = "ok" ]; then
        pass
    else
        warn "Examples directory not accessible"
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
    
    # Check available disk space
    print_test "Disk space available"
    if vm_run "df -BG / | awk 'NR==2{print \$4}' | tr -d 'G'"; then
        local disk=$(output | tr -d '[:space:]')
        if [ "${disk:-0}" -ge 5 ]; then
            pass
            info "Available disk: ${disk}GB"
        else
            warn "Low disk: ${disk}GB available"
        fi
    else
        warn "Cannot check disk"
    fi
}

#-------------------------------------------------------------------------------
# Check Common Issues
#-------------------------------------------------------------------------------
check_common_issues() {
    print_header "Common Issues Check"
    
    local issues_found=0
    
    # Check for snap refresh in progress
    print_test "No snap refresh in progress"
    if vm_run "snap changes | grep -c 'Doing'"; then
        local doing=$(output | tr -d '[:space:]')
        if [ "${doing:-0}" -eq 0 ]; then
            pass
        else
            warn "Snap refresh in progress"
            issues_found=$((issues_found + 1))
        fi
    else
        pass
    fi
    
    # Check DNS resolution
    print_test "DNS resolution working"
    if vm_run "host -W 3 google.com" && grep -q "has address" "$TMPFILE"; then
        pass
    else
        warn "DNS resolution may have issues"
        issues_found=$((issues_found + 1))
    fi
    
    # Check web container health via HTTP
    print_test "Web container health check"
    local health=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://${VM_IP}:8080/" 2>/dev/null)
    if [ "$health" = "200" ]; then
        pass
    else
        warn "Web container may be unhealthy"
        issues_found=$((issues_found + 1))
    fi
    
    # Summary
    if [ $issues_found -eq 0 ]; then
        echo ""
        echo -e "  ${GREEN}No common issues found${NC}"
    else
        echo ""
        echo -e "  ${YELLOW}Found $issues_found potential issue(s)${NC}"
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
        echo -e "  ${GREEN}LXD VM is healthy and ready to use.${NC}"
        echo ""
        echo -e "  ${BLUE}Web container accessible at: http://${VM_IP}:8080${NC}"
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
    echo -e "${BLUE}║                    LXD VM TEST SUITE v2                        ║${NC}"
    echo -e "${BLUE}║       VM: $VM_NAME${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    test_vm_accessibility
    test_lxd_installation
    test_lxd_storage
    test_lxd_networking
    test_lxd_profiles
    test_lxd_images
    test_web_container
    test_container_operations
    test_snapshot_operations
    test_security_features
    test_api_access
    test_permissions
    test_resources
    check_common_issues
    
    print_summary
}

# Run main
main "$@"
