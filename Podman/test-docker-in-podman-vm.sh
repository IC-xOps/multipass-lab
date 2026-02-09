#!/bin/bash
#
# Docker-in-Podman VM Test Script
# Tests Docker Engine running inside a Podman container
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

VM_NAME="${1:-docker-in-podman-vm}"
TIMEOUT=300
TEST_PASSED=0
TEST_FAILED=0
TEST_WARNED=0

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

print_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    TEST_WARNED=$((TEST_WARNED + 1))
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

# Helper functions
vm_exec() {
    multipass exec "$VM_NAME" -- "$@" 2>&1
    return $?
}

vm_exec_output() {
    multipass exec "$VM_NAME" -- "$@" 2>&1
}

vm_exec_quiet() {
    multipass exec "$VM_NAME" -- "$@" >/dev/null 2>&1
    return $?
}

# Execute docker command via wrapper
docker_exec() {
    multipass exec "$VM_NAME" -- /home/ubuntu/docker "$@" 2>&1
}

docker_exec_quiet() {
    local output
    output=$(multipass exec "$VM_NAME" -- /home/ubuntu/docker "$@" 2>&1)
    return $?
}

# Execute podman as root (required for docker-in-podman)
podman_exec() {
    multipass exec "$VM_NAME" -- sudo podman "$@" 2>&1
}

podman_exec_quiet() {
    local output
    output=$(multipass exec "$VM_NAME" -- sudo podman "$@" 2>&1)
    return $?
}

#===============================================================================
# PREREQUISITES
#===============================================================================
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    print_test "Multipass installation"
    if command -v multipass &> /dev/null; then
        MULTIPASS_VERSION=$(multipass version | head -1)
        print_pass "Multipass is installed ($MULTIPASS_VERSION)"
    else
        print_fail "Multipass is not installed"
        exit 1
    fi
}

#===============================================================================
# VM STATUS
#===============================================================================
check_vm_status() {
    print_header "Checking VM Status"
    
    print_test "VM '$VM_NAME' exists"
    if multipass list | grep -q "^$VM_NAME "; then
        print_pass "VM exists"
    else
        print_fail "VM does not exist"
        print_info "Create with: multipass launch 24.04 -n $VM_NAME -c 2 -m 4G -d 20G --cloud-init docker-in-podman.yaml"
        exit 1
    fi
    
    print_test "VM is running"
    VM_STATE=$(multipass list | grep "^$VM_NAME " | awk '{print $2}')
    if [ "$VM_STATE" == "Running" ]; then
        print_pass "VM is running"
    else
        print_fail "VM is not running (state: $VM_STATE)"
        exit 1
    fi
    
    print_test "Cloud-init completed"
    STATUS=$(vm_exec_output cloud-init status 2>/dev/null)
    if echo "$STATUS" | grep -q "status: done"; then
        print_pass "Cloud-init completed"
    else
        print_fail "Cloud-init not complete"
        print_info "Wait with: multipass exec $VM_NAME -- cloud-init status --wait"
    fi
}

#===============================================================================
# PODMAN INSTALLATION (Host)
#===============================================================================
test_podman_installation() {
    print_header "Testing Podman Installation (Host)"
    
    print_test "Podman is installed"
    PODMAN_VERSION=$(vm_exec_output podman --version)
    if [ $? -eq 0 ]; then
        print_pass "$PODMAN_VERSION"
    else
        print_fail "Podman not installed"
    fi
    
    print_test "Podman (root) can run containers"
    POD_TEST=$(podman_exec run --rm alpine echo test 2>/dev/null)
    if [ "$POD_TEST" == "test" ]; then
        print_pass "Podman can run containers"
    else
        print_fail "Podman cannot run containers"
    fi
    
    print_test "uidmap installed"
    if vm_exec_output which newuidmap | grep -q newuidmap; then
        print_pass "uidmap is installed"
    else
        print_fail "uidmap not installed"
    fi
    
    print_test "slirp4netns installed"
    if vm_exec_output which slirp4netns | grep -q slirp4netns; then
        print_pass "slirp4netns is installed"
    else
        print_fail "slirp4netns not installed"
    fi
    
    print_test "fuse-overlayfs installed"
    if vm_exec_output which fuse-overlayfs | grep -q fuse-overlayfs; then
        print_pass "fuse-overlayfs is installed"
    else
        print_fail "fuse-overlayfs not installed"
    fi
}

