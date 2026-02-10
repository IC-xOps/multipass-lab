#!/bin/bash

#===============================================================================
# Docker Rootless VM Test Script
# 
# Tests: VM accessibility, Docker rootless installation, permissions, 
#        functionality, and rootless-specific features
#
# Usage: ./test-docker-rootless-vm.sh [vm-name]
# Default VM name: docker-rootless-vm
#===============================================================================

VM_NAME="${1:-docker-rootless-vm}"

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
# Helper Functions for VM Execution
#-------------------------------------------------------------------------------
vm_exec() {
    # Execute command in VM without capturing output (for tests that check exit code)
    local result
    result=$(multipass exec "$VM_NAME" -- bash -c "$1" 2>&1)
    return $?
}

vm_exec_output() {
    # Execute command in VM and capture output
    multipass exec "$VM_NAME" -- bash -c "$1" 2>&1
}

# Execute as ubuntu user with proper rootless environment
vm_exec_rootless() {
    local result
    result=$(multipass exec "$VM_NAME" -- bash -c "export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/docker.sock; $1" 2>&1)
    return $?
}

vm_exec_rootless_output() {
    multipass exec "$VM_NAME" -- bash -c "export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/docker.sock; $1" 2>&1
}

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
    local state
    state=$(multipass info "$VM_NAME" 2>/dev/null | grep "State:" | awk '{print $2}')
    if [ "$state" = "Running" ]; then
        pass
    else
        fail "VM state is: $state"
        echo -e "${RED}VM is not running. Exiting.${NC}"
        exit 1
    fi
    
    # Check shell access
    print_test "Shell access available"
    if vm_exec "echo 'test'"; then
        pass
    else
        fail "Cannot execute commands in VM"
        exit 1
    fi
    
    # Get VM info
    local vm_ip
    vm_ip=$(multipass info "$VM_NAME" 2>/dev/null | grep "IPv4:" | awk '{print $2}')
    info "VM IP: $vm_ip"
}

#-------------------------------------------------------------------------------
# Test: Docker Rootless Installation
#-------------------------------------------------------------------------------
test_docker_rootless_installation() {
    print_header "Docker Rootless Installation Tests"
    
    # Check Docker CLI is installed
    print_test "Docker CLI installed"
    if vm_exec "which docker"; then
        pass
        local docker_version
        docker_version=$(vm_exec_output "docker --version")
        info "$docker_version"
    else
        fail "Docker CLI not found"
    fi
    
    # Check rootless extras installed
    print_test "Docker rootless extras installed"
    if vm_exec "dpkg -l | grep -q docker-ce-rootless-extras"; then
        pass
    else
        fail "docker-ce-rootless-extras package not installed"
    fi
    
    # Check dockerd-rootless-setuptool.sh exists
    print_test "Rootless setup tool available"
    if vm_exec "which dockerd-rootless-setuptool.sh"; then
        pass
    else
        fail "dockerd-rootless-setuptool.sh not found"
    fi
    
    # Check Docker Compose installed
    print_test "Docker Compose installed"
    if vm_exec "docker compose version"; then
        pass
        local compose_version
        compose_version=$(vm_exec_output "docker compose version")
        info "$compose_version"
    else
        fail "Docker Compose not found"
    fi
    
    # Check Docker Buildx installed
    print_test "Docker Buildx installed"
    if vm_exec "docker buildx version"; then
        pass
    else
        fail "Docker Buildx not found"
    fi
    
    # Check uidmap installed (required for rootless)
    print_test "uidmap package installed"
    if vm_exec "dpkg -l | grep -q uidmap"; then
        pass
    else
        fail "uidmap not installed (required for rootless)"
    fi
    
    # Check slirp4netns installed (for rootless networking)
    print_test "slirp4netns installed"
    if vm_exec "which slirp4netns"; then
        pass
    else
        fail "slirp4netns not installed"
    fi
    
    # Check fuse-overlayfs installed
    print_test "fuse-overlayfs installed"
    if vm_exec "which fuse-overlayfs"; then
        pass
    else
        warn "fuse-overlayfs not found (may use native overlay)"
    fi
}

