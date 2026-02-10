#!/bin/bash
#
# Podman VM Test Script
# Tests if the podman-vm starts correctly and checks for permission issues
#

# Don't use set -e as it interferes with test logic and counter increments

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

VM_NAME="podman-vm"
TIMEOUT=300  # 5 minutes timeout for VM to be ready
TEST_PASSED=0
TEST_FAILED=0

# Print functions
print_header() {
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
        print_info "Create it with: multipass launch --name $VM_NAME --cloud-init podman.yaml"
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

# Test Podman installation
test_podman_installation() {
    print_header "Testing Podman Installation"
    
    print_test "Podman is installed"
    PODMAN_VERSION=$(vm_exec_output podman --version)
    if [ $? -eq 0 ]; then
        print_pass "$PODMAN_VERSION"
    else
        print_fail "Podman is not installed"
    fi
    
    print_test "Podman-docker compatibility layer"
    if vm_exec which docker | grep -q "/usr/bin/docker"; then
        print_pass "podman-docker is installed (docker alias available)"
    else
        print_warn "podman-docker not installed (optional)"
    fi
    
    print_test "slirp4netns (rootless networking)"
    if vm_exec which slirp4netns; then
        print_pass "slirp4netns is installed"
    else
        print_fail "slirp4netns is not installed (required for rootless)"
    fi
    
    print_test "fuse-overlayfs (rootless storage)"
    if vm_exec which fuse-overlayfs; then
        print_pass "fuse-overlayfs is installed"
    else
        print_fail "fuse-overlayfs is not installed (required for rootless)"
    fi
    
    print_test "uidmap (newuidmap/newgidmap)"
    if vm_exec which newuidmap && vm_exec which newgidmap; then
        print_pass "uidmap tools are installed"
    else
        print_fail "uidmap tools are not installed (required for rootless)"
    fi
}

# Test Podman post-installation configuration
test_post_installation() {
    print_header "Testing Podman Post-Installation"
    
    print_test "Subuid configured for ubuntu"
    SUBUID=$(vm_exec_output grep ubuntu /etc/subuid)
    if [ -n "$SUBUID" ]; then
        print_pass "Subuid configured: $SUBUID"
    else
        print_fail "Subuid not configured for ubuntu"
        print_info "Fix with: sudo usermod --add-subuids 100000-165535 ubuntu"
    fi
    
    print_test "Subgid configured for ubuntu"
    SUBGID=$(vm_exec_output grep ubuntu /etc/subgid)
    if [ -n "$SUBGID" ]; then
        print_pass "Subgid configured: $SUBGID"
    else
        print_fail "Subgid not configured for ubuntu"
        print_info "Fix with: sudo usermod --add-subgids 100000-165535 ubuntu"
    fi
    
    print_test "User linger enabled"
    if vm_exec test -f /var/lib/systemd/linger/ubuntu; then
        print_pass "Linger enabled for ubuntu user"
    else
        print_fail "Linger not enabled (user services won't persist)"
        print_info "Fix with: sudo loginctl enable-linger ubuntu"
    fi
    
    print_test "Container registries configured"
    if vm_exec test -f /etc/containers/registries.conf; then
        if vm_exec_output cat /etc/containers/registries.conf | grep -q "docker.io"; then
            print_pass "Container registries configured (docker.io included)"
        else
            print_warn "Container registries file exists but docker.io not configured"
        fi
    else
        print_fail "Container registries not configured"
    fi
    
    print_test "User containers.conf exists"
    if vm_exec test -f /home/ubuntu/.config/containers/containers.conf; then
        print_pass "User containers.conf exists"
    else
        print_info "User containers.conf not found (optional)"
    fi
    
    print_test "Cgroup manager set to systemd"
    CGROUP_MGR=$(vm_exec_output podman info --format '{{.Host.CgroupManager}}' 2>/dev/null)
    if [ "$CGROUP_MGR" = "systemd" ]; then
        print_pass "Cgroup manager is systemd"
    else
        print_warn "Cgroup manager is '$CGROUP_MGR' (systemd recommended)"
    fi
}

# Test permissions
test_permissions() {
    print_header "Testing Permissions"
    
    print_test "Home directory ownership"
    HOME_OWNER=$(vm_exec_output stat -c '%U:%G' /home/ubuntu 2>/dev/null)
    if [ "$HOME_OWNER" = "ubuntu:ubuntu" ]; then
        print_pass "Home directory has correct ownership ($HOME_OWNER)"
    else
        print_fail "Home directory has incorrect ownership ($HOME_OWNER)"
        print_info "Fix with: multipass exec $VM_NAME -- sudo chown -R ubuntu:ubuntu /home/ubuntu"
    fi
    
    print_test ".config directory ownership"
    if vm_exec test -d /home/ubuntu/.config; then
        CONFIG_OWNER=$(vm_exec_output stat -c '%U:%G' /home/ubuntu/.config 2>/dev/null)
        if [ "$CONFIG_OWNER" = "ubuntu:ubuntu" ]; then
            print_pass ".config directory has correct ownership"
        else
            print_fail ".config directory has incorrect ownership ($CONFIG_OWNER)"
        fi
    else
        print_fail ".config directory does not exist"
    fi
    
    print_test ".local directory ownership"
    if vm_exec test -d /home/ubuntu/.local; then
        LOCAL_OWNER=$(vm_exec_output stat -c '%U:%G' /home/ubuntu/.local 2>/dev/null)
        if [ "$LOCAL_OWNER" = "ubuntu:ubuntu" ]; then
            print_pass ".local directory has correct ownership"
        else
            print_fail ".local directory has incorrect ownership ($LOCAL_OWNER)"
        fi
    else
        print_fail ".local directory does not exist"
    fi
    
    print_test "XDG_RUNTIME_DIR exists"
    XDG_RUNTIME=$(vm_exec_output bash -c 'echo $XDG_RUNTIME_DIR')
    if vm_exec test -d /run/user/1000; then
        print_pass "XDG_RUNTIME_DIR exists (/run/user/1000)"
    else
        print_warn "XDG_RUNTIME_DIR may not be set up correctly"
    fi
    
    print_test "Podman runs rootless (as ubuntu)"
    PODMAN_USER=$(vm_exec_output podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)
    if [ "$PODMAN_USER" = "true" ]; then
        print_pass "Podman is running rootless"
    else
        print_warn "Podman is running as root"
    fi
}

# Test Podman sockets
test_sockets() {
    print_header "Testing Podman Sockets"
    
    print_test "User podman.socket enabled"
    SOCKET_STATUS=$(vm_exec_output systemctl --user is-enabled podman.socket 2>/dev/null)
    if [ "$SOCKET_STATUS" = "enabled" ]; then
        print_pass "User podman.socket is enabled"
    else
        print_warn "User podman.socket is not enabled"
        print_info "Enable with: systemctl --user enable podman.socket"
    fi
    
    print_test "User podman.socket active"
    SOCKET_ACTIVE=$(vm_exec_output systemctl --user is-active podman.socket 2>/dev/null)
    if [ "$SOCKET_ACTIVE" = "active" ]; then
        print_pass "User podman.socket is active"
    else
        print_warn "User podman.socket is not active"
        print_info "Start with: systemctl --user start podman.socket"
    fi
    
    print_test "User socket file exists"
    if vm_exec test -S /run/user/1000/podman/podman.sock; then
        print_pass "User socket exists at /run/user/1000/podman/podman.sock"
    else
        print_warn "User socket not found (may need to be activated)"
    fi
    
    print_test "System podman.socket enabled"
    SYS_SOCKET_STATUS=$(vm_exec_output sudo systemctl is-enabled podman.socket 2>/dev/null)
    if [ "$SYS_SOCKET_STATUS" = "enabled" ]; then
        print_pass "System podman.socket is enabled"
    else
        print_info "System podman.socket is not enabled (optional)"
    fi
    
    print_test "System podman.socket active"
    SYS_SOCKET_ACTIVE=$(vm_exec_output sudo systemctl is-active podman.socket 2>/dev/null)
    if [ "$SYS_SOCKET_ACTIVE" = "active" ]; then
        print_pass "System podman.socket is active"
    else
        print_info "System podman.socket is not active (optional)"
    fi
}

# Test Podman functionality
test_podman_functionality() {
    print_header "Testing Podman Functionality"
    
    print_test "Pull hello-world image"
    if vm_exec podman pull hello-world:linux; then
        print_pass "Successfully pulled hello-world image"
    else
        print_fail "Failed to pull hello-world image"
    fi
    
    print_test "Run hello-world container"
    if vm_exec podman run --rm hello-world:linux; then
        print_pass "Successfully ran hello-world container"
    else
        print_fail "Failed to run hello-world container"
    fi
    
    print_test "Create and write to volume"
    if vm_exec bash -c "podman run --rm -v test-vol:/data alpine:3.21 sh -c 'echo test > /data/test.txt && cat /data/test.txt'"; then
        print_pass "Volume read/write works correctly"
        # Cleanup
        vm_exec podman volume rm test-vol 2>/dev/null || true
    else
        print_fail "Volume read/write failed"
    fi
    
    print_test "Bind mount from home directory"
    vm_exec mkdir -p /home/ubuntu/test-mount
    vm_exec bash -c "echo 'test content' > /home/ubuntu/test-mount/test.txt"
    if vm_exec podman run --rm -v /home/ubuntu/test-mount:/data:ro alpine:3.21 cat /data/test.txt; then
        print_pass "Bind mount from home directory works"
    else
        print_fail "Bind mount failed (possible permission issue)"
    fi
    vm_exec rm -rf /home/ubuntu/test-mount 2>/dev/null || true
    
    print_test "Port mapping works"
    vm_exec podman run -d --name test-nginx -p 8888:80 nginx:1.28.2-alpine3.23 2>/dev/null
    sleep 2
    if vm_exec curl -s --connect-timeout 5 http://localhost:8888 | grep -q "nginx\|Welcome"; then
        print_pass "Port mapping works correctly"
    else
        print_warn "Port mapping test inconclusive"
    fi
    vm_exec podman rm -f test-nginx 2>/dev/null || true
}

# Test Docker compatibility
test_docker_compatibility() {
    print_header "Testing Docker Compatibility"
    
    print_test "Docker command available (via podman-docker)"
    if vm_exec which docker; then
        print_pass "Docker command is available"
    else
        print_info "Docker command not available (podman-docker not installed)"
        return
    fi
    
    print_test "Docker CLI works with Podman"
    DOCKER_VERSION=$(vm_exec_output docker --version 2>/dev/null)
    if echo "$DOCKER_VERSION" | grep -qi "podman"; then
        print_pass "Docker CLI redirects to Podman"
    else
        print_info "Docker CLI output: $DOCKER_VERSION"
    fi
    
    print_test "Docker run works"
    if vm_exec docker run --rm hello-world:linux; then
        print_pass "Docker run command works via Podman"
    else
        print_fail "Docker run command failed"
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
    if vm_exec getent hosts docker.io; then
        print_pass "DNS resolution works"
    else
        print_fail "DNS resolution failed"
    fi
    
    print_test "Container registry connectivity (docker.io)"
    if vm_exec curl -s --connect-timeout 10 https://registry-1.docker.io/v2/; then
        print_pass "Can reach Docker registry"
    else
        print_warn "Cannot reach Docker registry directly"
    fi
    
    print_test "Container registry connectivity (quay.io)"
    if vm_exec curl -s --connect-timeout 10 https://quay.io; then
        print_pass "Can reach Quay.io registry"
    else
        print_warn "Cannot reach Quay.io registry"
    fi
}

# Test resources
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
    
    print_test "Podman storage info"
    PODMAN_STORAGE=$(vm_exec_output podman system df 2>/dev/null)
    if [ $? -eq 0 ]; then
        print_pass "Podman storage info retrieved"
        echo "$PODMAN_STORAGE" | while read line; do
            print_info "  $line"
        done
    else
        print_info "No Podman storage data yet"
    fi
}

