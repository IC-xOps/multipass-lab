# 🖥️ Multipass Lab

A collection of cloud-init configurations for provisioning container runtime environments on **Ubuntu VMs** via [Multipass](https://multipass.run/) on **macOS**. Each lab deploys a fully configured, tested environment — from standard Docker to gVisor-sandboxed containers and nested LXD setups.

---

## 📋 Overview

| Lab | Description | Cloud-init Configs | Tests |
|-----|-------------|-------------------|-------|
| [🐳 Docker](Docker/) | Standard Docker Engine & Docker Rootless | `docker.yaml`, `docker-rootless.yaml` | 38 + rootless suite |
| [🛡️ gVisor](gVisor/) | Sandboxed containers via gVisor + containerd + nerdctl | `docker-in-gvisor.yaml` | 52 |
| [📦 LXD](lxd/) | System containers & VMs — standalone, Docker-in-LXD, Podman-in-LXD | `lxd.yaml`, `docker-in-lxd.yaml`, `podman-in-lxd.yaml` | 47 + 39 + 44 |
| [🦭 Podman](Podman/) | Rootless Podman & Docker-in-Podman | `podman.yaml`, `docker-in-podman.yaml` | 41 + Docker-in-Podman suite |
| [🔧 Incus](incus/) | System containers & VMs — standalone, Docker-in-Incus, Podman-in-Incus | `incus.yaml`, `docker-in-incus.yaml`, `podman-in-incus.yaml` | 47 + 39 + 44 |

> **Total:** 11 cloud-init configurations · 11 test suites

---

## 🏗️ Architecture

Every lab follows the same pattern: a Multipass VM is launched with a cloud-init YAML that fully provisions the environment on first boot.

```
┌──────────────────────────────────────────────────────┐
│  macOS Host                                          │
│  └─ Multipass                                        │
│      ├─ docker-vm          (Docker Engine + Swarm)   │
│      ├─ docker-rootless-vm (Rootless Docker)         │
│      ├─ docker-in-gvisor-vm(gVisor + containerd)     │
│      ├─ lxd-vm             (LXD + nginx)             │
│      ├─ docker-in-lxd-vm   (Docker inside LXD)       │
│      ├─ podman-in-lxd-vm   (Podman inside LXD)       │
│      ├─ podman-vm            (Rootless Podman)          │
│      ├─ docker-in-podman-vm  (Docker inside Podman)     │
│      ├─ incus-vm             (Incus + nginx)            │
│      ├─ docker-in-incus-vm   (Docker inside Incus)      │
│      └─ podman-in-incus-vm   (Podman inside Incus)      │
└──────────────────────────────────────────────────────────┘
```

---

## 🚀 Prerequisites

- **macOS** with [Multipass](https://multipass.run/) installed
- Internet connection for package downloads

```bash
brew install multipass
```

---

## ⚡ Quick Start

Each lab can be launched with a single command. Navigate to the corresponding directory, then:

```bash
# Example: Standard Docker
cd Docker
multipass launch 24.04 -n docker-vm -c 2 -m 4G -d 20G --cloud-init docker.yaml

# Wait for provisioning to complete
multipass exec docker-vm -- cloud-init status --wait

# Run the test suite
./test-docker-vm.sh
```

See the individual lab READMEs for specific launch commands and resource requirements.

---

## 📂 Project Structure

```
Multipass-lab/
├── README.md                          # ← You are here
│
├── Docker/
│   ├── docker.yaml                    # Standard Docker Engine + Swarm + Compose
│   ├── docker-rootless.yaml           # Docker daemon running without root
│   ├── test-docker-vm.sh              # 38-test validation suite
│   ├── test-docker-rootless-vm.sh     # Rootless-specific test suite
│   └── README.md
│
├── gVisor/
│   ├── docker-in-gvisor.yaml          # gVisor (runsc) + containerd + nerdctl + Caddy
│   ├── test-gvisor-vm.sh              # 52-test validation suite
│   ├── DEPLOYMENT_SUMMARY.md
│   └── README.md
│
├── lxd/
│   ├── lxd.yaml                       # Standard LXD with nginx container
│   ├── docker-in-lxd.yaml             # Docker Engine inside an LXD container
│   ├── podman-in-lxd.yaml             # Podman inside an LXD container
│   ├── test-lxd-vm.sh                 # 47-test validation suite
│   ├── test-docker-in-lxd-vm.sh       # 39-test validation suite
│   ├── test-podman-in-lxd-vm.sh       # 44-test validation suite
│   └── README.md
│
├── Podman/
│   ├── podman.yaml                    # Rootless Podman with Docker compat
│   ├── docker-in-podman.yaml          # Docker Engine inside a Podman container
│   ├── test-podman-vm.sh              # 41-test validation suite
│   ├── test-docker-in-podman-vm.sh    # Docker-in-Podman test suite
│   └── README.md
│
└── incus/
    ├── incus.yaml                     # Standard Incus with nginx container
    ├── docker-in-incus.yaml           # Docker Engine inside an Incus container
    ├── podman-in-incus.yaml           # Podman inside an Incus container
    ├── test-incus-vm.sh               # 47-test validation suite
    ├── test-docker-in-incus-vm.sh     # 39-test validation suite
    ├── test-podman-in-incus-vm.sh     # 44-test validation suite
    └── README.md
```

---

## 🧪 Test Suites

Every lab ships with a comprehensive shell-based test suite that validates the full stack — from VM status and cloud-init completion to runtime functionality, networking, permissions, and common-issue detection.

```bash
# Run any test suite from the lab directory
./test-docker-vm.sh
./test-docker-rootless-vm.sh
./test-gvisor-vm.sh
./test-lxd-vm.sh
./test-docker-in-lxd-vm.sh
./test-podman-in-lxd-vm.sh
./test-podman-vm.sh
./test-docker-in-podman-vm.sh
./test-incus-vm.sh
./test-docker-in-incus-vm.sh
./test-podman-in-incus-vm.sh
```

### Test Categories (common across suites)

| Category | What's Validated |
|----------|------------------|
| **Prerequisites** | Multipass installation |
| **VM Status** | VM exists, is running |
| **Cloud-Init** | Provisioning completed successfully |
| **Installation** | Runtime binaries, versions, plugins |
| **Post-Installation** | Daemon config, log rotation, storage drivers, boot services |
| **Permissions** | User groups, socket ownership, directory permissions |
| **Functionality** | Pull images, run containers, volumes, bind mounts, port mapping |
| **Networking** | Internet access, DNS resolution, registry connectivity |
| **Resources** | Disk space, memory, storage pool usage |
| **Common Issues** | Zombie containers, dangling images, invalid configs |

---

## 🔬 Lab Details

### 🐳 Docker

Two configurations targeting different security postures:

| Configuration | Daemon | Key Components | Security |
|---------------|--------|----------------|----------|
| **Standard** | Root | Docker CE, Compose, Swarm, Containerd | Standard |
| **Rootless** | User-space | Docker CE (rootless), Compose | Enhanced |

**VM Resources:** 2 CPUs · 4 GB RAM · 20 GB Disk · Ubuntu 24.04

→ [Full documentation](Docker/README.md)

---

### 🛡️ gVisor

Containers sandboxed in a user-space kernel for maximum isolation:

| Component | Version |
|-----------|---------|
| gVisor (runsc) | 20240115.0 |
| containerd | Latest |
| nerdctl | 1.7.6 |
| CNI plugins | 1.4.1 |
| Demo app | Caddy 2.7.6-alpine |

**VM Resources:** 2 CPUs · 4 GB RAM · 20 GB Disk · Ubuntu 24.04

→ [Full documentation](gVisor/README.md)

---

### 📦 LXD

Full system containers and VMs, plus nested container runtimes:

| Configuration | Nesting | Use Case |
|---------------|---------|----------|
| **Standard LXD** | — | System containers & VMs with nginx |
| **Docker-in-LXD** | Docker inside LXD container | Isolated Docker environments |
| **Podman-in-LXD** | Podman inside LXD container | Daemonless, rootless containers |

**VM Resources:** 2 CPUs · 2–4 GB RAM · 15–20 GB Disk · Ubuntu 24.04

→ [Full documentation](lxd/README.md)

---

### 🦭 Podman

Daemonless, rootless container engine with Docker compatibility:

| Configuration | Key Features |
|---------------|-------------|
| **Podman VM** | Rootless Podman, `podman-docker` alias, socket support, Podman Desktop integration |
| **Docker-in-Podman** | Full Docker Engine running inside a Podman-managed container |

**VM Resources:** 2 CPUs · 4 GB RAM · 20 GB Disk · Ubuntu 24.04

→ [Full documentation](Podman/README.md)

---

### 🔧 Incus

Community-driven LXD fork with system containers, VMs, and nested runtimes:

| Configuration | Nesting | Use Case |
|---------------|---------|----------|
| **Standard Incus** | — | System containers & VMs with nginx |
| **Docker-in-Incus** | Docker inside Incus container | Isolated Docker environments |
| **Podman-in-Incus** | Podman inside Incus container | Daemonless, rootless containers |

**VM Resources:** 2 CPUs · 2–4 GB RAM · 15–20 GB Disk · Ubuntu 24.04  
**Installation:** Zabbly APT repository (not snap)

→ [Full documentation](incus/README.md)

---

## 🧹 Cleanup

Remove any lab VM when you're done:

```bash
# Stop and delete a specific VM
multipass stop <vm-name>
multipass delete <vm-name>
multipass purge

# Or remove all VMs at once
multipass delete --all
multipass purge
```

---

## 📄 License

This project is provided as-is for educational and development purposes.