#-------------------------------------------------------------------------------
# Test: System Docker Disabled
#-------------------------------------------------------------------------------
test_system_docker_disabled() {
    print_header "System Docker Service Tests"
    
    # Check system Docker service is disabled
    print_test "System Docker service disabled"
    local docker_status
    docker_status=$(vm_exec_output "systemctl is-enabled docker.service 2>/dev/null" | head -1 | tr -d '[:space:]')
    if [[ "$docker_status" == "disabled" ]] || [[ "$docker_status" == "masked" ]] || [[ -z "$docker_status" ]]; then
        pass
        info "docker.service is ${docker_status:-not found}"
    else
        fail "docker.service is $docker_status (should be disabled)"
    fi
    
    # Check system Docker socket is disabled
    print_test "System Docker socket disabled"
    local socket_status
    socket_status=$(vm_exec_output "systemctl is-enabled docker.socket 2>/dev/null" | head -1 | tr -d '[:space:]')
    if [[ "$socket_status" == "disabled" ]] || [[ "$socket_status" == "masked" ]] || [[ -z "$socket_status" ]]; then
        pass
        info "docker.socket is ${socket_status:-not found}"
    else
        fail "docker.socket is $socket_status (should be disabled)"
    fi
    
    # Check system containerd is disabled
    print_test "System containerd service disabled"
    local containerd_status
    containerd_status=$(vm_exec_output "systemctl is-enabled containerd.service 2>/dev/null" | head -1 | tr -d '[:space:]')
    if [[ "$containerd_status" == "disabled" ]] || [[ "$containerd_status" == "masked" ]] || [[ -z "$containerd_status" ]]; then
        pass
        info "containerd.service is ${containerd_status:-not found}"
    else
        fail "containerd.service is $containerd_status (should be disabled)"
    fi
    
    # Check /var/run/docker.sock does NOT exist (rootless doesn't use it)
    print_test "System Docker socket file absent"
    if vm_exec "test ! -S /var/run/docker.sock"; then
        pass
    else
        warn "System Docker socket exists (may conflict with rootless)"
    fi
}

#-------------------------------------------------------------------------------
# Test: Rootless Docker Service
#-------------------------------------------------------------------------------
test_rootless_docker_service() {
    print_header "Rootless Docker Service Tests"
    
    # Check user linger is enabled
    print_test "User linger enabled for ubuntu"
    if vm_exec "test -f /var/lib/systemd/linger/ubuntu"; then
        pass
    else
        fail "Linger not enabled (rootless services won't persist)"
    fi
    
    # Check XDG_RUNTIME_DIR exists
    print_test "XDG_RUNTIME_DIR exists"
    if vm_exec "test -d /run/user/1000"; then
        pass
    else
        fail "/run/user/1000 not found"
    fi
    
    # Check rootless Docker socket exists
    print_test "Rootless Docker socket exists"
    if vm_exec "test -S /run/user/1000/docker.sock"; then
        pass
    else
        fail "Rootless Docker socket not found at /run/user/1000/docker.sock"
    fi
    
    # Check user Docker service is running
    print_test "User Docker service running"
    local user_docker_status
    user_docker_status=$(vm_exec_output "systemctl --user is-active docker 2>/dev/null || echo 'inactive'")
    if [ "$user_docker_status" = "active" ]; then
        pass
    else
        fail "User Docker service is $user_docker_status"
    fi
    
    # Check user Docker service is enabled
    print_test "User Docker service enabled"
    local user_docker_enabled
    user_docker_enabled=$(vm_exec_output "systemctl --user is-enabled docker 2>/dev/null || echo 'disabled'")
    if [ "$user_docker_enabled" = "enabled" ]; then
        pass
    else
        fail "User Docker service is $user_docker_enabled (should be enabled)"
    fi
    
    # Check rootless dockerd process is running as ubuntu user
    print_test "Rootless dockerd running as ubuntu user"
    if vm_exec "pgrep -u ubuntu dockerd"; then
        pass
        local pid
        pid=$(vm_exec_output "pgrep -u ubuntu dockerd | head -1")
        info "dockerd PID: $pid (running as ubuntu)"
    else
        fail "No dockerd process running as ubuntu user"
    fi
}

