#!/bin/bash
#
# Docker VM Test Script
# Tests if the docker-vm starts correctly and checks for permission issues
#

# Don't use set -e as it interferes with test logic and counter increments

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VM_NAME="docker-vm"
TIMEOUT=300  # 5 minutes timeout for VM to be ready
TEST_PASSED=0
TEST_FAILED=0

# Print functions
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test() {
    echo -e "${YELLOW}▶ Testing:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✔ PASS:${NC} $1"
    TEST_PASSED=$((TEST_PASSED + 1))
}

print_fail() {
    echo -e "${RED}✘ FAIL:${NC} $1"
    TEST_FAILED=$((TEST_FAILED + 1))
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
}

# Helper to run multipass exec and check exit code
# Avoids issues with &>/dev/null on some systems
vm_exec() {
    local result
    result=$(multipass exec "$VM_NAME" -- "$@" 2>&1)
    return $?
}

vm_exec_output() {
    multipass exec "$VM_NAME" -- "$@" 2>&1
}

# Check if multipass is installed
check_multipass() {
    print_header "Checking Prerequisites"
    
    print_test "Multipass installation"
    if command -v multipass &> /dev/null; then
        MULTIPASS_VERSION=$(multipass version | head -1)
        print_pass "Multipass is installed ($MULTIPASS_VERSION)"
    else
        print_fail "Multipass is not installed"
        echo "Please install multipass: brew install multipass"
        exit 1
    fi
}

# Check if VM exists
check_vm_exists() {
    print_header "Checking VM Status"
    
    print_test "VM '$VM_NAME' exists"
    if multipass list | grep -q "^$VM_NAME "; then
        print_pass "VM '$VM_NAME' exists"
        return 0
    else
        print_fail "VM '$VM_NAME' does not exist"
        print_info "Create it with: multipass launch --name $VM_NAME --cloud-init docker.yaml"
        return 1
    fi
}

# Check VM state
check_vm_state() {
    print_test "VM '$VM_NAME' is running"
    VM_STATE=$(multipass list | grep "^$VM_NAME " | awk '{print $2}')
    
    if [ "$VM_STATE" == "Running" ]; then
        print_pass "VM is running"
        return 0
    elif [ "$VM_STATE" == "Stopped" ]; then
        print_warn "VM is stopped, attempting to start..."
        if multipass start "$VM_NAME"; then
            print_pass "VM started successfully"
            return 0
        else
            print_fail "Failed to start VM"
            return 1
        fi
    else
        print_fail "VM is in unexpected state: $VM_STATE"
        return 1
    fi
}

# Wait for cloud-init to complete
wait_for_cloud_init() {
    print_header "Waiting for Cloud-Init"
    
    print_test "Cloud-init completion (timeout: ${TIMEOUT}s)"
    
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $TIMEOUT ]; do
        STATUS=$(multipass exec "$VM_NAME" -- cloud-init status 2>/dev/null || echo "error")
        
        if echo "$STATUS" | grep -q "status: done"; then
            print_pass "Cloud-init completed successfully"
            return 0
        elif echo "$STATUS" | grep -q "status: error"; then
            print_fail "Cloud-init completed with errors"
            print_info "Check logs with: multipass exec $VM_NAME -- sudo cat /var/log/cloud-init-output.log"
            return 1
        fi
        
        echo "  Waiting for cloud-init... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_fail "Timeout waiting for cloud-init"
    return 1
}

# Test Docker installation
test_docker_installation() {
    print_header "Testing Docker Installation"
    
    print_test "Docker daemon is running"
    DOCKER_STATUS=$(vm_exec_output systemctl is-active docker)
    if [ "$DOCKER_STATUS" = "active" ]; then
        print_pass "Docker daemon is active"
    else
        print_fail "Docker daemon is not running (status: $DOCKER_STATUS)"
        print_info "Check with: multipass exec $VM_NAME -- sudo systemctl status docker"
    fi
    
    print_test "Docker version"
    DOCKER_VERSION=$(vm_exec_output docker --version)
    if [ $? -eq 0 ]; then
        print_pass "$DOCKER_VERSION"
    else
        print_fail "Unable to get Docker version"
    fi
    
    print_test "Docker Compose version"
    COMPOSE_VERSION=$(vm_exec_output docker compose version)
    if [ $? -eq 0 ]; then
        print_pass "$COMPOSE_VERSION"
    else
        print_fail "Unable to get Docker Compose version"
    fi
    
    print_test "Containerd is running"
    CONTAINERD_STATUS=$(vm_exec_output systemctl is-active containerd)
    if [ "$CONTAINERD_STATUS" = "active" ]; then
        print_pass "Containerd is active"
    else
        print_fail "Containerd is not running (status: $CONTAINERD_STATUS)"
    fi
}

