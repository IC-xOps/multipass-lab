# 🦭 Podman VMs for Multipass

Two different approaches to running containers on macOS using Multipass VMs:

1. **[Podman VM](#-podman-vm)** - Rootless Podman for secure, daemonless containers
2. **[Docker-in-Podman VM](#-docker-in-podman-vm)** - Docker Engine running inside a Podman container

---

## 📋 Prerequisites

- [Multipass](https://multipass.run/) installed on macOS
- [Podman Desktop](https://podman-desktop.io/) (optional, for GUI management)

```bash
brew install --cask multipass
brew install --cask podman-desktop  # Optional
```

---
---

# 🦭 Podman VM

A fully configured rootless Podman environment running in a Multipass Ubuntu VM with Docker compatibility and socket support for Podman Desktop integration.

## Features

- **Rootless Podman 4.9.3** - Secure containerization without root privileges
- **Docker compatibility** - `podman-docker` alias support
- **Socket support** - User and system sockets for remote management
- **Podman Desktop ready** - Connect from macOS via SSH tunnel
- **Optimized settings** - Proper subuid/subgid, cgroup systemd, overlay storage
- **41 comprehensive tests** - Full validation suite

---

## Quick Start

### 1. Create the VM

```bash
cd Podman
multipass launch --name podman-vm --cloud-init podman.yaml --cpus 2 --memory 4G --disk 20G
```

### 2. Run Tests

```bash
./test-podman-vm.sh
```

### 3. Access the VM

```bash
multipass shell podman-vm
```

---

## Test Suite - 41 Tests

```bash
./test-podman-vm.sh
```

**Test Categories:**

| Category | Tests |
|----------|-------|
| **Prerequisites** | Multipass installation |
| **VM Status** | Exists, Running |
| **Cloud-Init** | Completion status |
| **Podman Installation** | Version, podman-docker, slirp4netns, fuse-overlayfs, uidmap |
| **Post-Installation** | Subuid/subgid, linger, registries, containers.conf, cgroup manager |
| **Permissions** | Home directory, .config, .local, XDG_RUNTIME_DIR, rootless mode |
| **Sockets** | User socket (enabled/active/exists), System socket |
| **Functionality** | Pull images, Run containers, Volumes, Bind mounts, Port mapping |
| **Docker Compatibility** | Docker CLI, Podman redirect, docker run |
| **Network** | Internet, DNS, Registry connectivity |
| **Resources** | Disk space, Memory, Podman storage |
| **Common Issues** | Zombie containers, Dangling images, Storage driver, OCI runtime |

---

## What's Included

**Configuration Files:**
- `podman.yaml` - Cloud-init configuration
- `test-podman-vm.sh` - Test suite (41 tests)

**Inside the VM:**
- `~/test-podman.sh` - Quick Podman test script
- `~/.config/containers/containers.conf` - User container configuration
- `/etc/containers/registries.conf` - Container registry configuration

---

## Socket Paths

| Type | Path | Description |
|------|------|-------------|
| **User (rootless)** | `/run/user/1000/podman/podman.sock` | Recommended for security |
| **System (root)** | `/run/podman/podman.sock` | For privileged operations |
| **macOS forwarded** | `/tmp/podman.sock` | Via SSH tunnel |

---

## Connect Podman Desktop from macOS

### Method 1: SSH Socket Forwarding (Recommended)

#### Step 1: Copy SSH Key to VM

```bash
multipass exec podman-vm -- bash -c "echo '$(cat ~/.ssh/id_rsa.pub)' >> ~/.ssh/authorized_keys"
```

#### Step 2: Get VM IP

```bash
multipass info podman-vm | grep IPv4
```

#### Step 3: Forward the Socket

```bash
# For rootless Podman (recommended)
ssh -nNT -L /tmp/podman.sock:/run/user/1000/podman/podman.sock ubuntu@<VM-IP>

# For root Podman
ssh -nNT -L /tmp/podman.sock:/run/podman/podman.sock ubuntu@<VM-IP>
```

> 💡 Keep this terminal open or add `&` to background it.

#### Step 4: Configure Podman Desktop

1. Open **Podman Desktop**
2. Go to **Settings** → **Resources**
3. Click **Create new** under Podman connections
4. Configure:
   - **Name:** `Multipass VM`
   - **Socket Path:** `/tmp/podman.sock`
5. Click **Connect**

---

### Method 2: Persistent Tunnel with autossh

```bash
# Install autossh
brew install autossh

# Create tunnel script
cat > ~/podman-tunnel.sh << 'EOF'
#!/bin/bash
VM_IP=$(multipass info podman-vm | grep IPv4 | awk '{print $2}')
autossh -M 0 -nNT -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" \
  -L /tmp/podman.sock:/run/user/1000/podman/podman.sock ubuntu@$VM_IP
EOF
chmod +x ~/podman-tunnel.sh

# Run it
~/podman-tunnel.sh &
```

---

### Method 3: Direct CLI Connection

```bash
# Get VM IP
VM_IP=$(multipass info podman-vm | grep IPv4 | awk '{print $2}')

# Set environment variable
export PODMAN_HOST="ssh://ubuntu@$VM_IP/run/user/1000/podman/podman.sock"

# Now podman commands use the VM
podman ps
podman images
```

---

## Configuration Details

### Rootless Setup

The VM is configured for secure rootless container operation:

- **Subuid/Subgid:** `100000-165535` mapped to ubuntu user
- **User linger:** Enabled for persistent user services
- **Cgroup manager:** systemd
- **Storage driver:** overlay (optimal)
- **OCI runtime:** crun

### Container Registries

Pre-configured in `/etc/containers/registries.conf`:

```toml
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "docker.io"

[[registry]]
location = "quay.io"

[[registry]]
location = "gcr.io"
```

### User Configuration

Located at `~/.config/containers/containers.conf`:

```toml
[containers]
log_driver = "k8s-file"

[engine]
cgroup_manager = "systemd"
events_logger = "journald"
```

---

## Useful Commands

### Multipass

| Command | Description |
|---------|-------------|
| `multipass list` | List all VMs |
| `multipass shell podman-vm` | SSH into VM |
| `multipass info podman-vm` | VM details and IP |
| `multipass stop podman-vm` | Stop VM |
| `multipass start podman-vm` | Start VM |
| `multipass delete podman-vm && multipass purge` | Delete VM |

### Podman

| Command | Description |
|---------|-------------|
| `podman ps` | List running containers |
| `podman ps -a` | List all containers |
| `podman images` | List images |
| `podman run --rm hello-world` | Test container |
| `podman run -d -p 8080:80 nginx` | Run Nginx |
| `podman logs <container>` | View logs |
| `podman exec -it <container> bash` | Shell into container |
| `podman system prune -a` | Clean up |

### Systemd Socket Management

| Command | Description |
|---------|-------------|
| `systemctl --user status podman.socket` | Check user socket |
| `systemctl --user restart podman.socket` | Restart user socket |
| `sudo systemctl status podman.socket` | Check system socket |

---

## Docker Compatibility

The VM includes `podman-docker` for Docker CLI compatibility:

```bash
# These work the same
docker run --rm hello-world
podman run --rm hello-world

# Docker Compose alternative
podman-compose up -d
# Or use podman directly
podman compose up -d  # (if podman-compose plugin installed)
```

---

## VM Specifications

| Resource | Default | Recommended |
|----------|---------|-------------|
| CPUs | 2 | 2-4 |
| Memory | 4GB | 4-8GB |
| Disk | 20GB | 20-50GB |

Adjust resources when creating the VM:

```bash
multipass launch --name podman-vm --cloud-init podman.yaml \
  --cpus 4 --memory 8G --disk 50G
```

---

## Troubleshooting

### Socket Not Available

```bash
# Restart the socket
multipass exec podman-vm -- systemctl --user restart podman.socket
multipass exec podman-vm -- systemctl --user status podman.socket
```

### Permission Denied

```bash
# Check linger status
multipass exec podman-vm -- loginctl show-user ubuntu | grep Linger

# Enable linger if needed
multipass exec podman-vm -- sudo loginctl enable-linger ubuntu
```

### Connection Refused from macOS

1. Verify VM is running:
   ```bash
   multipass list
   ```

2. Check socket exists:
   ```bash
   multipass exec podman-vm -- ls -la /run/user/1000/podman/podman.sock
   ```

3. Verify SSH tunnel:
   ```bash
   ls -la /tmp/podman.sock
   ```

4. Clean up stale socket:
   ```bash
   rm -f /tmp/podman.sock
   ```

### Subuid/Subgid Issues

```bash
# Verify configuration
multipass exec podman-vm -- cat /etc/subuid
multipass exec podman-vm -- cat /etc/subgid

# Reset if needed
multipass exec podman-vm -- sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 ubuntu
```

### Clean Up Resources

```bash
# Remove stopped containers
podman container prune -f

# Remove unused images
podman image prune -a -f

# Remove unused volumes
podman volume prune -f

# Remove everything
podman system prune -a --volumes -f
```

---
---

# 🐳 Docker-in-Podman VM

Docker Engine (27.3.1) running inside a privileged Podman container for full Docker compatibility while leveraging Podman as the host runtime.

## Features

- **Docker 27.3.1** - Pinned version for stability
- **Complete isolation** - Docker containers isolated from Podman host
- **CLI wrappers** - Seamless `docker` and `docker-compose` commands
- **Auto-start** - Systemd service for automatic container startup on boot
- **Workspace sharing** - `/home/ubuntu/workspace` mounted in Docker
- **Data persistence** - Docker data stored in Podman volume
- **48 comprehensive tests** - Full validation suite

---

## Quick Start

### 1. Create the VM

```bash
cd Podman
multipass launch --name docker-in-podman-vm --cloud-init docker-in-podman.yaml --cpus 2 --memory 4G --disk 20G
```

### 2. Run Tests

```bash
./test-docker-in-podman-vm.sh
```

### 3. Use Docker

```bash
multipass shell docker-in-podman-vm
docker --version  # Docker 27.3.1
docker run hello-world
docker-compose --version  # v2.31.0
```

---

## Test Suite - 48 Tests

```bash
./test-docker-in-podman-vm.sh
```

**Test Categories:**

| Category | Tests |
|----------|-------|
| **Prerequisites** | Multipass installation |
| **VM Status** | Exists, Running, Cloud-init completion |
| **Podman Installation** | Version (4.9.3), root mode, dependencies |
| **Podman Configuration** | Subuid/subgid, linger, registries |
| **Docker Container** | Exists, Running, Privileged mode, Volumes |
| **Docker Daemon** | Responding, Version (27.3.1), Storage driver, Root directory |
| **Wrapper Scripts** | docker, docker-compose, start script, PATH |
| **Docker Functionality** | ps, pull, run, hello-world, volumes, networks, build |
| **Container Isolation** | Host visibility, Docker isolation, nested containers |
| **Data Persistence** | Docker data volume, Workspace sharing |
| **Auto-Start** | Systemd service, Service enabled, Restart policy |
| **Network** | Internet access, DNS resolution, Docker Hub |
| **Resources** | Disk space, Memory usage |

---

## What's Included

**Configuration Files:**
- `docker-in-podman.yaml` - Cloud-init configuration
- `test-docker-in-podman-vm.sh` - Test suite (48 tests)

**Inside the VM:**
- `~/docker` - Docker CLI wrapper (executes in Podman container)
- `~/docker-compose` - Docker Compose wrapper
- `~/start-docker-container.sh` - Script to start Docker container
- `~/workspace/` - Shared workspace folder
- `/etc/systemd/system/docker-in-podman.service` - Auto-start service

---

## How It Works

### Architecture

```
macOS Host
  └─ Multipass VM (Ubuntu 24.04)
      └─ Podman 4.9.3 (root mode)
          └─ Docker Container (docker:27.3-dind)
              └─ Docker Engine 27.3.1
                  └─ Your Docker containers
```

**Components:**
- **Podman Host**: Runs at system level for privileged container support
- **Docker Container**: Privileged container with `cgroupns=host`
- **Docker Daemon**: Listens on `/var/run/docker.sock` (inside container)
- **Wrappers**: `~/docker` and `~/docker-compose` execute via `podman exec`
- **Data Persistence**: `docker-data` Podman volume mounted to `/var/lib/docker`
- **Workspace**: `/home/ubuntu/workspace` shared with `/workspace` in Docker

---

## Version Pinning

For stability, versions are pinned:
- **Podman**: 4.9.3 (Ubuntu 24.04 repos)
- **Docker Image**: `docker.io/library/docker:27.3-dind`
- **Docker Version**: 27.3.1
- **Docker Compose**: v2.31.0 (included in dind image)

---

## CLI Wrappers

### Docker Wrapper

The `~/docker` wrapper executes Docker commands inside the Podman container:

```bash
#!/bin/bash
CONTAINER_NAME="docker-engine"

if ! sudo podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Docker container '$CONTAINER_NAME' is not running"
    echo "Start it with: ~/start-docker-container.sh"
    exit 1
fi

sudo podman exec -i $CONTAINER_NAME docker "$@"
```

### Docker Compose Wrapper

Similar wrapper for `docker-compose`:

```bash
#!/bin/bash
CONTAINER_NAME="docker-engine"

if ! sudo podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Docker container '$CONTAINER_NAME' is not running"
    echo "Start it with: ~/start-docker-container.sh"
    exit 1
fi

sudo podman exec -i $CONTAINER_NAME docker compose "$@"
```

---

## Auto-Start Configuration

Docker container automatically starts on boot via systemd service at `/etc/systemd/system/docker-in-podman.service`:

```ini
[Unit]
Description=Docker-in-Podman Container
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=-/usr/bin/podman stop docker-engine
ExecStartPre=-/usr/bin/podman rm docker-engine
ExecStart=/usr/bin/podman run --name docker-engine --privileged --cgroupns=host -v docker-data:/var/lib/docker -v /home/ubuntu/workspace:/workspace docker.io/library/docker:27.3-dind dockerd --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2375 --tls=false
ExecStop=/usr/bin/podman stop docker-engine
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Manage the service:**

```bash
# Check status
systemctl status docker-in-podman.service

# Restart
sudo systemctl restart docker-in-podman.service

# Stop
sudo systemctl stop docker-in-podman.service

# Disable auto-start
sudo systemctl disable docker-in-podman.service
```

---

## Usage Examples

### Basic Docker Commands

```bash
# Container management
docker ps
docker ps -a
docker images
docker run -d nginx
docker logs <container-id>
docker stop <container-id>
docker rm <container-id>

# Image management
docker pull alpine
docker rmi alpine
docker image prune -a
```

### Docker Compose

```bash
# In your project directory (inside ~/workspace)
cd ~/workspace/myapp

# Start services
docker-compose up -d

# View status
docker-compose ps

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Remove volumes
docker-compose down -v
```

### Building Images

```bash
# Create Dockerfile in workspace
cd ~/workspace/myapp
cat > Dockerfile << 'EOF'
FROM alpine
RUN apk add --no-cache nginx
CMD ["nginx", "-g", "daemon off;"]
EOF

# Build image
docker build -t myapp:latest .

# Run container
docker run -d -p 8080:80 myapp:latest
```

### Volumes and Data Persistence

```bash
# Create volume (stored in Podman volume docker-data)
docker volume create mydata

# Use volume in container
docker run -d -v mydata:/data alpine sleep 3600

# List volumes
docker volume ls

# Inspect volume
docker volume inspect mydata

# Remove volume
docker volume rm mydata
```

### Workspace Sharing

```bash
# Files in ~/workspace are accessible in Docker
echo "Hello from host" > ~/workspace/test.txt

# Run container with workspace mounted
docker run --rm -v /workspace:/data alpine cat /data/test.txt
```

---

## VM Specifications

| Resource | Default | Recommended |
|----------|---------|-------------|
| CPUs | 2 | 2-4 |
| Memory | 4GB | 4-8GB |
| Disk | 20GB | 20-50GB |

Adjust resources when creating the VM:

```bash
multipass launch --name docker-in-podman-vm --cloud-init docker-in-podman.yaml \
  --cpus 4 --memory 8G --disk 50G
```

---

## Troubleshooting

### Docker Container Not Running

```bash
# Check container status
multipass exec docker-in-podman-vm -- sudo podman ps -a

# Start manually
multipass exec docker-in-podman-vm -- ~/start-docker-container.sh

# Check logs
multipass exec docker-in-podman-vm -- sudo podman logs docker-engine
```

### Docker Daemon Not Responding

```bash
# Restart the container
multipass exec docker-in-podman-vm -- sudo systemctl restart docker-in-podman.service

# Check daemon status inside container
multipass exec docker-in-podman-vm -- /home/ubuntu/docker info
```

### Systemd Service Issues

```bash
# Check service status
multipass exec docker-in-podman-vm -- sudo systemctl status docker-in-podman.service

# View service logs
multipass exec docker-in-podman-vm -- sudo journalctl -u docker-in-podman.service -n 50

# Restart service
multipass exec docker-in-podman-vm -- sudo systemctl restart docker-in-podman.service

# Reload systemd daemon
multipass exec docker-in-podman-vm -- sudo systemctl daemon-reload
```

### Workspace Not Accessible

```bash
# Verify mount inside container
multipass exec docker-in-podman-vm -- sudo podman exec docker-engine ls -la /workspace

# Test file creation
multipass exec docker-in-podman-vm -- bash -c 'echo "test" > ~/workspace/test.txt'
multipass exec docker-in-podman-vm -- /home/ubuntu/docker run --rm -v /workspace:/test alpine cat /test/test.txt
```

### Clean Up Docker Resources

```bash
# From macOS
multipass exec docker-in-podman-vm -- /home/ubuntu/docker system prune -a --volumes -f

# Or inside VM
multipass shell docker-in-podman-vm
docker system prune -a --volumes -f
docker volume prune -f
docker network prune -f
```

### Container Won't Start After Reboot

```bash
# Check if service is enabled
multipass exec docker-in-podman-vm -- sudo systemctl is-enabled docker-in-podman.service

# Enable if needed
multipass exec docker-in-podman-vm -- sudo systemctl enable docker-in-podman.service

# Start immediately
multipass exec docker-in-podman-vm -- sudo systemctl start docker-in-podman.service
```

---
---

# 🆚 Comparison & Choosing

## Test Results Summary

| VM Configuration | Tests | Status |
|-----------------|-------|---------|
| **Podman VM** | 41/41 passed | ✅ All tests passed |
| **Docker-in-Podman VM** | 48/48 passed | ✅ All tests passed |

**Total:** 89 tests across both VMs

---

## When to Use Each VM

### Use **Podman VM** when:

✅ You want rootless, secure container runtime  
✅ You need Podman Desktop integration  
✅ You prefer Podman's daemonless architecture  
✅ You need OCI container compatibility  
✅ Security is a top priority  
✅ You're learning Podman or migrating to it  

### Use **Docker-in-Podman VM** when:

✅ You need actual Docker Engine compatibility  
✅ You have projects requiring Docker-specific features  
✅ You want to test Docker in an isolated environment  
✅ You need Docker Compose with full compatibility  
✅ You're migrating from Docker to Podman gradually  
✅ You need both Docker and Podman on the same system  

---

## Feature Comparison

| Feature | Podman VM | Docker-in-Podman VM |
|---------|-----------|---------------------|
| **Container Runtime** | Podman (native) | Docker (in container) |
| **Rootless** | ✅ Yes | ❌ No (root Podman) |
| **Daemon** | ❌ Daemonless | ✅ Docker daemon |
| **Desktop Integration** | ✅ Podman Desktop | ❌ No |
| **Docker Compatibility** | ⚠️ Via podman-docker | ✅ Full |
| **Docker Compose** | ⚠️ podman-compose | ✅ Native |
| **Auto-start** | ⚠️ Socket only | ✅ Full service |
| **Isolation** | N/A | ✅ Complete |
| **Workspace Sharing** | N/A | ✅ Yes |
| **Resource Usage** | Lower | Higher |
| **Security** | Higher (rootless) | Lower (privileged) |

---

## 📝 License

MIT License - Feel free to use and modify as needed.