#-------------------------------------------------------------------------------
# Test: Rootless Configuration
#-------------------------------------------------------------------------------
test_rootless_configuration() {
    print_header "Rootless Configuration Tests"
    
    # Check subuid configuration
    print_test "Subuid configured for ubuntu"
    if vm_exec "grep -q '^ubuntu:' /etc/subuid"; then
        pass
        local subuid
        subuid=$(vm_exec_output "grep '^ubuntu:' /etc/subuid")
        info "subuid: $subuid"
    else
        fail "ubuntu not in /etc/subuid"
    fi
    
    # Check subgid configuration
    print_test "Subgid configured for ubuntu"
    if vm_exec "grep -q '^ubuntu:' /etc/subgid"; then
        pass
        local subgid
        subgid=$(vm_exec_output "grep '^ubuntu:' /etc/subgid")
        info "subgid: $subgid"
    else
        fail "ubuntu not in /etc/subgid"
    fi
    
    # Check user daemon.json exists
    print_test "User daemon.json exists"
    if vm_exec "test -f /home/ubuntu/.config/docker/daemon.json"; then
        pass
    else
        warn "User daemon.json not found"
    fi
    
    # Check Docker data directory exists
    print_test "Rootless data directory exists"
    if vm_exec "test -d /home/ubuntu/.local/share/docker"; then
        pass
    else
        fail "Rootless Docker data directory not found"
    fi
    
    # Check .bashrc has DOCKER_HOST
    print_test "DOCKER_HOST in .bashrc"
    if vm_exec "grep -q 'DOCKER_HOST' /home/ubuntu/.bashrc"; then
        pass
    else
        warn "DOCKER_HOST not set in .bashrc"
    fi
    
    # Check unprivileged port start
    print_test "Unprivileged port sysctl configured"
    local port_start
    port_start=$(vm_exec_output "sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null")
    if [ "$port_start" = "0" ]; then
        pass
        info "Can bind to ports >= $port_start"
    else
        warn "Unprivileged ports start at $port_start (ports < $port_start require root)"
    fi
}

#-------------------------------------------------------------------------------
# Test: Permissions
#-------------------------------------------------------------------------------
test_permissions() {
    print_header "Permissions Tests"
    
    # Check home directory ownership
    print_test "Home directory ownership"
    local home_owner
    home_owner=$(vm_exec_output "stat -c '%U:%G' /home/ubuntu")
    if [ "$home_owner" = "ubuntu:ubuntu" ]; then
        pass
    else
        fail "Home directory owned by $home_owner (expected ubuntu:ubuntu)"
    fi
    
    # Check .config ownership
    print_test ".config directory ownership"
    local config_owner
    config_owner=$(vm_exec_output "stat -c '%U:%G' /home/ubuntu/.config")
    if [ "$config_owner" = "ubuntu:ubuntu" ]; then
        pass
    else
        fail ".config owned by $config_owner (expected ubuntu:ubuntu)"
    fi
    
    # Check .local ownership
    print_test ".local directory ownership"
    local local_owner
    local_owner=$(vm_exec_output "stat -c '%U:%G' /home/ubuntu/.local")
    if [ "$local_owner" = "ubuntu:ubuntu" ]; then
        pass
    else
        fail ".local owned by $local_owner (expected ubuntu:ubuntu)"
    fi
    
    # Check Docker socket permissions
    print_test "Rootless Docker socket accessible"
    if vm_exec_rootless "test -w /run/user/1000/docker.sock"; then
        pass
    else
        fail "Cannot write to rootless Docker socket"
    fi
    
    # Check no sudo required for docker
    print_test "Docker works without sudo"
    if vm_exec_rootless "docker ps"; then
        pass
    else
        fail "Docker requires elevated privileges"
    fi
}