# Test Docker post-installation configuration
test_post_installation() {
    print_header "Testing Docker Post-Installation"
    
    print_test "Docker service enabled on boot"
    DOCKER_ENABLED=$(vm_exec_output systemctl is-enabled docker)
    if [ "$DOCKER_ENABLED" = "enabled" ]; then
        print_pass "Docker is enabled to start on boot"
    else
        print_fail "Docker is NOT enabled on boot"
        print_info "Fix with: multipass exec $VM_NAME -- sudo systemctl enable docker"
    fi
    
    print_test "Containerd service enabled on boot"
    CONTAINERD_ENABLED=$(vm_exec_output systemctl is-enabled containerd)
    if [ "$CONTAINERD_ENABLED" = "enabled" ]; then
        print_pass "Containerd is enabled to start on boot"
    else
        print_fail "Containerd is NOT enabled on boot"
        print_info "Fix with: multipass exec $VM_NAME -- sudo systemctl enable containerd"
    fi
    
    print_test "Live restore configuration"
    DAEMON_CONFIG=$(vm_exec_output sudo cat /etc/docker/daemon.json 2>/dev/null)
    SWARM_ACTIVE=$(vm_exec_output docker info 2>/dev/null | grep "Swarm:" | awk '{print $2}')
    if [ "$SWARM_ACTIVE" = "active" ]; then
        if echo "$DAEMON_CONFIG" | grep -q '"live-restore".*true'; then
            print_warn "Live restore is enabled but incompatible with Swarm mode"
            print_info "Remove 'live-restore' from daemon.json when using Swarm"
        else
            print_pass "Live restore correctly disabled (Swarm mode active)"
        fi
    else
        if echo "$DAEMON_CONFIG" | grep -q '"live-restore".*true'; then
            print_pass "Live restore is enabled (containers survive daemon restart)"
        else
            print_info "Live restore not enabled (optional, enable if not using Swarm)"
        fi
    fi
    
    print_test "Log rotation configured"
    if echo "$DAEMON_CONFIG" | grep -q '"max-size"'; then
        print_pass "Log rotation is configured"
    else
        print_warn "Log rotation not configured (logs may grow unbounded)"
    fi
    
    print_test "Storage driver set to overlay2"
    STORAGE_DRIVER=$(vm_exec_output docker info 2>/dev/null | grep "Storage Driver" | awk '{print $3}')
    if [ "$STORAGE_DRIVER" = "overlay2" ]; then
        print_pass "Storage driver is overlay2 (recommended)"
    else
        print_warn "Storage driver is '$STORAGE_DRIVER' (overlay2 recommended)"
    fi
    
    print_test "IP forwarding enabled"
    IP_FORWARD=$(vm_exec_output cat /proc/sys/net/ipv4/ip_forward)
    if [ "$IP_FORWARD" = "1" ]; then
        print_pass "IP forwarding is enabled"
    else
        print_fail "IP forwarding is disabled (required for Docker networking)"
        print_info "Fix with: sudo sysctl -w net.ipv4.ip_forward=1"
    fi
    
    print_test "Bridge netfilter enabled"
    if vm_exec test -f /proc/sys/net/bridge/bridge-nf-call-iptables; then
        BR_NETFILTER=$(vm_exec_output cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null)
        if [ "$BR_NETFILTER" = "1" ]; then
            print_pass "Bridge netfilter (iptables) is enabled"
        else
            print_warn "Bridge netfilter is disabled"
        fi
    else
        print_info "Bridge netfilter module not loaded (may be normal)"
    fi
    
    print_test "Default ulimits configured"
    if echo "$DAEMON_CONFIG" | grep -q '"nofile"'; then
        print_pass "Default ulimits are configured"
    else
        print_warn "Default ulimits not configured"
    fi
    
    print_test "Docker CLI config exists"
    if vm_exec test -f /home/ubuntu/.docker/config.json; then
        print_pass "Docker CLI config exists"
    else
        print_info "Docker CLI config not found (optional)"
    fi
    
    print_test "Bash completion for Docker"
    if vm_exec test -f /etc/bash_completion.d/docker; then
        print_pass "Docker bash completion is installed"
    else
        print_info "Docker bash completion not installed (optional)"
    fi
}

