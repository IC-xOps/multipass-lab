# 🛡️ Docker-in-gVisor VM

Run Docker containers with gVisor sandbox isolation on macOS using Multipass VMs. This setup provides an additional security layer by running containers in a user-space kernel, significantly reducing the attack surface.

## ✨ Features

| Component | Version | Description |
|-----------|---------|-------------|
| **gVisor (runsc)** | 20240115.0 | User-space kernel for container isolation |
| **containerd** | Latest (Ubuntu repos) | Container runtime with gVisor support |
| **nerdctl** | 1.7.6 | Docker-compatible CLI for containerd |
| **CNI plugins** | 1.4.1 | Container networking (bridge, host-local, etc.) |
| **Caddy** | 2.7.6-alpine | Demo webserver container |
| **Ubuntu** | 24.04 LTS | Base operating system |

**Additional Features:**
- Auto-start via systemd service
- Full container networking support
- 52 comprehensive tests

---

## 📋 Prerequisites

- macOS with [Multipass](https://multipass.run/) installed

```bash
brew install --cask multipass
```

---

## 🚀 Quick Start

### Step 1: Create the VM

```bash
cd gVisor
multipass launch --name docker-in-gvisor-vm \
  --cloud-init docker-in-gvisor.yaml \
  --cpus 2 --memory 4G --disk 20G
```

### Step 2: Verify Installation

```bash
# Check VM is running
multipass list

# Verify gVisor installed
multipass exec docker-in-gvisor-vm -- /usr/local/bin/runsc --version

# Verify nerdctl installed
multipass exec docker-in-gvisor-vm -- /usr/local/bin/nerdctl --version

# Check containers
multipass exec docker-in-gvisor-vm -- sudo /usr/local/bin/nerdctl ps
```

### Step 3: Access Caddy Webserver

```bash
# Get VM IP
VM_IP=$(multipass info docker-in-gvisor-vm | grep IPv4 | awk '{print $2}')

# Test webserver
curl http://$VM_IP:8080

# Or open in browser
open http://$VM_IP:8080
```

### Step 4: Run Tests (Optional)

```bash
./test-gvisor-vm.sh
```

---

## 🧪 Test Suite

The test suite validates all components of the gVisor VM setup.

```bash
./test-gvisor-vm.sh
```

**Test Categories:**

| Category | Description |
|----------|-------------|
| Prerequisites | Multipass installation verification |
| VM Status | VM exists, running, cloud-init completion |
| gVisor Installation | runsc binary, version, containerd-shim |
| containerd | Service status, config files, runtime setup |
| nerdctl | Binary installation, version, functionality |
| CNI Plugins | Directory structure, plugin installation |
| Caddy Deployment | Container exists and running |
| Webserver | Port listening, HTTP endpoints |
| Container Isolation | Process isolation, sandbox verification |
| Networking | External connectivity, DNS resolution |
| Auto-Start | Systemd service configuration |
| Resources | Disk space, memory usage |

---

## 📁 File Structure

**Local Files:**
```
gVisor/
├── docker-in-gvisor.yaml    # Cloud-init configuration
├── test-gvisor-vm.sh        # Test suite
└── README.md                # This documentation
```

**Inside the VM:**
```
/usr/local/bin/
├── runsc                      # gVisor runtime binary
├── containerd-shim-runsc-v1   # Containerd shim for gVisor
└── nerdctl                    # Container CLI

/etc/containerd/
├── config.toml                # Containerd configuration
└── runsc.toml                 # gVisor runtime options

/opt/cni/bin/                  # CNI network plugins

/home/ubuntu/
├── deploy-caddy.sh            # Caddy deployment script
├── test-gvisor.sh             # Quick validation script
└── caddy-data/                # Caddy config and web content

/etc/systemd/system/
└── caddy-gvisor.service       # Auto-start service
```

---

## 🛡️ Architecture

```
┌─────────────────────────────────────────────────┐
│  macOS Host                                     │
│  └─ Multipass                                   │
│      └─ Ubuntu 24.04 VM (docker-in-gvisor-vm)  │
│          └─ containerd                          │
│              ├─ runc runtime (standard)         │
│              └─ runsc runtime (gVisor)          │
│                  └─ Caddy Container             │
└─────────────────────────────────────────────────┘
```

### gVisor Security Model

gVisor provides an application kernel written in Go that runs in user-space:

| Feature | Description |
|---------|-------------|
| System call filtering | Only safe syscalls are allowed |
| Reduced attack surface | Kernel vulnerabilities are isolated |
| Platform: ptrace | Uses ptrace for broad compatibility |
| User-space execution | Container processes run in gVisor's sandbox |

### Component Responsibilities

| Component | Role |
|-----------|------|
| **runsc** | gVisor runtime implementing OCI spec |
| **containerd** | Container lifecycle management |
| **containerd-shim-runsc-v1** | Bridge between containerd and runsc |
| **nerdctl** | Docker-compatible CLI for containerd |
| **CNI plugins** | Container networking |

---

## 🌐 Caddy Webserver

The Caddy container serves the following endpoints:

| Endpoint | Port | Description |
|----------|------|-------------|
| `/` | 8080 | Homepage with gVisor information |
| `/health` | 8080 | Health check (returns 200 OK) |
| `/api/info` | 8080 | Server information API |

**Access from host:**
```bash
VM_IP=$(multipass info docker-in-gvisor-vm | grep IPv4 | awk '{print $2}')

# Homepage
curl http://$VM_IP:8080

# Health check
curl http://$VM_IP:8080/health

# API info
curl http://$VM_IP:8080/api/info
```

---

## 🔧 Container Management

### Basic Commands

```bash
# SSH into VM
multipass shell docker-in-gvisor-vm

# List containers
sudo nerdctl ps

# View logs
sudo nerdctl logs caddy

# Restart container
sudo nerdctl restart caddy

# Stop container
sudo nerdctl stop caddy

# Remove container
sudo nerdctl rm caddy
```

### Run Container with gVisor Runtime

```bash
# Run with gVisor isolation
sudo nerdctl run -d \
  --name my-app \
  --runtime io.containerd.runsc.v1 \
  -p 8080:80 \
  nginx:alpine

# Verify runtime
sudo nerdctl inspect my-app --format '{{.State.Runtime}}'
```

### Run Container with Standard Runtime

```bash
# Run with standard runc (no gVisor)
sudo nerdctl run -d \
  --name my-app \
  -p 8080:80 \
  nginx:alpine
```

### Docker-Compatible Commands

```bash
# Pull images
sudo nerdctl pull alpine:latest

# Run containers
sudo nerdctl run --rm alpine echo "Hello"

# Build images
sudo nerdctl build -t myapp:latest .

# Manage volumes
sudo nerdctl volume ls
sudo nerdctl volume create mydata

# Manage networks
sudo nerdctl network ls
sudo nerdctl network create mynet
```

---

## ⚙️ Configuration

### gVisor Runtime Options

File: `/etc/containerd/runsc.toml`

```toml
[runsc_config]
platform = "ptrace"        # Options: ptrace, kvm
network = "host"           # Network mode
file-access = "exclusive"  # File access mode
overlay = false            # Use overlay filesystem
ignore-cgroups = true      # Compatibility with cgroup v2
```

**Platform Options:**
| Platform | Compatibility | Performance |
|----------|---------------|-------------|
| ptrace | Works on most systems | Moderate |
| kvm | Requires KVM support | Better |

### containerd Configuration

File: `/etc/containerd/config.toml`

Available runtimes:
| Runtime | Type | Description |
|---------|------|-------------|
| runc | io.containerd.runc.v2 | Standard OCI runtime (default) |
| runsc | io.containerd.runsc.v1 | gVisor runtime |
| gvisor | io.containerd.runsc.v1 | gVisor with custom config |

To use gVisor runtime: `--runtime io.containerd.runsc.v1`

---

## � Advanced Usage

### Running Multiple Containers

```bash
# Deploy web app with gVisor
sudo nerdctl run -d \
  --name webapp \
  --runtime io.containerd.runsc.v1 \
  -p 3000:3000 \
  node:alpine

# Deploy Redis with gVisor
sudo nerdctl run -d \
  --name redis \
  --runtime io.containerd.runsc.v1 \
  -p 6379:6379 \
  redis:alpine

# List all containers
sudo nerdctl ps

# Check runtime for each container
for c in $(sudo nerdctl ps --format '{{.Names}}'); do
  echo -n "$c: "
  sudo nerdctl inspect $c --format '{{.State.Runtime}}'
done
```

### Switching Between Runtimes

```bash
# Standard runc (no gVisor)
sudo nerdctl run -d --name nginx-standard -p 8080:80 nginx:alpine

# gVisor isolation
sudo nerdctl run -d --name nginx-gvisor \
  --runtime io.containerd.runsc.v1 \
  -p 8081:80 \
  nginx:alpine

# Verify gVisor process
ps aux | grep runsc
```

### Building Custom Images

```bash
# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM alpine:latest
RUN apk add --no-cache curl
CMD ["sh", "-c", "while true; do echo 'Hello'; sleep 10; done"]
EOF

# Build
sudo nerdctl build -t myapp:latest .

# Run with gVisor
sudo nerdctl run -d --name myapp \
  --runtime io.containerd.runsc.v1 \
  myapp:latest

# View logs
sudo nerdctl logs -f myapp
```

---

## 🔍 Troubleshooting

### gVisor Not Working

```bash
# Check runsc installation
multipass exec docker-in-gvisor-vm -- /usr/local/bin/runsc --version

# Check containerd runtime config
multipass exec docker-in-gvisor-vm -- grep -A 10 "runsc" /etc/containerd/config.toml

# Restart containerd
multipass exec docker-in-gvisor-vm -- sudo systemctl restart containerd

# Check containerd logs
multipass exec docker-in-gvisor-vm -- sudo journalctl -u containerd -n 50
```

### Container Not Starting

```bash
# Check container logs
multipass exec docker-in-gvisor-vm -- sudo nerdctl logs caddy

# Check all containers
multipass exec docker-in-gvisor-vm -- sudo nerdctl ps -a

# Manually redeploy Caddy
multipass exec docker-in-gvisor-vm -- sudo /home/ubuntu/deploy-caddy.sh

# Check systemd service
multipass exec docker-in-gvisor-vm -- sudo systemctl status caddy-gvisor.service
```

### Webserver Not Accessible

```bash
# Check if port is listening
multipass exec docker-in-gvisor-vm -- sudo ss -tuln | grep :8080

# Test from inside VM
multipass exec docker-in-gvisor-vm -- curl -v http://localhost:8080

# View container logs
multipass exec docker-in-gvisor-vm -- sudo nerdctl logs caddy
```

### gVisor Cgroup Issues (Ubuntu 24.04)

Ubuntu 24.04 uses cgroup v2 which may have compatibility issues with gVisor:

```bash
# Check current cgroup configuration
multipass exec docker-in-gvisor-vm -- cat /etc/containerd/runsc.toml

# Ensure ignore-cgroups is set
# Should contain: ignore-cgroups = true
```

### Clean Up Resources

```bash
# Stop all containers
multipass exec docker-in-gvisor-vm -- sudo nerdctl stop $(sudo nerdctl ps -q)

# Remove all containers
multipass exec docker-in-gvisor-vm -- sudo nerdctl rm $(sudo nerdctl ps -aq)

# Remove unused images
multipass exec docker-in-gvisor-vm -- sudo nerdctl image prune -a -f

# Remove unused volumes
multipass exec docker-in-gvisor-vm -- sudo nerdctl volume prune -f
```

---

## 📊 VM Specifications

| Resource | Default | Recommended |
|----------|---------|-------------|
| CPUs | 2 | 2-4 |
| Memory | 4GB | 4-8GB |
| Disk | 20GB | 20-50GB |

**Custom resources:**
```bash
multipass launch --name docker-in-gvisor-vm \
  --cloud-init docker-in-gvisor.yaml \
  --cpus 4 --memory 8G --disk 50G
```

> **Note:** gVisor adds ~50-100MB memory overhead per container compared to standard containers.

---

## 🆚 gVisor vs Standard Containers

| Aspect | Standard (runc) | gVisor (runsc) |
|--------|-----------------|----------------|
| Security | Kernel namespaces | User-space kernel + namespaces |
| Performance | Native | ~10-30% overhead |
| Compatibility | 100% | ~95% (some syscalls unsupported) |
| Memory | Lower | Higher (+50-100MB/container) |
| Use Case | General purpose | Security-sensitive workloads |
| Attack Surface | Full Linux kernel | gVisor user-space kernel |

### When to Use gVisor

**✅ Recommended for:**
- Running untrusted code
- Multi-tenant environments
- Security-critical workloads
- Handling sensitive data
- Defense in depth

**❌ Not recommended for:**
- Maximum performance requirements
- Specific kernel feature dependencies
- High I/O database workloads
- Kernel version dependencies

---

## 🔒 Security Benefits

### Defense in Depth

| Layer | Isolation |
|-------|-----------|
| 1. Hypervisor | Multipass VM isolation |
| 2. gVisor | User-space kernel sandbox |
| 3. Container | Namespace isolation |
| 4. Read-only mounts | Immutable configuration |

### Attack Surface Reduction

```
Standard Container:
  Container → Host Kernel (200+ syscalls)

With gVisor:
  Container → gVisor Kernel (70 syscalls) → Host Kernel
```

### Security Best Practices

```bash
# Run as non-root
sudo nerdctl run -d --user 1000:1000 \
  --runtime io.containerd.runsc.v1 myapp

# Read-only filesystem
sudo nerdctl run -d --read-only \
  --runtime io.containerd.runsc.v1 myapp

# Drop capabilities
sudo nerdctl run -d --cap-drop=ALL \
  --runtime io.containerd.runsc.v1 myapp

# Limit resources
sudo nerdctl run -d --memory=512m --cpus=1 \
  --runtime io.containerd.runsc.v1 myapp
```

---

## 🔄 Auto-Start Service

Caddy is configured to start automatically via systemd:

```bash
# Check service status
multipass exec docker-in-gvisor-vm -- sudo systemctl status caddy-gvisor.service

# Enable auto-start
multipass exec docker-in-gvisor-vm -- sudo systemctl enable caddy-gvisor.service

# Disable auto-start
multipass exec docker-in-gvisor-vm -- sudo systemctl disable caddy-gvisor.service

# Restart service
multipass exec docker-in-gvisor-vm -- sudo systemctl restart caddy-gvisor.service
```

---

## 🧹 Cleanup

### Stop and Remove Container

```bash
multipass exec docker-in-gvisor-vm -- sudo nerdctl stop caddy
multipass exec docker-in-gvisor-vm -- sudo nerdctl rm caddy
```

### Delete VM

```bash
multipass stop docker-in-gvisor-vm
multipass delete docker-in-gvisor-vm
multipass purge
```

---

## 📚 Resources

- [gVisor Documentation](https://gvisor.dev/)
- [gVisor GitHub](https://github.com/google/gvisor)
- [containerd Documentation](https://containerd.io/)
- [nerdctl GitHub](https://github.com/containerd/nerdctl)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Multipass Documentation](https://multipass.run/docs)

---

## 📝 License

MIT License
