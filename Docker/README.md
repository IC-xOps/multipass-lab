# 🐳 Docker - Containerization Platform

Complete Docker environments running on Ubuntu via Multipass. This repository provides two configurations:

| Configuration | Use Case | Security Level |
|---------------|----------|----------------|
| [Standard Docker](#-standard-docker) | Development, CI/CD, Swarm | Standard (root daemon) |
| [Docker Rootless](#-docker-rootless) | Security-critical, multi-tenant | Enhanced (user daemon) |

---

## 📋 Prerequisites

- **macOS** with [Multipass](https://multipass.run/) installed
- Internet connection for package downloads

```bash
# Install Multipass on macOS
brew install multipass
```

---

# 🐋 Standard Docker

Full Docker Engine with Compose, Swarm, and optimal configuration. The Docker daemon runs as root with the ubuntu user added to the docker group.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  Multipass VM (docker-vm)                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                   Docker Engine                       │  │
│  │  • Docker CE 29.x                                     │  │
│  │  • Docker Compose v5.x                                │  │
│  │  • Docker Swarm (initialized)                         │  │
│  │  • Containerd                                         │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Configuration                            │  │
│  │  • overlay2 storage driver                            │  │
│  │  • Log rotation (10m, 3 files)                        │  │
│  │  • Ulimits configured                                 │  │
│  │  • IP forwarding enabled                              │  │
│  │  • Ubuntu user in docker group                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Create the VM

```bash
multipass launch 24.04 -n docker-vm -c 2 -m 4G -d 20G --cloud-init docker.yaml
```

### 2. Wait for Setup (~3-5 minutes)

```bash
multipass exec docker-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check Docker
multipass exec docker-vm -- docker --version
multipass exec docker-vm -- docker compose version

# Check Swarm
multipass exec docker-vm -- docker node ls
```

### 4. Run Tests

```bash
./test-docker-vm.sh
# Expected: 38 tests passed
```

## Configuration Details

### VM Resources

| Resource | Value |
|----------|-------|
| CPUs | 2 |
| Memory | 4GB |
| Disk | 20GB |
| Ubuntu | 24.04 LTS |

### Installed Components

| Component | Version | Source |
|-----------|---------|--------|
| Docker CE | 29.x | docker.com |
| Docker Compose | v5.x | docker-compose-plugin |
| Containerd | Latest | docker.com |
| Docker Swarm | Initialized | Built-in |

### Daemon Configuration

**File**: `/etc/docker/daemon.json`

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  },
  "userland-proxy": false
}
```

### System Settings

- **Docker auto-starts on VM boot** (systemd enabled)
- IP forwarding enabled (`net.ipv4.ip_forward=1`)
- Bridge netfilter enabled
- Ubuntu user added to `docker` group
- Docker Swarm initialized (single-node manager)

## Usage Examples

```bash
# Access the VM
multipass shell docker-vm

# Run containers
docker run -d --name nginx -p 8080:80 nginx:alpine
docker ps

# Use Docker Compose
cd ~/docker-compose-example
docker compose up -d
docker compose logs -f

# Deploy to Swarm
cd ~/swarm-example
docker stack deploy -c docker-compose.yml mystack
docker service ls
```

## Test Suite (38 tests)

```bash
./test-docker-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| Prerequisites | 1 | Multipass installation |
| VM Status | 2 | VM exists, running |
| Cloud-Init | 1 | Cloud-init completion |
| Docker Installation | 4 | Daemon, version, Compose, Containerd |
| Post-Installation | 10 | Boot services, live restore, log rotation, storage driver, IP forward, netfilter, ulimits, CLI config, bash completion |
| Permissions | 6 | Docker group, socket ownership, sudo-less access, home dir, .docker dir ownership and mode |
| Functionality | 4 | Pull images, run containers, volumes, bind mounts |
| Swarm | 1 | Initialization status |
| Network | 3 | Internet, DNS, Docker Hub |
| Resources | 3 | Disk space, memory, Docker storage |
| Common Issues | 3 | Valid daemon.json, zombie containers, dangling images |

## Troubleshooting

### Docker commands require sudo

```bash
# Ensure user is in docker group
groups
sudo usermod -aG docker $USER
newgrp docker
```

### Docker daemon not starting

```bash
# Check service status
sudo systemctl status docker
sudo journalctl -u docker -n 50

# Restart Docker
sudo systemctl restart docker
```

### Permission denied on bind mount

```bash
# Check ownership
ls -la /path/to/mount

# Fix ownership
sudo chown -R $USER:$USER /path/to/mount
```

### Swarm not working

```bash
# Check Swarm status
docker info | grep Swarm

# Re-initialize if needed
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
```

## Files

| File | Description |
|------|-------------|
| `docker.yaml` | Cloud-init configuration |
| `test-docker-vm.sh` | Test suite (38 tests) |

---

# 🔒 Docker Rootless

Secure Docker installation with the daemon running as a non-root user. This significantly reduces the attack surface by eliminating root privileges from the container runtime.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│              Multipass VM (docker-rootless-vm)              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │          Docker Rootless (runs as ubuntu)             │  │
│  │  • Docker CE 29.x (rootless mode)                     │  │
│  │  • Docker Compose v5.x                                │  │
│  │  • User systemd service                               │  │
│  │  • slirp4netns networking                             │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Rootless Configuration                   │  │
│  │  • System Docker DISABLED                             │  │
│  │  • subuid/subgid: 100000-165535                       │  │
│  │  • loginctl linger enabled                            │  │
│  │  • fuse-overlayfs storage                             │  │
│  │  • Unprivileged ports enabled (sysctl)                │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Rootless vs Standard Comparison

| Feature | Docker Rootless | Standard Docker |
|---------|-----------------|-----------------|
| Daemon runs as | `ubuntu` (your user) | `root` |
| Container escape risk | Lower (user privileges only) | Higher |
| Host file access | User's files only | Full system |
| Privileged ports (<1024) | Requires sysctl config | Yes |
| Performance | Slight overhead | Native |
| Docker Swarm | ❌ Not supported | ✅ Yes |
| Bind mounts | User-accessible paths | Any path |

### When to Use Docker Rootless

- Security is a top priority
- Running untrusted containers
- Multi-tenant environments
- Compliance requirements (least-privilege)
- Reducing attack surface

## Quick Start

### 1. Create the VM

```bash
multipass launch 24.04 -n docker-rootless-vm -c 2 -m 2G -d 10G --cloud-init docker-rootless.yaml
```

### 2. Wait for Setup (~3-5 minutes)

```bash
multipass exec docker-rootless-vm -- cloud-init status --wait
```

### 3. Verify Rootless Mode

```bash
# Check Docker runs as user (not root)
multipass exec docker-rootless-vm -- docker info 2>/dev/null | grep -i rootless

# Verify dockerd runs as ubuntu
multipass exec docker-rootless-vm -- ps aux | grep dockerd
```

### 4. Run Tests

```bash
./test-docker-rootless-vm.sh
# Expected: 57 tests passed
```

## Configuration Details

### VM Resources

| Resource | Value |
|----------|-------|
| CPUs | 2 |
| Memory | 2GB |
| Disk | 10GB |
| Ubuntu | 24.04 LTS |

### Installed Components

| Component | Version | Purpose |
|-----------|---------|---------|
| Docker CE | 29.x | Container runtime (rootless) |
| Docker Compose | v5.x | Multi-container orchestration |
| slirp4netns | Latest | User-mode networking |
| fuse-overlayfs | Latest | Rootless storage driver |
| uidmap | Latest | User namespace mapping |

### System Docker Status

System Docker is **completely disabled**:

```bash
systemctl disable --now docker.service docker.socket
systemctl disable --now containerd.service
```

### User Namespace Mapping

**Files**: `/etc/subuid` and `/etc/subgid`

```
ubuntu:100000:65536
```

This maps UIDs 100000-165535 to the ubuntu user for container isolation.

### Rootless Environment

**File**: `~/.bashrc`

```bash
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
```

### Rootless Daemon Configuration

**File**: `~/.config/docker/daemon.json`

```json
{
  "storage-driver": "fuse-overlayfs"
}
```

### System Settings

- **Docker auto-starts on VM boot** (user systemd service + linger)
- `loginctl enable-linger ubuntu` - Starts user services at boot without login
- `net.ipv4.ip_unprivileged_port_start=0` - Allow binding to ports < 1024

## Usage Examples

```bash
# Access the VM
multipass shell docker-rootless-vm

# Run containers (same commands, runs as user)
docker run -d --name nginx -p 8080:80 nginx:alpine
docker ps

# Verify rootless mode
docker info | grep -i rootless
# Output: rootless

# Check process owner
ps aux | grep dockerd
# Shows: ubuntu ... dockerd

# Use Docker Compose
docker compose up -d
docker compose logs -f
```

## Test Suite (57 tests)

```bash
./test-docker-rootless-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| Docker Installation | 8 | CLI, rootless extras, setup tool, Compose, Buildx, uidmap, slirp4netns, fuse-overlayfs |
| System Docker Disabled | 4 | Service disabled, socket disabled, containerd disabled, socket absent |
| Rootless Service | 6 | Linger enabled, XDG_RUNTIME_DIR, socket exists, service running/enabled, process owner |
| Rootless Configuration | 6 | subuid/subgid, daemon.json, data dir, DOCKER_HOST, unprivileged ports |
| Permissions | 5 | Home dir, .config, .local, socket access, sudo-less |
| Rootless Security | 4 | Rootless mode, context, socket path, user namespaces |
| Docker Functionality | 9 | Info, ps, pull, run, volume, port, exec, build, compose |
| Network | 5 | Network mode, create network, container-to-container, outbound, DNS |
| Resources | 3 | Memory, disk, Docker storage |
| Common Issues | 4 | XDG_RUNTIME_DIR, system processes, socket conflicts, cgroups |

## Troubleshooting

### Docker command not found or wrong socket

```bash
# Ensure DOCKER_HOST is set
echo $DOCKER_HOST
# Should show: unix:///run/user/1000/docker.sock

# Source bashrc
source ~/.bashrc
```

### Rootless Docker not starting

```bash
# Check user service
systemctl --user status docker

# Restart user service
systemctl --user restart docker

# Check XDG_RUNTIME_DIR
echo $XDG_RUNTIME_DIR
# Should show: /run/user/1000
```

### Permission denied on port < 1024

```bash
# Check sysctl setting
cat /proc/sys/net/ipv4/ip_unprivileged_port_start
# Should show: 0

# If not, fix it
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
```

### Rootless storage issues

```bash
# Check fuse-overlayfs
which fuse-overlayfs

# Check storage location
ls -la ~/.local/share/docker
```

### Cannot connect to Docker daemon

```bash
# Check if socket exists
ls -la $XDG_RUNTIME_DIR/docker.sock

# Check if system Docker is accidentally running
sudo systemctl status docker
# Should be: inactive (dead)
```

## Files

| File | Description |
|------|-------------|
| `docker-rootless.yaml` | Cloud-init configuration |
| `test-docker-rootless-vm.sh` | Test suite (57 tests) |

---

# 🛠️ VM Management

```bash
# List VMs
multipass list

# Stop/Start VM
multipass stop docker-vm
multipass start docker-vm

# Delete VM
multipass delete docker-vm && multipass purge

# Get VM info
multipass info docker-vm
```

---

# 📚 Reference

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/)
- [Docker Swarm](https://docs.docker.com/engine/swarm/)
- [Docker Rootless Mode](https://docs.docker.com/engine/security/rootless/)
- [Multipass Documentation](https://multipass.run/docs)

---

**Docker environments made simple** 🐳