#-------------------------------------------------------------------------------
# Test: Rootless Security
#-------------------------------------------------------------------------------
test_rootless_security() {
    print_header "Rootless Security Tests"
    
    # Check Docker is running in rootless mode
    print_test "Docker reports rootless mode"
    local security_opts
    security_opts=$(vm_exec_rootless_output "docker info 2>/dev/null | grep -i 'rootless'")
    if [ -n "$security_opts" ]; then
        pass
        info "$security_opts"
    else
        fail "Docker not reporting rootless mode"
    fi
    
    # Check Docker context
    print_test "Docker context is rootless"
    local context
    context=$(vm_exec_rootless_output "docker context show 2>/dev/null")
    if [ "$context" = "rootless" ] || [ -n "$(vm_exec_rootless_output "docker info 2>/dev/null | grep -i rootless")" ]; then
        pass
        info "Context: $context"
    else
        warn "Context: $context (expected rootless)"
    fi
    
    # Verify docker.sock is NOT /var/run/docker.sock
    print_test "Not using system Docker socket"
    local docker_host
    docker_host=$(vm_exec_rootless_output "echo \$DOCKER_HOST")
    if [[ "$docker_host" != *"/var/run/docker.sock"* ]] && [[ "$docker_host" == *"/run/user/"* ]]; then
        pass
        info "DOCKER_HOST: $docker_host"
    else
        fail "Using system Docker socket: $docker_host"
    fi
    
    # Check container runs as non-root UID (rootless implies user namespaces)
    print_test "Containers use user namespaces"
    local security_info
    security_info=$(vm_exec_rootless_output "docker info 2>/dev/null | grep -E 'rootless|userns'")
    if echo "$security_info" | grep -qi "rootless\|userns"; then
        pass
        info "Rootless mode uses user namespaces by default"
    else
        warn "User namespace info not found"
    fi
}

#-------------------------------------------------------------------------------
# Test: Docker Functionality
#-------------------------------------------------------------------------------
test_docker_functionality() {
    print_header "Docker Functionality Tests"
    
    # Test docker info
    print_test "Docker info command"
    if vm_exec_rootless "docker info"; then
        pass
    else
        fail "docker info failed"
    fi
    
    # Test docker ps
    print_test "Docker ps command"
    if vm_exec_rootless "docker ps"; then
        pass
    else
        fail "docker ps failed"
    fi
    
    # Test pulling an image
    print_test "Pull alpine image"
    if vm_exec_rootless "docker pull alpine:3.21"; then
        pass
    else
        fail "Failed to pull alpine image"
    fi
    
    # Test running a container
    print_test "Run container (hello-world)"
    if vm_exec_rootless "docker run --rm hello-world:linux"; then
        pass
    else
        fail "Failed to run hello-world container"
    fi
    
    # Test container with volume
    print_test "Run container with volume mount"
    if vm_exec_rootless "docker run --rm -v /tmp:/data alpine:3.21 ls /data"; then
        pass
    else
        fail "Failed to run container with volume"
    fi
    
    # Test container with port mapping
    print_test "Run container with port mapping"
    if vm_exec_rootless "docker run --rm -d -p 9999:80 --name nginx-test nginx:1.28.2-alpine3.23"; then
        sleep 2
        if vm_exec "curl -s http://localhost:9999"; then
            pass
        else
            fail "Port mapping not working"
        fi
        vm_exec_rootless "docker stop nginx-test 2>/dev/null || true"
    else
        fail "Failed to run container with port mapping"
    fi
    
    # Test docker exec
    print_test "Docker exec command"
    vm_exec_rootless "docker run -d --name exec-test alpine:3.21 sleep 60" || true
    if vm_exec_rootless "docker exec exec-test echo 'test'"; then
        pass
    else
        fail "docker exec failed"
    fi
    vm_exec_rootless "docker rm -f exec-test 2>/dev/null || true"
    
    # Test docker build
    print_test "Docker build command"
    vm_exec_rootless "mkdir -p /tmp/docker-build-test"
    vm_exec_rootless "echo 'FROM alpine:3.21' > /tmp/docker-build-test/Dockerfile"
    vm_exec_rootless "echo 'RUN echo hello' >> /tmp/docker-build-test/Dockerfile"
    if vm_exec_rootless "docker build -t test-build:latest /tmp/docker-build-test"; then
        pass
    else
        fail "docker build failed"
    fi
    vm_exec_rootless "docker rmi test-build:latest 2>/dev/null || true"
    
    # Test Docker Compose
    print_test "Docker Compose functionality"
    if vm_exec_rootless "cd /home/ubuntu/docker-compose-example && docker compose config"; then
        pass
    else
        fail "Docker Compose config validation failed"
    fi
}

