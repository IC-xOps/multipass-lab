# LXD - System Containers & Virtual Machines

A complete LXD environment running on Ubuntu via Multipass. This repository provides three configurations:

1. **Standard LXD** - System containers and VMs with pre-deployed nginx
2. **Docker-in-LXD** - Run Docker inside LXD containers for isolated Docker environments
3. **Podman-in-LXD** - Run Podman inside LXD containers for daemonless container runtime

---

## 📑 Table of Contents

- [What is LXD?](#-what-is-lxd)
- [Prerequisites](#-prerequisites)
- [Quick Start: Standard LXD](#-quick-start-standard-lxd)
- [Quick Start: Docker-in-LXD](#-quick-start-docker-in-lxd)
- [Quick Start: Podman-in-LXD](#-quick-start-podman-in-lxd)
- [File Structure](#-file-structure)
- [Basic Usage](#-basic-usage)
- [Docker-in-LXD Details](#-docker-in-lxd-details)
- [Podman-in-LXD Details](#-podman-in-lxd-details)
- [Configuration](#-configuration)
- [Test Suites](#-test-suites)
- [Troubleshooting](#-troubleshooting)
- [Reference](#-reference)

---

## 🚀 What is LXD?

LXD is a next-generation system container and virtual machine manager. Unlike application containers (Docker), LXD runs full Linux operating systems with init systems, multiple processes, and complete isolation.

### Key Features

| Feature | Description |
|---------|-------------|
| **System Containers** | Full Linux OS in a container (not just apps) |
| **Virtual Machines** | Full VMs with same UX as containers |
| **Image Based** | Pre-built images for instant deployment |
| **Snapshots** | Point-in-time backups of containers/VMs |
| **Live Migration** | Move running containers between hosts |
| **REST API** | Full remote management capabilities |
| **Clustering** | Multi-node clusters for HA |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    LXD Management Layer                     │
├────────────────────────────┬────────────────────────────────┤
│     System Containers      │       Virtual Machines         │
│  ┌──────┐ ┌──────┐        │    ┌──────────────────────┐    │
│  │Ubuntu│ │Alpine│        │    │    ┌──────────────┐  │    │
│  │  OS  │ │  OS  │        │    │    │   Full OS    │  │    │
│  └──────┘ └──────┘        │    │    │   + Kernel   │  │    │
│      │         │          │    │    └──────────────┘  │    │
│      └────┬────┘          │    │        QEMU/KVM      │    │
│           │               │    └──────────────────────┘    │
│     Shared Kernel         │       Dedicated Kernel         │
├───────────────────────────┴────────────────────────────────┤
│                      Host Kernel                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Prerequisites

- **macOS** with [Multipass](https://multipass.run/) installed
- Internet connection for package downloads

| Setup | RAM | Disk | Use Case |
|-------|-----|------|----------|
| Standard LXD | 2GB+ | 15GB+ | System containers, basic usage |
| Docker-in-LXD | 4GB+ | 20GB+ | Nested Docker containers |
| Podman-in-LXD | 4GB+ | 20GB+ | Daemonless containers, rootless by default |

```bash
# Install Multipass on macOS
brew install multipass
```

---

## 🚀 Quick Start: Standard LXD

Standard LXD setup with a pre-deployed nginx container for immediate testing.

### 1. Create the VM

```bash
multipass launch 24.04 -n lxd-vm -c 2 -m 2G -d 15G --cloud-init lxd.yaml
```

### 2. Wait for Setup (~3-5 minutes)

```bash
multipass exec lxd-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check LXD and containers
multipass exec lxd-vm -- lxc list

# Test HTTP access (nginx in web-test container)
curl http://$(multipass info lxd-vm | grep IPv4 | awk '{print $2}'):8080
```

### 4. Run Tests

```bash
./test-lxd-vm.sh
# Expected: 47 tests passed
```

### What Gets Deployed

```
┌─────────────────────────────────────────┐
│           Multipass VM (lxd-vm)         │
│  ┌───────────────────────────────────┐  │
│  │              LXD                  │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │    web-test (container)     │  │  │
│  │  │         nginx:80            │  │  │
│  │  └─────────────────────────────┘  │  │
│  │           lxdbr0 bridge           │  │
│  └───────────────────────────────────┘  │
│              Port 8080 → nginx          │
└─────────────────────────────────────────┘
```

---

## 🐳 Quick Start: Docker-in-LXD

Run Docker containers inside LXD system containers for isolated Docker environments.

### 1. Create the VM

```bash
multipass launch 24.04 -n docker-in-lxd-vm -c 2 -m 4G -d 20G --cloud-init docker-in-lxd.yaml
```

### 2. Wait for Setup (~5-10 minutes)

```bash
multipass exec docker-in-lxd-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check LXD container with Docker
multipass exec docker-in-lxd-vm -- lxc list

# Check Docker inside the container
multipass exec docker-in-lxd-vm -- lxc exec docker-host -- docker ps

# Test HTTP (nginx running in Docker, inside LXD)
curl http://$(multipass info docker-in-lxd-vm | grep IPv4 | awk '{print $2}'):8080
```

### 4. Run Tests

```bash
./test-docker-in-lxd-vm.sh
# Expected: 39 tests passed
```

### What Gets Deployed

```
┌─────────────────────────────────────────────────────────────┐
│              Multipass VM (docker-in-lxd-vm)                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                        LXD                            │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │         docker-host (LXD container)             │  │  │
│  │  │  ┌─────────────────────────────────────────┐   │  │  │
│  │  │  │              Docker Engine              │   │  │  │
│  │  │  │  ┌───────────┐  ┌───────────┐          │   │  │  │
│  │  │  │  │   nginx   │  │  (more)   │          │   │  │  │
│  │  │  │  │ container │  │containers │          │   │  │  │
│  │  │  │  └───────────┘  └───────────┘          │   │  │  │
│  │  │  └─────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                     lxdbr0 bridge                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                    Port 8080 → Docker nginx                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 🦭 Quick Start: Podman-in-LXD

Run Podman containers inside LXD system containers for daemonless, rootless container runtime.

### 1. Create the VM

```bash
multipass launch 24.04 -n podman-in-lxd-vm -c 2 -m 4G -d 20G --cloud-init podman-in-lxd.yaml
```

### 2. Wait for Setup (~5-8 minutes)

```bash
multipass exec podman-in-lxd-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check LXD container with Podman
multipass exec podman-in-lxd-vm -- lxc list

# Check Podman inside the container
multipass exec podman-in-lxd-vm -- lxc exec podman-host -- podman ps

# Test HTTP (nginx running in Podman, inside LXD)
curl http://$(multipass info podman-in-lxd-vm | grep IPv4 | awk '{print $2}'):8080
```

### 4. Run Tests

```bash
./test-podman-in-lxd-vm.sh
# Expected: 44 tests passed
```

### What Gets Deployed

```
┌─────────────────────────────────────────────────────────────┐
│             Multipass VM (podman-in-lxd-vm)                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                        LXD                            │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │         podman-host (LXD container)             │  │  │
│  │  │  ┌─────────────────────────────────────────┐   │  │  │
│  │  │  │           Podman (daemonless)           │   │  │  │
│  │  │  │  ┌───────────┐  ┌───────────┐          │   │  │  │
│  │  │  │  │   nginx   │  │  (more)   │          │   │  │  │
│  │  │  │  │ container │  │containers │          │   │  │  │
│  │  │  │  └───────────┘  └───────────┘          │   │  │  │
│  │  │  └─────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                     lxdbr0 bridge                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                   Port 8080 → Podman nginx                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 File Structure

```
lxd/
├── lxd.yaml                    # Cloud-init: Standard LXD setup (pinned versions)
├── docker-in-lxd.yaml          # Cloud-init: Docker inside LXD (pinned versions)
├── podman-in-lxd.yaml          # Cloud-init: Podman inside LXD (pinned versions)
├── test-lxd-vm.sh              # Test suite for lxd-vm (47 tests)
├── test-docker-in-lxd-vm.sh    # Test suite for docker-in-lxd-vm (39 tests)
├── test-podman-in-lxd-vm.sh    # Test suite for podman-in-lxd-vm (44 tests)
└── README.md                   # This documentation
```

---

## 📖 Basic Usage

### Container Lifecycle

```bash
# Launch a new container
lxc launch ubuntu:22.04 mycontainer

# List containers
lxc list

# Get container info
lxc info mycontainer

# Shell into container
lxc exec mycontainer -- bash

# Stop/Start/Delete
lxc stop mycontainer
lxc start mycontainer
lxc delete mycontainer --force
```

### Virtual Machines

```bash
# Launch a VM (add --vm flag)
lxc launch ubuntu:22.04 myvm --vm

# Launch with resources
lxc launch ubuntu:22.04 myvm --vm -c limits.cpu=2 -c limits.memory=2GB

# Console access
lxc console myvm
```

### Images

```bash
# List remote images
lxc image list ubuntu:
lxc image list images:

# Download locally
lxc image copy ubuntu:22.04 local: --alias ubuntu-22.04

# List local images
lxc image list
```

### Snapshots

```bash
# Create snapshot
lxc snapshot mycontainer snap1

# Restore snapshot
lxc restore mycontainer snap1

# Delete snapshot
lxc delete mycontainer/snap1

# Clone from snapshot
lxc copy mycontainer/snap1 newcontainer
```

### File Transfer

```bash
# Push file to container
lxc file push localfile.txt mycontainer/home/ubuntu/

# Pull file from container
lxc file pull mycontainer/home/ubuntu/file.txt ./

# Push directory
lxc file push -r ./mydir mycontainer/home/ubuntu/
```

### Port Forwarding (Proxy Devices)

```bash
# Expose container port 80 on host port 8080
lxc config device add mycontainer http proxy \
  listen=tcp:0.0.0.0:8080 connect=tcp:127.0.0.1:80

# List devices
lxc config device show mycontainer

# Remove device
lxc config device remove mycontainer http
```

---

## 🐳 Docker-in-LXD Details

### Why Run Docker Inside LXD?

| Benefit | Description |
|---------|-------------|
| **Isolation** | Each Docker environment is fully isolated |
| **Snapshots** | Snapshot entire Docker environments instantly |
| **Multi-tenancy** | Multiple isolated Docker hosts on one machine |
| **Easy Rollback** | Restore Docker env to previous state |
| **Resource Control** | LXD limits on top of Docker limits |

### Docker Profile Configuration

The key to running Docker inside LXD is the security profile:

```yaml
config:
  security.nesting: "true"                        # Allow nested containers
  security.syscalls.intercept.mknod: "true"       # Allow device creation
  security.syscalls.intercept.setxattr: "true"    # Required for overlay FS
```

### Access Docker Commands

```bash
# From your Mac (through multipass + lxc)
multipass exec docker-in-lxd-vm -- lxc exec docker-host -- docker ps
multipass exec docker-in-lxd-vm -- lxc exec docker-host -- docker images

# Or shell into the VM first
multipass shell docker-in-lxd-vm
lxc exec docker-host -- docker ps
```

### Run Docker Containers

```bash
# Run a container
lxc exec docker-host -- docker run -d --name myapp -p 8081:80 nginx

# Check logs
lxc exec docker-host -- docker logs myapp

# Exec into container
lxc exec docker-host -- docker exec -it myapp sh

# Stop and remove
lxc exec docker-host -- docker stop myapp && lxc exec docker-host -- docker rm myapp
```

### Docker Compose

```bash
# Docker Compose is pre-installed
lxc exec docker-host -- docker compose version

# Create and run a compose stack
lxc exec docker-host -- bash -c 'cat > /tmp/compose.yml << EOF
services:
  web:
    image: nginx:alpine
    ports:
      - "8081:80"
  redis:
    image: redis:alpine
EOF'

lxc exec docker-host -- docker compose -f /tmp/compose.yml up -d
```

### Expose Additional Ports

```bash
# Add proxy device for new port
lxc config device add docker-host port8081 proxy \
  listen=tcp:0.0.0.0:8081 connect=tcp:127.0.0.1:8081
```

### Create Additional Docker Hosts

```bash
# Launch new container with docker profile
lxc launch ubuntu:22.04 docker-dev --profile default --profile docker

# Install Docker (use provided script)
./setup-docker-container.sh docker-dev
```

### Snapshot Docker Environments

```bash
# Snapshot entire Docker environment
lxc snapshot docker-host before-experiment

# Do risky things...
lxc exec docker-host -- docker system prune -af

# Restore if needed
lxc restore docker-host before-experiment
```

---

## 🦭 Podman-in-LXD Details

### Why Run Podman Inside LXD?

| Benefit | Description |
|---------|-------------|
| **Daemonless** | No daemon process - containers run directly |
| **Rootless** | Run containers without root privileges by default |
| **OCI Compatible** | Full OCI/Docker compatibility |
| **Isolation** | Each Podman environment is fully isolated in LXD |
| **Security** | Better security model with user namespaces |
| **Docker CLI** | Same CLI commands as Docker |

### Podman vs Docker

| Feature | Podman | Docker |
|---------|--------|--------|
| Architecture | Daemonless | Daemon-based |
| Root Required | No (rootless default) | Yes (unless rootless mode) |
| CLI Compatibility | docker-compatible | native |
| Compose | podman-compose or built-in | docker compose |
| Systemd Integration | Native support | Limited |
| Fork/Exec Model | Direct | Via daemon |

### Podman Profile Configuration

The key to running Podman inside LXD is the security profile:

```yaml
config:
  security.nesting: "true"                        # Allow nested containers
  security.syscalls.intercept.mknod: "true"       # Allow device creation
  security.syscalls.intercept.setxattr: "true"    # Required for overlay FS
```

### Access Podman Commands

```bash
# From your Mac (through multipass + lxc)
multipass exec podman-in-lxd-vm -- lxc exec podman-host -- podman ps
multipass exec podman-in-lxd-vm -- lxc exec podman-host -- podman images

# Or shell into the VM first
multipass shell podman-in-lxd-vm
lxc exec podman-host -- podman ps
```

### Run Podman Containers

```bash
# Run a container (same as Docker!)
lxc exec podman-host -- podman run -d --name myapp -p 8081:80 docker.io/nginx:alpine

# Check logs
lxc exec podman-host -- podman logs myapp

# Exec into container
lxc exec podman-host -- podman exec -it myapp sh

# Stop and remove
lxc exec podman-host -- podman stop myapp && lxc exec podman-host -- podman rm myapp
```

### Rootless Podman

One of Podman's key features is native rootless operation:

```bash
# Run as non-root user (ubuntu)
lxc exec podman-host -- sudo -u ubuntu podman run --rm docker.io/alpine echo "rootless works!"

# Check rootless storage
lxc exec podman-host -- sudo -u ubuntu podman info --format '{{.Store.GraphRoot}}'

# Rootless networking uses slirp4netns
lxc exec podman-host -- which slirp4netns
```

### Podman Socket (Docker API Compatibility)

Podman provides a Docker-compatible socket:

```bash
# Enable the socket
lxc exec podman-host -- systemctl enable --now podman.socket

# Use Docker CLI tools with Podman
lxc exec podman-host -- curl --unix-socket /run/podman/podman.sock \
  http://localhost/v4.0.0/containers/json
```

### Expose Additional Ports

```bash
# Add proxy device for new port
lxc config device add podman-host port8081 proxy \
  listen=tcp:0.0.0.0:8081 connect=tcp:127.0.0.1:8081
```

### Create Additional Podman Hosts

```bash
# Launch new container with podman profile
lxc launch ubuntu:22.04 podman-dev --profile default --profile podman

# Install Podman (use provided script)
./setup-podman-container.sh podman-dev
```

### Snapshot Podman Environments

```bash
# Snapshot entire Podman environment
lxc snapshot podman-host before-experiment

# Do risky things...
lxc exec podman-host -- podman system prune -af

# Restore if needed
lxc restore podman-host before-experiment
```

---

## 🔧 Configuration

### Profiles

```bash
# List profiles
lxc profile list

# Show profile config
lxc profile show default

# Create new profile
lxc profile create myprofile

# Apply profile to container
lxc launch ubuntu:22.04 web --profile default --profile myprofile
```

### Resource Limits

```bash
# Set CPU limit
lxc config set mycontainer limits.cpu 2

# Set memory limit
lxc config set mycontainer limits.memory 1GB

# View config
lxc config show mycontainer
```

### Network Configuration

```bash
# List networks
lxc network list

# Show network
lxc network show lxdbr0

# Create new network
lxc network create mybridge ipv4.address=10.30.30.1/24 ipv4.nat=true
```

### Storage

```bash
# List storage pools
lxc storage list

# Show storage details
lxc storage show default

# Create container on specific pool
lxc launch ubuntu:22.04 mycontainer --storage mypool
```

---

## 🧪 Test Suites

All configurations include comprehensive test suites covering installation, permissions, and functionality.

**Total: 130 tests across all configurations**

### Standard LXD Tests (47 tests)

```bash
./test-lxd-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| LXD Installation | 5 | Snap, daemon, socket, user group |
| Storage | 2 | Pool exists, usable |
| Networking | 4 | Bridge, IPv4, NAT, interface |
| Profiles | 4 | Default profile, devices, examples |
| Images | 3 | Remotes configured, cached images |
| Web Container | 6 | Container running, HTTP access |
| Container Ops | 4 | Exec, internet, file push/pull |
| Snapshots | 3 | Create, list, delete |
| Security | 3 | AppArmor, namespaces, cgroups |
| API Access | 2 | HTTPS listening, address |
| Permissions | 3 | Home ownership, user access, examples |
| Resources | 2 | Memory, disk |
| Common Issues | 3 | Snap refresh, DNS, health |

### Docker-in-LXD Tests (39 tests)

```bash
./test-docker-in-lxd-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| LXD Installation | 3 | Snap, daemon, user group |
| Docker Profile | 4 | Profile exists, security settings |
| Docker Host | 5 | Container running, network, proxy |
| Docker Inside | 4 | Docker installed, daemon running |
| Docker Containers | 3 | Nginx running, image pulled |
| Docker Operations | 3 | Run, pull, networking |
| HTTP Access | 3 | VM and host HTTP access |
| Docker Compose | 1 | Compose installed |
| Security | 3 | Nesting, AppArmor, cgroups |
| Permissions | 5 | Home ownership, LXC access, socket, docker group, filesystem |
| Resources | 2 | Memory available |

### Podman-in-LXD Tests (44 tests)

```bash
./test-podman-in-lxd-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| LXD Installation | 3 | Snap, daemon, user group |
| Podman Profile | 4 | Profile exists, security settings |
| Podman Host | 5 | Container running, network, proxy |
| Podman Inside | 4 | Podman installed, functional, compose |
| Podman Containers | 3 | Nginx running, image pulled |
| Podman Operations | 3 | Run, pull, networking |
| Rootless Podman | 3 | subuid/subgid, rootless execution |
| HTTP Access | 3 | VM and host HTTP access |
| Docker Compatibility | 2 | CLI compatible, socket available |
| Security | 3 | Nesting, cgroups, fuse-overlayfs |
| Permissions | 6 | Home ownership, LXC access, socket, UID mapping, filesystem, container home |
| Resources | 2 | Memory available |

### Test Coverage Summary

| Test Area | LXD | Docker-in-LXD | Podman-in-LXD |
|-----------|-----|---------------|---------------|
| Post-Installation | ✅ LXD 6.1 | ✅ LXD 6.1 + Docker 29.x | ✅ LXD 6.1 + Podman 3.4 |
| Permissions | ✅ 3 tests | ✅ 5 tests | ✅ 6 tests |
| Networking | ✅ HTTP verified | ✅ HTTP verified | ✅ HTTP verified |
| Security | ✅ AppArmor, cgroups | ✅ Nesting, cgroups | ✅ Nesting, rootless |
| Container Ops | ✅ Full lifecycle | ✅ Docker commands | ✅ Podman + rootless |

---

## ⚠️ Troubleshooting

### Common LXD Issues

#### "Permission denied" errors
```bash
# Ensure user is in lxd group
groups
sudo usermod -aG lxd $USER
newgrp lxd
```

#### Container can't access internet
```bash
# Check/enable NAT
lxc network get lxdbr0 ipv4.nat
lxc network set lxdbr0 ipv4.nat true
lxc restart mycontainer
```

#### "Error: not found" when launching
```bash
# Use full image path
lxc launch images:ubuntu/22.04 mycontainer
```

#### LXD daemon not responding
```bash
snap services lxd
sudo snap restart lxd
sudo journalctl -u snap.lxd.daemon
```

### Docker-in-LXD Issues

#### Docker daemon won't start
```bash
# Check nesting is enabled
lxc config get docker-host security.nesting
# Should return: true

# Check Docker service
lxc exec docker-host -- systemctl status docker
lxc exec docker-host -- journalctl -u docker -n 50
```

#### Overlay filesystem errors
```bash
# Verify setxattr setting
lxc config get docker-host security.syscalls.intercept.setxattr
# Should return: true
```

#### Docker networking issues
```bash
lxc exec docker-host -- docker network ls
lxc exec docker-host -- systemctl restart docker
```

### Podman-in-LXD Issues

#### Podman containers fail to start
```bash
# Check nesting is enabled
lxc config get podman-host security.nesting
# Should return: true

# Check Podman info
lxc exec podman-host -- podman info
```

#### Rootless Podman not working
```bash
# Check subuid/subgid configuration
lxc exec podman-host -- cat /etc/subuid
lxc exec podman-host -- cat /etc/subgid
# Should show: ubuntu:100000:65536

# Check slirp4netns
lxc exec podman-host -- which slirp4netns
```

#### Overlay filesystem errors
```bash
# Verify setxattr setting
lxc config get podman-host security.syscalls.intercept.setxattr

# Check fuse-overlayfs for rootless
lxc exec podman-host -- which fuse-overlayfs
```

#### Podman socket issues
```bash
# Enable and start socket
lxc exec podman-host -- systemctl enable --now podman.socket
lxc exec podman-host -- systemctl status podman.socket
```

### VM Management

```bash
# List VMs
multipass list

# Stop/Start VM
multipass stop lxd-vm
multipass start lxd-vm

# Delete VM
multipass delete lxd-vm && multipass purge

# Get VM info
multipass info lxd-vm
```

---

## 📊 Comparison

### LXD vs Docker vs Podman

| Feature | LXD | Docker | Podman |
|---------|-----|--------|--------|
| Container Type | System | Application | Application |
| Init System | Full (systemd) | Single process | Single process |
| VM Support | Yes | No | No |
| Clustering | Built-in | Swarm/K8s | No |
| Snapshots | Yes | Limited | No |
| Live Migration | Yes | No | No |
| OCI Images | Limited | Yes | Yes |

### Docker-in-LXD vs Direct Docker

| Aspect | Docker-in-LXD | Direct Docker |
|--------|---------------|---------------|
| Isolation | Higher (nested) | Standard |
| Snapshots | Full environment | Individual containers |
| Multi-tenant | Easy | Complex |
| Performance | Slight overhead | Native |
| Complexity | Higher | Lower |

### When to Use What

**Use Standard LXD when:**
- Need full Linux systems (not just apps)
- Want VM-like isolation with container efficiency
- Require snapshots and live migration
- Building development environments

**Use Docker-in-LXD when:**
- Need isolated Docker environments
- Want to snapshot entire Docker setups
- Multi-tenant Docker hosting
- CI/CD with clean Docker states
- Learning Docker without affecting host

**Use Podman-in-LXD when:**
- Need daemonless container runtime
- Prefer rootless containers by default
- Want Docker CLI compatibility without Docker daemon
- Require better security with user namespaces
- Need systemd integration for containers
- Want to snapshot entire Podman environments

---

## 📝 Configuration Summary

### Pinned Versions (for stability)

All configurations use pinned package versions for reproducible deployments:

| Component | Version | Channel/Source |
|-----------|---------|----------------|
| LXD | 6.1 | snap 6.1/stable |
| Docker CE | 29.x | docker.com repo |
| Docker Compose | v5.x | docker-compose-plugin |
| Podman | 3.4.x | Ubuntu 22.04 repo |
| podman-compose | 1.5.x | pip3 |
| Ubuntu (container) | 22.04 LTS | images:ubuntu/22.04 |

### Standard LXD (lxd-vm)

| Setting | Value |
|---------|-------|
| VM Resources | 2 CPU, 2GB RAM, 15GB disk |
| LXD Version | 6.1 (snap, pinned) |
| Storage Pool | `default` (dir driver) |
| Network Bridge | `lxdbr0` (10.10.10.1/24) |
| Pre-deployed | `web-test` container (nginx) |
| Exposed Port | 8080 → nginx |

### Docker-in-LXD (docker-in-lxd-vm)

| Setting | Value |
|---------|-------|
| VM Resources | 2 CPU, 4GB RAM, 20GB disk |
| LXD Version | 6.1 (snap, pinned) |
| Network Bridge | `lxdbr0` (10.20.20.1/24) |
| Docker Profile | `docker` (security.nesting) |
| LXD Container | `docker-host` |
| Docker Version | 29.x (from docker.com) |
| Docker Compose | v5.x |
| Pre-deployed | nginx:alpine container |
| Exposed Port | 8080 → Docker nginx |

### Podman-in-LXD (podman-in-lxd-vm)

| Setting | Value |
|---------|-------|
| VM Resources | 2 CPU, 4GB RAM, 20GB disk |
| LXD Version | 6.1 (snap, pinned) |
| Network Bridge | `lxdbr0` (10.30.30.1/24) |
| Podman Profile | `podman` (security.nesting) |
| LXD Container | `podman-host` |
| Podman Version | 3.4.x (Ubuntu 22.04) |
| podman-compose | 1.5.x (via pip3) |
| Pre-deployed | nginx:alpine container |
| Rootless Support | Yes (slirp4netns, fuse-overlayfs, loginctl linger) |
| Exposed Port | 8080 → Podman nginx |

---

## 📚 Reference

### Documentation
- [LXD Documentation](https://documentation.ubuntu.com/lxd/en/latest/)
- [Linux Containers](https://linuxcontainers.org/)
- [Docker in LXD](https://documentation.ubuntu.com/lxd/en/latest/howto/instances_docker/)
- [Podman Documentation](https://podman.io/docs)
- [Multipass Documentation](https://multipass.run/docs)

### Source Code
- [LXD GitHub](https://github.com/canonical/lxd)
- [Podman GitHub](https://github.com/containers/podman)

### Remote Access (API)
```bash
# API available at https://<vm-ip>:8443
# Uses certificate-based authentication (LXD 6.x)

# Generate token for remote client
lxc config trust add --name myclient
```

---

**System containers, Docker, and Podman environments made simple** 📦🐳🦭