# Test permissions
test_permissions() {
    print_header "Testing Permissions"
    
    print_test "User 'ubuntu' is in docker group"
    if vm_exec_output groups ubuntu | grep -q docker; then
        print_pass "User 'ubuntu' is in docker group"
    else
        print_fail "User 'ubuntu' is NOT in docker group"
        print_info "Fix with: multipass exec $VM_NAME -- sudo usermod -aG docker ubuntu"
    fi
    
    print_test "Docker socket permissions"
    SOCKET_PERMS=$(vm_exec_output ls -la /var/run/docker.sock)
    if echo "$SOCKET_PERMS" | grep -q "docker"; then
        print_pass "Docker socket has correct group ownership"
        print_info "  $SOCKET_PERMS"
    else
        print_fail "Docker socket may have incorrect permissions"
        print_info "  $SOCKET_PERMS"
    fi
    
    print_test "Docker runs without sudo (as ubuntu user)"
    # More accurate test - check if docker ps works without permission error
    DOCKER_PS_RESULT=$(vm_exec_output docker ps 2>&1)
    if echo "$DOCKER_PS_RESULT" | grep -qi "permission denied\|cannot connect"; then
        print_fail "Docker requires sudo (permission issue)"
        print_info "The user may need to log out and back in, or run: newgrp docker"
    else
        print_pass "Docker runs without sudo"
    fi
    
    print_test "Home directory ownership"
    HOME_OWNER=$(vm_exec_output stat -c '%U:%G' /home/ubuntu 2>/dev/null)
    if [ "$HOME_OWNER" = "ubuntu:ubuntu" ]; then
        print_pass "Home directory has correct ownership ($HOME_OWNER)"
    else
        print_fail "Home directory has incorrect ownership ($HOME_OWNER)"
        print_info "Fix with: multipass exec $VM_NAME -- sudo chown -R ubuntu:ubuntu /home/ubuntu"
    fi
    
    print_test ".docker directory permissions"
    if vm_exec test -d /home/ubuntu/.docker; then
        DOCKER_DIR_OWNER=$(vm_exec_output stat -c '%U:%G' /home/ubuntu/.docker 2>/dev/null)
        if [ "$DOCKER_DIR_OWNER" = "ubuntu:ubuntu" ]; then
            print_pass ".docker directory has correct ownership"
        else
            print_fail ".docker directory has incorrect ownership ($DOCKER_DIR_OWNER)"
            print_info "Fix with: multipass exec $VM_NAME -- sudo chown -R ubuntu:ubuntu /home/ubuntu/.docker"
        fi
    else
        print_warn ".docker directory does not exist yet (will be created on first docker use)"
    fi
    
    print_test ".docker directory mode (should not be group/world writable)"
    if vm_exec test -d /home/ubuntu/.docker; then
        DOCKER_DIR_MODE=$(vm_exec_output stat -c '%a' /home/ubuntu/.docker 2>/dev/null)
        if [ "${DOCKER_DIR_MODE:1:1}" -le 5 ] && [ "${DOCKER_DIR_MODE:2:1}" -le 5 ]; then
            print_pass ".docker directory has secure permissions ($DOCKER_DIR_MODE)"
        else
            print_warn ".docker directory may have insecure permissions ($DOCKER_DIR_MODE)"
        fi
    fi
}

# Test Docker functionality
test_docker_functionality() {
    print_header "Testing Docker Functionality"
    
    print_test "Pull hello-world image"
    if vm_exec docker pull hello-world:linux; then
        print_pass "Successfully pulled hello-world image"
    else
        print_fail "Failed to pull hello-world image"
    fi
    
    print_test "Run hello-world container"
    if vm_exec docker run --rm hello-world:linux; then
        print_pass "Successfully ran hello-world container"
    else
        print_fail "Failed to run hello-world container"
    fi
    
    print_test "Create and write to volume"
    if vm_exec bash -c "docker run --rm -v test-vol:/data alpine:3.21 sh -c 'echo test > /data/test.txt && cat /data/test.txt'"; then
        print_pass "Volume read/write works correctly"
        # Cleanup
        vm_exec docker volume rm test-vol 2>/dev/null || true
    else
        print_fail "Volume read/write failed (possible permission issue)"
    fi
    
    print_test "Bind mount from home directory"
    vm_exec mkdir -p /home/ubuntu/test-mount
    vm_exec bash -c "echo 'test content' > /home/ubuntu/test-mount/test.txt"
    if vm_exec docker run --rm -v /home/ubuntu/test-mount:/data:ro alpine:3.21 cat /data/test.txt; then
        print_pass "Bind mount from home directory works"
    else
        print_fail "Bind mount failed (possible permission issue)"
    fi
    vm_exec rm -rf /home/ubuntu/test-mount 2>/dev/null || true
}

# Test Docker Swarm
test_docker_swarm() {
    print_header "Testing Docker Swarm"
    
    print_test "Docker Swarm is initialized"
    if vm_exec docker node ls; then
        print_pass "Docker Swarm is initialized"
        SWARM_INFO=$(vm_exec_output docker node ls | tail -1)
        print_info "  $SWARM_INFO"
    else
        print_warn "Docker Swarm is not initialized (optional)"
    fi
}