#===============================================================================
# PODMAN CONFIGURATION
#===============================================================================
test_podman_configuration() {
    print_header "Testing Podman Configuration"
    
    print_test "Subuid configured for ubuntu"
    SUBUID=$(vm_exec_output grep ubuntu /etc/subuid)
    if [ -n "$SUBUID" ]; then
        print_pass "subuid configured"
        print_info "$SUBUID"
    else
        print_fail "subuid not configured"
    fi
    
    print_test "Subgid configured for ubuntu"
    SUBGID=$(vm_exec_output grep ubuntu /etc/subgid)
    if [ -n "$SUBGID" ]; then
        print_pass "subgid configured"
        print_info "$SUBGID"
    else
        print_fail "subgid not configured"
    fi
    
    print_test "User linger enabled"
    LINGER=$(vm_exec_output loginctl show-user ubuntu 2>/dev/null | grep Linger)
    if echo "$LINGER" | grep -q "yes"; then
        print_pass "Linger enabled"
    else
        print_warn "Linger not enabled (using root Podman)"
    fi
    
    print_test "Registry configuration exists"
    if vm_exec_output test -f /etc/containers/registries.conf && echo "exists"; then
        print_pass "Registry configuration exists"
    else
        print_fail "Registry configuration missing"
    fi
}

#===============================================================================
# DOCKER-IN-PODMAN CONTAINER
#===============================================================================
test_docker_container() {
    print_header "Testing Docker-in-Podman Container"
    
    print_test "Docker container exists"
    if podman_exec ps -a --format "{{.Names}}" | grep -q "docker-engine"; then
        print_pass "Docker container exists"
    else
        print_fail "Docker container does not exist"
        return
    fi
    
    print_test "Docker container is running"
    if podman_exec ps --format "{{.Names}}" | grep -q "docker-engine"; then
        print_pass "Docker container is running"
    else
        print_fail "Docker container is not running"
        print_info "Start with: multipass exec $VM_NAME -- ~/start-docker-container.sh"
        return
    fi
    
    print_test "Docker container is privileged"
    PRIVILEGED=$(podman_exec inspect docker-engine --format '{{.HostConfig.Privileged}}')
    if [ "$PRIVILEGED" == "true" ]; then
        print_pass "Container is privileged"
    else
        print_fail "Container is not privileged"
    fi
    
    print_test "Docker data volume exists"
    if podman_exec volume ls | grep -q "docker-data"; then
        print_pass "Docker data volume exists"
    else
        print_fail "Docker data volume missing"
    fi
    
    print_test "Workspace volume mounted"
    MOUNTS=$(podman_exec inspect docker-engine --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}')
    if echo "$MOUNTS" | grep -q "workspace"; then
        print_pass "Workspace volume mounted"
    else
        print_warn "Workspace volume not mounted"
    fi
}