#-------------------------------------------------------------------------------
# Test: Network
#-------------------------------------------------------------------------------
test_network() {
    print_header "Network Tests"
    
    # Check slirp4netns is used for networking
    print_test "Rootless networking mode"
    local network_mode
    network_mode=$(vm_exec_rootless_output "docker info 2>/dev/null | grep -i 'network'")
    if [ -n "$network_mode" ]; then
        pass
        info "Network info available"
    else
        warn "Could not determine network mode"
    fi
    
    # Test creating a network
    print_test "Create Docker network"
    if vm_exec_rootless "docker network create test-net-rootless"; then
        pass
        vm_exec_rootless "docker network rm test-net-rootless 2>/dev/null || true"
    else
        fail "Failed to create network"
    fi
    
    # Test container-to-container networking
    print_test "Container-to-container networking"
    vm_exec_rootless "docker network create c2c-test-net 2>/dev/null || true"
    vm_exec_rootless "docker run -d --name c2c-server --network c2c-test-net alpine:3.21 sleep 60" || true
    if vm_exec_rootless "docker run --rm --network c2c-test-net alpine:3.21 ping -c 1 c2c-server"; then
        pass
    else
        fail "Container networking failed"
    fi
    vm_exec_rootless "docker rm -f c2c-server 2>/dev/null || true"
    vm_exec_rootless "docker network rm c2c-test-net 2>/dev/null || true"
    
    # Test outbound connectivity from container (using wget instead of ping - ICMP doesn't work in rootless)
    print_test "Container outbound connectivity"
    if vm_exec_rootless "docker run --rm alpine:3.21 wget -q -O /dev/null http://google.com"; then
        pass
    else
        fail "Container cannot reach internet"
    fi
    
    # Test DNS resolution in container
    print_test "Container DNS resolution"
    if vm_exec_rootless "docker run --rm alpine:3.21 nslookup google.com"; then
        pass
    else
        fail "DNS resolution failed"
    fi
}

#-------------------------------------------------------------------------------
# Test: Resources
#-------------------------------------------------------------------------------
test_resources() {
    print_header "Resource Tests"
    
    # Check VM memory
    print_test "VM memory adequate"
    local total_mem
    total_mem=$(vm_exec_output "free -m | awk '/^Mem:/{print \$2}'")
    if [ "$total_mem" -ge 1800 ]; then
        pass
        info "Total memory: ${total_mem}MB"
    else
        warn "Low memory: ${total_mem}MB (recommend >= 2GB)"
    fi
    
    # Check available disk space
    print_test "Disk space available"
    local available_disk
    available_disk=$(vm_exec_output "df -BG / | awk 'NR==2{print \$4}' | tr -d 'G'")
    if [ "$available_disk" -ge 5 ]; then
        pass
        info "Available disk: ${available_disk}GB"
    else
        warn "Low disk: ${available_disk}GB available"
    fi
    
    # Check rootless data directory size
    print_test "Rootless Docker storage"
    local docker_size
    docker_size=$(vm_exec_output "du -sh /home/ubuntu/.local/share/docker 2>/dev/null | cut -f1")
    if [ -n "$docker_size" ]; then
        pass
        info "Docker storage: $docker_size"
    else
        warn "Could not determine Docker storage size"
    fi
}