# Check for common issues
check_common_issues() {
    print_header "Checking Common Issues"
    
    print_test "No zombie containers"
    ZOMBIE_COUNT=$(vm_exec_output podman ps -a --filter "status=dead" -q 2>/dev/null | wc -l | tr -d ' ')
    if [ "$ZOMBIE_COUNT" -eq 0 ]; then
        print_pass "No zombie/dead containers"
    else
        print_warn "$ZOMBIE_COUNT dead containers found"
        print_info "Clean with: podman container prune -f"
    fi
    
    print_test "No dangling images"
    DANGLING_COUNT=$(vm_exec_output podman images -f "dangling=true" -q 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DANGLING_COUNT" -eq 0 ]; then
        print_pass "No dangling images"
    else
        print_warn "$DANGLING_COUNT dangling images found"
        print_info "Clean with: podman image prune -f"
    fi
    
    print_test "Rootless storage driver"
    STORAGE_DRIVER=$(vm_exec_output podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null)
    if [ "$STORAGE_DRIVER" = "overlay" ]; then
        print_pass "Storage driver is overlay (optimal)"
    elif [ "$STORAGE_DRIVER" = "vfs" ]; then
        print_warn "Storage driver is vfs (slower, but works)"
    else
        print_info "Storage driver is '$STORAGE_DRIVER'"
    fi
    
    print_test "OCI runtime"
    OCI_RUNTIME=$(vm_exec_output podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null)
    if [ -n "$OCI_RUNTIME" ]; then
        print_pass "OCI runtime: $OCI_RUNTIME"
    else
        print_warn "Could not determine OCI runtime"
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
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║           Podman VM Test Suite                           ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    
    check_multipass
    
    if ! check_vm_exists; then
        echo ""
        echo "Would you like to create the VM now? (y/n)"
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            print_info "Creating VM '$VM_NAME'..."
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if multipass launch --name "$VM_NAME" --cloud-init "$SCRIPT_DIR/podman.yaml" --cpus 2 --memory 4G --disk 20G; then
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
    
    test_podman_installation
    test_post_installation
    test_permissions
    test_sockets
    test_podman_functionality
    test_docker_compatibility
    test_network
    test_resources
    check_common_issues
    
    print_summary
}

# Run main function
main "$@"