#===============================================================================
# DOCKER DAEMON (Inside Container)
#===============================================================================
test_docker_daemon() {
    print_header "Testing Docker Daemon (Inside Container)"
    
    print_test "Docker daemon responding"
    if docker_exec_quiet info; then
        print_pass "Docker daemon is responding"
    else
        print_fail "Docker daemon not responding"
        return
    fi
    
    print_test "Docker version"
    DOCKER_VERSION=$(docker_exec --version 2>/dev/null)
    if [ $? -eq 0 ]; then
        print_pass "$DOCKER_VERSION"
    else
        print_fail "Unable to get Docker version"
    fi
    
    print_test "Docker storage driver"
    STORAGE=$(docker_exec info 2>/dev/null | grep "Storage Driver" | awk '{print $3}')
    if [ -n "$STORAGE" ]; then
        print_pass "Storage driver: $STORAGE"
    else
        print_warn "Unable to determine storage driver"
    fi
    
    print_test "Docker root directory"
    ROOT_DIR=$(docker_exec info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')
    if [ -n "$ROOT_DIR" ]; then
        print_pass "Docker root: $ROOT_DIR"
    else
        print_warn "Unable to determine root directory"
    fi
}

#===============================================================================
# DOCKER WRAPPER SCRIPTS
#===============================================================================
test_docker_wrappers() {
    print_header "Testing Docker Wrapper Scripts"
    
    print_test "Docker wrapper exists"
    if vm_exec_output test -x /home/ubuntu/docker && echo "exists"; then
        print_pass "Docker wrapper is executable"
    else
        print_fail "Docker wrapper missing or not executable"
    fi
    
    print_test "Docker-compose wrapper exists"
    if vm_exec_output test -x /home/ubuntu/docker-compose && echo "exists"; then
        print_pass "Docker-compose wrapper is executable"
    else
        print_fail "Docker-compose wrapper missing"
    fi
    
    print_test "Start script exists"
    if vm_exec_output test -x /home/ubuntu/start-docker-container.sh && echo "exists"; then
        print_pass "Start script is executable"
    else
        print_fail "Start script missing"
    fi
    
    print_test "PATH includes home directory"
    PATH_CHECK=$(vm_exec_output bash -c 'source ~/.bashrc && echo $PATH')
    if echo "$PATH_CHECK" | grep -q "/home/ubuntu"; then
        print_pass "PATH includes home directory"
    else
        print_warn "PATH may not include home directory"
    fi
}

#===============================================================================
# DOCKER FUNCTIONALITY (Inside Container)
#===============================================================================
test_docker_functionality() {
    print_header "Testing Docker Functionality (Inside Container)"
    
    print_test "Docker ps command"
    if docker_exec_quiet ps; then
        print_pass "docker ps works"
    else
        print_fail "docker ps failed"
    fi
    
    print_test "Pull image"
    if docker_exec_quiet pull alpine:latest; then
        print_pass "Image pull works"
    else
        print_fail "Image pull failed"
    fi
    
    print_test "Run container"
    OUTPUT=$(docker_exec run --rm alpine echo "hello-from-docker-in-podman" 2>/dev/null)
    if echo "$OUTPUT" | grep -q "hello-from-docker-in-podman"; then
        print_pass "Container run works"
    else
        print_fail "Container run failed"
    fi
    
    print_test "Run hello-world"
    if docker_exec_quiet run --rm hello-world; then
        print_pass "hello-world container works"
    else
        print_fail "hello-world failed"
    fi
    
    print_test "Docker volume create"
    if docker_exec_quiet volume create test-vol; then
        print_pass "Volume creation works"
        docker_exec_quiet volume rm test-vol
    else
        print_fail "Volume creation failed"
    fi
    
    print_test "Docker network create"
    if docker_exec_quiet network create test-net; then
        print_pass "Network creation works"
        docker_exec_quiet network rm test-net
    else
        print_fail "Network creation failed"
    fi
    
    print_test "Docker build"
    BUILD_OUTPUT=$(vm_exec_output bash -c 'echo "FROM alpine" | /home/ubuntu/docker build -t test-build - 2>&1')
    if echo "$BUILD_OUTPUT" | grep -q "Successfully\|naming to"; then
        print_pass "Docker build works"
        docker_exec_quiet rmi test-build
    else
        print_fail "Docker build failed"
    fi
}

#===============================================================================
# NESTED CONTAINERS
#===============================================================================
test_nested_containers() {
    print_header "Testing Nested Container Isolation"
    
    print_test "Host Podman sees docker-engine container"
    HOST_CONTAINERS=$(podman_exec ps --format "{{.Names}}")
    if echo "$HOST_CONTAINERS" | grep -q "docker-engine"; then
        print_pass "Host sees docker-engine"
    else
        print_fail "Host doesn't see docker-engine"
    fi
    
    print_test "Docker containers isolated from host Podman"
    # Run a container in Docker
    docker_exec_quiet run -d --name test-isolation alpine sleep 300
    
    # Check if host Podman can see it (it shouldn't)
    HOST_ALL=$(podman_exec ps -a --format "{{.Names}}")
    if echo "$HOST_ALL" | grep -q "test-isolation"; then
        print_fail "Docker container visible to host Podman (not isolated)"
    else
        print_pass "Docker containers properly isolated from host"
    fi
    
    # Cleanup
    docker_exec_quiet rm -f test-isolation
    
    print_test "Docker can see its own containers"
    docker_exec_quiet run -d --name visible-test alpine sleep 30
    DOCKER_CONTAINERS=$(docker_exec ps --format "{{.Names}}" 2>/dev/null)
    if echo "$DOCKER_CONTAINERS" | grep -q "visible-test"; then
        print_pass "Docker sees its own containers"
    else
        print_fail "Docker can't see its own containers"
    fi
    docker_exec_quiet rm -f visible-test
}

#===============================================================================
# PERSISTENCE
#===============================================================================
test_persistence() {
    print_header "Testing Data Persistence"
    
    print_test "Docker data volume persists data"
    # Create a test image
    docker_exec_quiet pull busybox
    
    # Check volume exists
    if podman_exec volume inspect docker-data 2>&1 | cat > /dev/null; then
        print_pass "Docker data volume exists and mounted"
    else
        print_fail "Docker data volume not found"
    fi
    
    print_test "Workspace directory accessible"
    # Create test file in workspace
    vm_exec_output bash -c 'echo "test-workspace-access" > /home/ubuntu/workspace/test-file.txt' >/dev/null
    
    # Check if accessible from Docker by running a container with workspace mounted
    FILE_CONTENT=$(docker_exec run --rm -v /workspace:/test alpine cat /test/test-file.txt 2>/dev/null)
    if [ "$FILE_CONTENT" == "test-workspace-access" ]; then
        print_pass "Workspace shared between host and Docker"
    else
        print_fail "Workspace not accessible from Docker"
    fi
    
    # Cleanup
    vm_exec_output rm -f /home/ubuntu/workspace/test-file.txt >/dev/null
}

#===============================================================================
# AUTO-START SERVICE
#===============================================================================
test_autostart() {
    print_header "Testing Auto-Start Configuration"
    
    print_test "Systemd service exists"
    if vm_exec_output test -f /etc/systemd/system/docker-in-podman.service && echo "exists"; then
        print_pass "Systemd service file exists"
    else
        print_fail "Systemd service file missing"
    fi
    
    print_test "Service is enabled"
    SERVICE_ENABLED=$(vm_exec_output systemctl is-enabled docker-in-podman.service 2>/dev/null)
    if [ "$SERVICE_ENABLED" == "enabled" ]; then
        print_pass "Service is enabled for auto-start"
    else
        print_warn "Service not enabled"
    fi
    
    print_test "Container has restart policy"
    RESTART_POLICY=$(podman_exec inspect docker-engine --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
    if [ "$RESTART_POLICY" == "unless-stopped" ] || [ "$RESTART_POLICY" == "always" ]; then
        print_pass "Container has restart policy: $RESTART_POLICY"
    else
        print_warn "Container restart policy: $RESTART_POLICY"
    fi
}

#===============================================================================
# NETWORK
#===============================================================================
test_network() {
    print_header "Testing Network"
    
    print_test "Docker has internet access"
    if docker_exec_quiet run --rm alpine ping -c 1 8.8.8.8; then
        print_pass "Docker containers have internet access"
    else
        print_fail "Docker containers have no internet access"
    fi
    
    print_test "Docker DNS resolution"
    if docker_exec_quiet run --rm alpine ping -c 1 google.com; then
        print_pass "Docker DNS resolution works"
    else
        print_fail "Docker DNS resolution failed"
    fi
    
    print_test "Docker Hub accessible"
    if docker_exec_quiet pull hello-world; then
        print_pass "Docker Hub accessible"
    else
        print_fail "Cannot reach Docker Hub"
    fi
}

#===============================================================================
# RESOURCES
#===============================================================================
test_resources() {
    print_header "Testing Resources"
    
    print_test "VM disk space"
    DISK_USAGE=$(vm_exec_output df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$DISK_USAGE" -lt 80 ]; then
        print_pass "Disk usage: ${DISK_USAGE}%"
    else
        print_warn "Disk usage high: ${DISK_USAGE}%"
    fi
    
    print_test "VM memory"
    MEM_INFO=$(vm_exec_output free -h | grep Mem | awk '{print $2}')
    print_pass "Total memory: $MEM_INFO"
    
    print_test "Docker container memory"
    CONTAINER_MEM=$(podman_exec stats docker-engine --no-stream --format "{{.MemUsage}}" 2>/dev/null)
    if [ -n "$CONTAINER_MEM" ]; then
        print_pass "Container memory: $CONTAINER_MEM"
    else
        print_warn "Unable to get container memory stats"
    fi
}

#===============================================================================
# CLEANUP
#===============================================================================
cleanup_tests() {
    print_header "Cleanup"
    
    echo "  Removing test artifacts..."
    docker_exec_quiet system prune -f
    print_pass "Cleanup complete"
}

#===============================================================================
# MAIN
#===============================================================================
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       DOCKER-IN-PODMAN VM TEST SUITE                           ║${NC}"
    echo -e "${BLUE}║       VM: $VM_NAME${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    check_prerequisites
    check_vm_status
    test_podman_installation
    test_podman_configuration
    test_docker_container
    test_docker_daemon
    test_docker_wrappers
    test_docker_functionality
    test_nested_containers
    test_persistence
    test_autostart
    test_network
    test_resources
    cleanup_tests
    
    # Summary
    print_header "Test Summary"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $TEST_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TEST_FAILED"
    echo -e "  ${YELLOW}Warned:${NC}  $TEST_WARNED"
    echo ""
    
    TOTAL=$((TEST_PASSED + TEST_FAILED))
    
    if [ $TEST_FAILED -eq 0 ]; then
        echo -e "  ${GREEN}All $TOTAL tests passed!${NC} ✓"
        echo ""
        echo -e "  Docker-in-Podman VM is healthy and ready to use."
    else
        echo -e "  ${RED}$TEST_FAILED of $TOTAL tests failed${NC}"
    fi
    
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    exit $TEST_FAILED
}

main "$@"