#-------------------------------------------------------------------------------
# Test: Cleanup
#-------------------------------------------------------------------------------
test_cleanup() {
    print_header "Cleanup"
    
    echo "  Removing test containers and images..."
    vm_exec_rootless "docker rm -f \$(docker ps -aq) 2>/dev/null || true"
    vm_exec_rootless "docker rmi alpine:3.21 2>/dev/null || true"
    vm_exec_rootless "docker rmi nginx:1.28.2-alpine3.23 2>/dev/null || true"
    vm_exec_rootless "docker network prune -f 2>/dev/null || true"
    echo -e "  ${GREEN}✓ Cleanup complete${NC}"
}

#-------------------------------------------------------------------------------
# Check Common Issues
#-------------------------------------------------------------------------------
check_common_issues() {
    print_header "Common Issues Check"
    
    local issues_found=0
    
    # Check if XDG_RUNTIME_DIR is set correctly in bashrc and directory exists
    print_test "XDG_RUNTIME_DIR set in session"
    local xdg_check
    xdg_check=$(vm_exec_output "cat ~/.bashrc | grep -c XDG_RUNTIME_DIR && test -d /run/user/\$(id -u) && echo 'exists'")
    if echo "$xdg_check" | grep -q "exists"; then
        pass
        info "XDG_RUNTIME_DIR configured in .bashrc and /run/user/\$(id -u) exists"
    else
        warn "XDG_RUNTIME_DIR may not be set correctly"
        issues_found=$((issues_found + 1))
    fi
    
    # Check for conflicting system Docker
    print_test "No conflicting system Docker processes"
    if vm_exec "pgrep -u root dockerd"; then
        warn "Root dockerd process found (may conflict)"
        issues_found=$((issues_found + 1))
    else
        pass
    fi
    
    # Check /var/run/docker.sock not in use
    print_test "System socket not being used"
    local system_socket_users
    system_socket_users=$(vm_exec_output "ls -la /var/run/docker.sock 2>/dev/null || echo 'not found'")
    if [[ "$system_socket_users" == *"not found"* ]]; then
        pass
    else
        warn "System Docker socket exists"
        issues_found=$((issues_found + 1))
    fi
    
    # Check cgroup configuration
    print_test "Cgroup configuration"
    local cgroup_version
    cgroup_version=$(vm_exec_output "stat -fc %T /sys/fs/cgroup/")
    if [ "$cgroup_version" = "cgroup2fs" ]; then
        pass
        info "Using cgroup v2"
    else
        pass
        info "Using cgroup v1"
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
        echo -e "  ${GREEN}Docker Rootless VM is healthy and ready to use.${NC}"
    else
        echo -e "  ${RED}$TESTS_FAILED of $total tests failed.${NC}"
        echo ""
        echo -e "  ${YELLOW}Review failed tests above for troubleshooting.${NC}"
    fi
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    
    # Return appropriate exit code
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
    echo -e "${BLUE}║       DOCKER ROOTLESS VM TEST SUITE                            ║${NC}"
    echo -e "${BLUE}║       VM: $VM_NAME${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    test_vm_accessibility
    test_docker_rootless_installation
    test_system_docker_disabled
    test_rootless_docker_service
    test_rootless_configuration
    test_permissions
    test_rootless_security
    test_docker_functionality
    test_network
    test_resources
    test_cleanup
    check_common_issues
    
    print_summary
}

# Run main
main "$@"