# Test network connectivity
test_network() {
    print_header "Testing Network"
    
    print_test "Internet connectivity from VM"
    if vm_exec ping -c 1 -W 5 8.8.8.8; then
        print_pass "VM has internet connectivity"
    else
        print_fail "VM cannot reach the internet"
    fi
    
    print_test "DNS resolution"
    if vm_exec ping -c 1 -W 5 docker.com; then
        print_pass "DNS resolution works"
    else
        print_fail "DNS resolution failed"
    fi
    
    print_test "Docker Hub connectivity"
    if vm_exec curl -s --connect-timeout 10 https://hub.docker.com; then
        print_pass "Can reach Docker Hub"
    else
        print_fail "Cannot reach Docker Hub"
    fi
}

# Test disk space
test_resources() {
    print_header "Testing Resources"
    
    print_test "Disk space available"
    DISK_INFO=$(vm_exec_output df -h / | tail -1)
    DISK_USED=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
    if [ "$DISK_USED" -lt 80 ]; then
        print_pass "Sufficient disk space available"
        print_info "  $DISK_INFO"
    elif [ "$DISK_USED" -lt 90 ]; then
        print_warn "Disk usage is high ($DISK_USED%)"
        print_info "  $DISK_INFO"
    else
        print_fail "Disk space critically low ($DISK_USED%)"
        print_info "  $DISK_INFO"
    fi
    
    print_test "Memory available"
    MEM_INFO=$(vm_exec_output free -h | grep "Mem:")
    print_pass "Memory info retrieved"
    print_info "  $MEM_INFO"
    
    print_test "Docker disk usage"
    DOCKER_DISK=$(vm_exec_output docker system df)
    print_pass "Docker disk usage retrieved"
    echo "$DOCKER_DISK" | while read line; do
        print_info "  $line"
    done
}

# Check for common issues
check_common_issues() {
    print_header "Checking Common Issues"
    
    print_test "Docker daemon.json is valid"
    DAEMON_JSON=$(vm_exec_output sudo cat /etc/docker/daemon.json 2>/dev/null)
    if echo "$DAEMON_JSON" | python3 -m json.tool >/dev/null 2>&1; then
        print_pass "daemon.json is valid JSON"
    else
        print_warn "daemon.json may be invalid or missing"
    fi
    
    print_test "No zombie containers"
    ZOMBIE_COUNT=$(vm_exec_output docker ps -a --filter "status=dead" -q | wc -l | tr -d ' ')
    if [ "$ZOMBIE_COUNT" -eq 0 ]; then
        print_pass "No zombie/dead containers"
    else
        print_warn "$ZOMBIE_COUNT dead containers found"
        print_info "Clean with: multipass exec $VM_NAME -- docker container prune -f"
    fi
    
    print_test "No dangling images"
    DANGLING_COUNT=$(vm_exec_output docker images -f "dangling=true" -q | wc -l | tr -d ' ')
    if [ "$DANGLING_COUNT" -eq 0 ]; then
        print_pass "No dangling images"
    else
        print_warn "$DANGLING_COUNT dangling images found"
        print_info "Clean with: multipass exec $VM_NAME -- docker image prune -f"
    fi
}

# Print summary
print_summary() {
    print_header "Test Summary"
    
    TOTAL=$((TEST_PASSED + TEST_FAILED))
    
    echo ""
    echo -e "  ${GREEN}Passed:${NC} $TEST_PASSED"
    echo -e "  ${RED}Failed:${NC} $TEST_FAILED"
    echo -e "  ${BLUE}Total:${NC}  $TOTAL"
    echo ""
    
    if [ $TEST_FAILED -eq 0 ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  ✔ All tests passed! VM is ready to use.${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        return 0
    else
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  ✘ Some tests failed. Please review the issues above.${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Docker VM Test Suite                           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    
    check_multipass
    
    if ! check_vm_exists; then
        echo ""
        echo "Would you like to create the VM now? (y/n)"
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            print_info "Creating VM '$VM_NAME'..."
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if multipass launch --name "$VM_NAME" --cloud-init "$SCRIPT_DIR/docker.yaml" --cpus 2 --memory 4G --disk 20G; then
                print_pass "VM created successfully"
            else
                print_fail "Failed to create VM"
                exit 1
            fi
        else
            exit 1
        fi
    fi
    
    check_vm_state || exit 1
    wait_for_cloud_init  # Continue even if cloud-init had errors
    
    test_docker_installation
    test_post_installation
    test_permissions
    test_docker_functionality
    test_docker_swarm
    test_network
    test_resources
    check_common_issues
    
    print_summary
}

# Run main function
main "$@"
