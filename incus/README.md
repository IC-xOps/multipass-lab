# 🔧 Incus - System Containers & Virtual Machines

A complete Incus environment running on Ubuntu via Multipass. Incus is a modern, community-driven fork of LXD maintained by the [Linux Containers](https://linuxcontainers.org/incus/) project. This repository provides three configurations:

1. **Standard Incus** - System containers and VMs with pre-deployed nginx
2. **Docker-in-Incus** - Run Docker inside Incus containers for isolated Docker environments
3. **Podman-in-Incus** - Run Podman inside Incus containers for daemonless container runtime

---

## 📑 Table of Contents

- [What is Incus?](#-what-is-incus)
- [Incus vs LXD](#-incus-vs-lxd)
- [Prerequisites](#-prerequisites)
- [Quick Start: Standard Incus](#-quick-start-standard-incus)
- [Quick Start: Docker-in-Incus](#-quick-start-docker-in-incus)
- [Quick Start: Podman-in-Incus](#-quick-start-podman-in-incus)
- [File Structure](#-file-structure)
- [Basic Usage](#-basic-usage)
- [Docker-in-Incus Details](#-docker-in-incus-details)
- [Podman-in-Incus Details](#-podman-in-incus-details)
- [Configuration](#-configuration)
- [Test Suites](#-test-suites)
- [Troubleshooting](#-troubleshooting)
- [Reference](#-reference)

---

## 🚀 What is Incus?

Incus is a next-generation system container and virtual machine manager. It is a community fork of LXD, created after Canonical moved LXD under its corporate CLA. Incus is maintained by the same upstream Linux Containers project that originally created LXC and LXD.

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
| **OCI Containers** | Native support for OCI/Docker images |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   Incus Management Layer                    │
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

## 🔄 Incus vs LXD

| Aspect | Incus | LXD |
|--------|-------|-----|
| **Maintainer** | Linux Containers community | Canonical |
| **Installation** | Zabbly APT repository | Snap package |
| **CLI command** | `incus` (unified) | `lxc` (client) + `lxd` (daemon) |
| **User group** | `incus-admin` | `lxd` |
| **Bridge name** | `incusbr0` | `lxdbr0` |
| **Socket path** | `/var/lib/incus/unix.socket` | `/var/snap/lxd/common/lxd/unix.socket` |
| **Daemon** | `incusd` (systemd service) | `lxd` (snap service) |
| **Preseed** | `incus admin init --preseed` | `lxd init --preseed` |
| **OCI support** | Native OCI container support | Not built-in |
| **License** | Apache 2.0 | Apache 2.0 (with Canonical CLA) |

---

## 📋 Prerequisites

- **macOS** with [Multipass](https://multipass.run/) installed
- Internet connection for package downloads

| Setup | RAM | Disk | Use Case |
|-------|-----|------|----------|
| Standard Incus | 2GB+ | 15GB+ | System containers, basic usage |
| Docker-in-Incus | 4GB+ | 20GB+ | Nested Docker containers |
| Podman-in-Incus | 4GB+ | 20GB+ | Daemonless containers, rootless by default |

```bash
# Install Multipass on macOS
brew install multipass
```

---

## 🚀 Quick Start: Standard Incus

Standard Incus setup with a pre-deployed nginx container for immediate testing.

### 1. Create the VM

```bash
multipass launch 24.04 -n incus-vm -c 2 -m 2G -d 15G --cloud-init incus.yaml
```

### 2. Wait for Setup (~3-5 minutes)

```bash
multipass exec incus-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check Incus and containers
multipass exec incus-vm -- incus list

# Test HTTP access (nginx in web-test container)
curl http://$(multipass info incus-vm | grep IPv4 | awk '{print $2}'):8080
```

### 4. Run Tests

```bash
./test-incus-vm.sh
# Expected: 47 tests passed
```

### What Gets Deployed

```
┌─────────────────────────────────────────┐
│          Multipass VM (incus-vm)         │
│  ┌───────────────────────────────────┐  │
│  │             Incus                 │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │    web-test (container)     │  │  │
│  │  │         nginx:80            │  │  │
│  │  └─────────────────────────────┘  │  │
│  │          incusbr0 bridge          │  │
│  └───────────────────────────────────┘  │
│              Port 8080 → nginx          │
└─────────────────────────────────────────┘
```

---

## 🐳 Quick Start: Docker-in-Incus

Run Docker containers inside Incus system containers for isolated Docker environments.

### 1. Create the VM

```bash
multipass launch 24.04 -n docker-in-incus-vm -c 2 -m 4G -d 20G --cloud-init docker-in-incus.yaml
```

### 2. Wait for Setup (~5-10 minutes)

```bash
multipass exec docker-in-incus-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check Incus container with Docker
multipass exec docker-in-incus-vm -- incus list

# Check Docker inside the container
multipass exec docker-in-incus-vm -- incus exec docker-host -- docker ps

# Test HTTP (nginx running in Docker, inside Incus)
curl http://$(multipass info docker-in-incus-vm | grep IPv4 | awk '{print $2}'):8080
```

### 4. Run Tests

```bash
./test-docker-in-incus-vm.sh
# Expected: 39 tests passed
```

### What Gets Deployed

```
┌─────────────────────────────────────────────────────────────┐
│             Multipass VM (docker-in-incus-vm)               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                       Incus                           │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │        docker-host (Incus container)            │  │  │
│  │  │  ┌─────────────────────────────────────────┐   │  │  │
│  │  │  │              Docker Engine              │   │  │  │
│  │  │  │  ┌───────────┐  ┌───────────┐          │   │  │  │
│  │  │  │  │   nginx   │  │  (more)   │          │   │  │  │
│  │  │  │  │ container │  │containers │          │   │  │  │
│  │  │  │  └───────────┘  └───────────┘          │   │  │  │
│  │  │  └─────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                    incusbr0 bridge                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                   Port 8080 → Docker nginx                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🦭 Quick Start: Podman-in-Incus

Run Podman containers inside Incus system containers for daemonless, rootless container runtime.

### 1. Create the VM

```bash
multipass launch 24.04 -n podman-in-incus-vm -c 2 -m 4G -d 20G --cloud-init podman-in-incus.yaml
```

### 2. Wait for Setup (~5-8 minutes)

```bash
multipass exec podman-in-incus-vm -- cloud-init status --wait
```

### 3. Verify Installation

```bash
# Check Incus container with Podman
multipass exec podman-in-incus-vm -- incus list

# Check Podman inside the container
multipass exec podman-in-incus-vm -- incus exec podman-host -- podman ps

# Test HTTP (nginx running in Podman, inside Incus)
curl http://$(multipass info podman-in-incus-vm | grep IPv4 | awk '{print $2}'):8080
```

### 4. Run Tests

```bash
./test-podman-in-incus-vm.sh
# Expected: 44 tests passed
```

### What Gets Deployed

```
┌─────────────────────────────────────────────────────────────┐
│            Multipass VM (podman-in-incus-vm)                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                       Incus                           │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │        podman-host (Incus container)            │  │  │
│  │  │  ┌─────────────────────────────────────────┐   │  │  │
│  │  │  │           Podman (daemonless)           │   │  │  │
│  │  │  │  ┌───────────┐  ┌───────────┐          │   │  │  │
│  │  │  │  │   nginx   │  │  (more)   │          │   │  │  │
│  │  │  │  │ container │  │containers │          │   │  │  │
│  │  │  │  └───────────┘  └───────────┘          │   │  │  │
│  │  │  └─────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                    incusbr0 bridge                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                  Port 8080 → Podman nginx                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 File Structure

```
incus/
├── incus.yaml                      # Cloud-init: Standard Incus setup
├── docker-in-incus.yaml            # Cloud-init: Docker inside Incus
├── podman-in-incus.yaml            # Cloud-init: Podman inside Incus
├── test-incus-vm.sh                # Test suite for incus-vm (47 tests)
├── test-docker-in-incus-vm.sh      # Test suite for docker-in-incus-vm (39 tests)
├── test-podman-in-incus-vm.sh      # Test suite for podman-in-incus-vm (44 tests)
└── README.md                       # This documentation
```

---

## 📖 Basic Usage

### Container Lifecycle

```bash
# Launch a new container
incus launch images:ubuntu/22.04 mycontainer

# List containers
incus list

# Get container info
incus info mycontainer

# Shell into container
incus exec mycontainer -- bash

# Stop/Start/Delete
incus stop mycontainer
incus start mycontainer
incus delete mycontainer --force
```

### Virtual Machines

```bash
# Launch a VM (add --vm flag)
incus launch images:ubuntu/22.04 myvm --vm

# List all (containers + VMs)
incus list

# Access VM
incus exec myvm -- bash

# VM console
incus console myvm
```

### Snapshots

```bash
# Create snapshot
incus snapshot create mycontainer snap1

# List snapshots
incus info mycontainer

# Restore from snapshot
incus snapshot restore mycontainer snap1

# Delete snapshot
incus snapshot delete mycontainer snap1
```

### Profiles

```bash
# List profiles
incus profile list

# Create profile
incus profile create myprofile

# Edit profile
incus profile edit myprofile

# Apply profile to container
incus launch images:ubuntu/22.04 mycontainer --profile default --profile myprofile
```

### File Operations

```bash
# Push file to container
incus file push local-file.txt mycontainer/tmp/

# Pull file from container
incus file pull mycontainer/tmp/file.txt ./

# Edit file in container
incus file edit mycontainer/etc/hostname
```

---

## 🐳 Docker-in-Incus Details

### How It Works

Incus containers with `security.nesting: true` allow running Docker inside them. The Docker profile also enables:
- `security.syscalls.intercept.mknod` — for device node creation
- `security.syscalls.intercept.setxattr` — for extended attribute operations

### Docker Profile

```yaml
config:
  security.nesting: "true"
  security.syscalls.intercept.mknod: "true"
  security.syscalls.intercept.setxattr: "true"
```

### Create Additional Docker Hosts

```bash
# Using the docker profile
incus launch images:ubuntu/22.04 my-docker --profile default --profile docker

# Install Docker via helper script
./setup-docker-container.sh my-docker
```

### Access Docker Inside Incus

```bash
# Run docker commands inside the container
incus exec docker-host -- docker ps
incus exec docker-host -- docker images
incus exec docker-host -- docker compose version

# Run a new container
incus exec docker-host -- docker run -d --name myapp -p 8081:80 nginx
```

---

## 🦭 Podman-in-Incus Details

### How It Works

Podman runs daemonless inside the Incus container. The same nesting profile is used, and rootless operation is configured with `subuid`/`subgid` mappings for the `ubuntu` user.

### Rootless vs Root Podman

```bash
# Root Podman (runs as root inside the container)
incus exec podman-host -- podman run --rm docker.io/alpine echo hello

# Rootless Podman (runs as ubuntu user)
incus exec podman-host -- sudo -u ubuntu podman run --rm docker.io/alpine echo hello
```

### Create Additional Podman Hosts

```bash
# Using the podman profile
incus launch images:ubuntu/22.04 my-podman --profile default --profile podman

# Install Podman via helper script
./setup-podman-container.sh my-podman
```

---

## ⚙️ Configuration

### Network Configuration

All three setups use an Incus managed bridge:

| Setup | Bridge IP | NAT |
|-------|-----------|-----|
| Standard | `10.10.10.1/24` | Enabled |
| Docker-in-Incus | `10.20.20.1/24` | Enabled |
| Podman-in-Incus | `10.30.30.1/24` | Enabled |

### Storage

All setups use the `dir` storage driver for maximum compatibility. For production use, consider:

```bash
# Create a ZFS pool
incus storage create mypool zfs

# Create a Btrfs pool
incus storage create mypool btrfs
```

### Incus Installation (Zabbly)

Incus is installed from the [Zabbly repository](https://github.com/zabbly/incus), which provides up-to-date packages for Ubuntu:

```bash
# Repository: Incus 6.x LTS
# Source: https://pkgs.zabbly.com/incus/lts-6.0
# Signed by: /etc/apt/keyrings/zabbly.asc
```

---

## 🧪 Test Suites

### Standard Incus (47 tests)

```bash
./test-incus-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| Incus Installation | 6 | Version, daemon, group, socket, Zabbly repo |
| Storage | 2 | Default pool exists, usable |
| Networking | 4 | Bridge exists, IPv4, NAT, interface |
| Profiles | 4 | Default profile, disk, network, examples |
| Images | 2 | Remote servers, cached images |
| Web Container | 6 | Exists, running, network, proxy, HTTP |
| Container Ops | 4 | Exec, internet, file push/pull |
| Snapshots | 3 | Create, list, delete |
| Security | 3 | AppArmor, unprivileged, cgroup |
| API Access | 2 | HTTPS listening, address configured |
| Permissions | 3 | Home dir, user access, examples |
| Resources | 2 | Memory, disk |
| Common Issues | 3 | Service health, DNS, container health |

### Docker-in-Incus (39 tests)

```bash
./test-docker-in-incus-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| Incus Installation | 3 | Version, daemon, group |
| Docker Profile | 4 | Exists, nesting, mknod, setxattr |
| Docker Host | 5 | Exists, running, profile, network, proxy |
| Docker Inside | 4 | Installed, daemon running, functional, containerd |
| Docker Containers | 3 | Nginx exists, running, image |
| Docker Operations | 3 | Run, pull, networking |
| HTTP Access | 3 | From VM, from host, content |
| Docker Compose | 1 | Installed |
| Security | 3 | Nesting, AppArmor, cgroup |
| Permissions | 5 | Home dir, user, socket, docker group, filesystem |
| Resources | 2 | VM memory, container memory |

### Podman-in-Incus (44 tests)

```bash
./test-podman-in-incus-vm.sh [vm-name]
```

| Category | Tests | Description |
|----------|-------|-------------|
| VM Accessibility | 3 | VM exists, running, shell access |
| Incus Installation | 3 | Version, daemon, group |
| Podman Profile | 4 | Exists, nesting, mknod, setxattr |
| Podman Host | 5 | Exists, running, profile, network, proxy |
| Podman Inside | 4 | Installed, functional, compose, slirp4netns |
| Podman Containers | 3 | Nginx exists, running, image |
| Podman Operations | 3 | Run, pull, networking |
| Rootless Podman | 3 | subuid, subgid, rootless run |
| HTTP Access | 3 | From VM, from host, content |
| Docker Compat | 2 | CLI compatibility, socket |
| Security | 3 | Nesting, cgroup, fuse-overlayfs |
| Permissions | 6 | Home dir, user, socket, UID mapping, filesystem, container home |
| Resources | 2 | VM memory, container memory |

---

## 🔧 Troubleshooting

### Incus daemon not starting

```bash
# Check service status
multipass exec incus-vm -- systemctl status incus
multipass exec incus-vm -- journalctl -u incus -n 50

# Restart Incus
multipass exec incus-vm -- sudo systemctl restart incus
```

### Permission denied (user not in group)

```bash
# Verify group membership
multipass exec incus-vm -- groups

# Add user to incus-admin group
multipass exec incus-vm -- sudo usermod -aG incus-admin ubuntu

# Apply new group (re-login or use newgrp)
multipass exec incus-vm -- newgrp incus-admin
```

### Container not getting IP

```bash
# Check bridge
multipass exec incus-vm -- incus network list
multipass exec incus-vm -- incus network show incusbr0

# Check DHCP
multipass exec incus-vm -- incus network get incusbr0 ipv4.dhcp

# Restart container
multipass exec incus-vm -- incus restart web-test
```

### Docker not starting inside Incus container

```bash
# Verify nesting is enabled
multipass exec docker-in-incus-vm -- incus config show docker-host | grep nesting

# Check Docker logs
multipass exec docker-in-incus-vm -- incus exec docker-host -- journalctl -u docker -n 50

# Verify container security profile
multipass exec docker-in-incus-vm -- incus profile show docker
```

### Podman rootless not working

> **⚠️ Ubuntu 24.04 AppArmor User Namespace Restriction**
>
> Ubuntu 24.04 introduced a new kernel parameter `kernel.apparmor_restrict_unprivileged_userns=1` that blocks
> unprivileged users from creating user namespaces. Rootless Podman relies on user namespaces for UID/GID
> mapping, so this restriction causes a `cannot clone: Permission denied` error when running containers as
> a non-root user inside nested Incus containers.
>
> The `podman-in-incus.yaml` cloud-init already handles this by writing a sysctl override
> (`/etc/sysctl.d/99-userns.conf`) that sets `kernel.apparmor_restrict_unprivileged_userns=0` at the **VM level**
> (containers share the host kernel, so this must be set on the VM, not inside the container).
>
> If you are provisioning manually or hit this on an existing VM, apply the fix with:
> ```bash
> multipass exec podman-in-incus-vm -- sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
> # To persist across reboots:
> multipass exec podman-in-incus-vm -- sudo bash -c \
>   'echo "kernel.apparmor_restrict_unprivileged_userns=0" > /etc/sysctl.d/99-userns.conf'
> ```

```bash
# Check subuid/subgid
multipass exec podman-in-incus-vm -- incus exec podman-host -- cat /etc/subuid
multipass exec podman-in-incus-vm -- incus exec podman-host -- cat /etc/subgid

# Check AppArmor userns restriction (1 = restricted, 0 = allowed)
multipass exec podman-in-incus-vm -- cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns

# Check user linger
multipass exec podman-in-incus-vm -- incus exec podman-host -- loginctl show-user ubuntu | grep Linger

# Verify fuse-overlayfs storage config exists for rootless user
multipass exec podman-in-incus-vm -- incus exec podman-host -- \
  su - ubuntu -c 'cat ~/.config/containers/storage.conf'

# Reset podman storage
multipass exec podman-in-incus-vm -- incus exec podman-host -- sudo -u ubuntu podman system reset
```

### Port 8080 not accessible

```bash
# Check proxy device
multipass exec incus-vm -- incus config device show web-test

# Re-add proxy device
multipass exec incus-vm -- incus config device remove web-test http
multipass exec incus-vm -- incus config device add web-test http proxy listen=tcp:0.0.0.0:8080 connect=tcp:127.0.0.1:80
```

---

## 📚 Reference

### Useful Commands Cheat Sheet

```bash
# === Instance Management ===
incus list                              # List all instances
incus info <name>                       # Detailed instance info
incus config show <name>                # Instance configuration
incus config edit <name>                # Edit configuration

# === Images ===
incus image list                        # List local images
incus image list images:                # List remote images
incus image list images: ubuntu         # Search for Ubuntu images
incus image delete <fingerprint>        # Delete cached image

# === Network ===
incus network list                      # List networks
incus network show incusbr0             # Network details
incus network info incusbr0             # Network info with leases

# === Storage ===
incus storage list                      # List pools
incus storage info default              # Pool details with usage

# === Profiles ===
incus profile list                      # List profiles
incus profile show default              # Profile details
incus profile assign <inst> default,docker  # Assign profiles

# === Remote Management ===
incus remote list                       # List remotes
incus remote add myserver <ip>          # Add remote server
incus list myserver:                    # List remote instances

# === Admin ===
incus admin init                        # Interactive setup
incus admin init --preseed < file.yaml  # Preseed setup
incus admin sql global "SELECT * FROM instances"  # Query DB
```

### Links

- [Incus Documentation](https://linuxcontainers.org/incus/docs/main/)
- [Incus GitHub](https://github.com/lxc/incus)
- [Zabbly Incus Packages](https://github.com/zabbly/incus)
- [Linux Containers](https://linuxcontainers.org/)
- [Incus Image Server](https://images.linuxcontainers.org/)

---

## 🧹 Cleanup

```bash
# Remove a specific VM
multipass stop incus-vm && multipass delete incus-vm && multipass purge

# Remove all Incus VMs
multipass stop incus-vm docker-in-incus-vm podman-in-incus-vm
multipass delete incus-vm docker-in-incus-vm podman-in-incus-vm
multipass purge
```
