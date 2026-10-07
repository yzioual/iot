# Inception-of-Things (IoT)

## Project Overview

Inception-of-Things (IoT) is a System Administration and DevOps project aimed at introducing lightweight Kubernetes environments, container orchestration, and Continuous Delivery (GitOps).

The project is structured into four distinct parts, progressing from virtualized multi-node K3s clusters using Vagrant to containerized K3d clusters with Argo CD and self-hosted GitLab integration.

---

## Directory Structure

```text
.
├── iot.pdf              # Official subject specification document
├── p1/                  # Part 1: K3s and Vagrant (Multi-node setup)
│   └── Vagrantfile      # Automated provisioning for Server and Worker nodes
├── p2/                  # Part 2: K3s and Host-Based Ingress Routing
│   ├── Vagrantfile      # Single-node K3s Vagrant configuration
│   └── confs/           # Kubernetes manifests
│       ├── app.yml      # Deployments and Services for App1, App2, App3
│       └── ingress.yml  # Traefik Ingress routing configuration
├── p3/                  # Part 3: K3d and GitOps with Argo CD
│   ├── setup.sh         # Installation and environment setup script
│   ├── confs/
│   │   └── application.yaml  # Argo CD Application manifest
│   └── app/             # Application Kubernetes resources
│       ├── deployment.yaml   # Deployment manifest for wil42/playground app
│       └── service.yaml      # Service manifest for app access
└── bonus/               # Bonus: Self-Hosted GitLab with Argo CD
    ├── confs/           # GitLab values, Argo CD app, and version manifests
    ├── app/             # Target application manifests
    └── scripts/
        ├── setup.sh     # Comprehensive cluster, Helm, GitLab, and Argo CD installer
        └── switch.sh    # Script to switch application versions (v1/v2) in GitLab
```

---

## Part 1: K3s and Vagrant

### Description
Part 1 sets up a multi-node Kubernetes cluster using K3s inside VirtualBox virtual machines managed by Vagrant.

### Specifications
* **Operating System**: Debian Bookworm (64-bit).
* **Hardware Allocation**: 1 CPU, 1024 MB RAM per node.
* **Network Interface**: Dedicated private network on `eth1`.
* **Node 1 (`yzioualS`)**: Server / Controller node with fixed IP `192.168.56.110`.
* **Node 2 (`yzioualSW`)**: Worker / Agent node with fixed IP `192.168.56.111`.

### Implementation Details
* **Server Provisioning**: Installs K3s in controller mode bound to `192.168.56.110` over `eth1`. Copies the cluster join token (`/var/lib/rancher/k3s/server/node-token`) to the shared `/vagrant` folder.
* **Worker Provisioning**: Waits for `/vagrant/node-token` and installs K3s in agent mode, connecting to `https://192.168.56.110:6443`.
* **Authentication**: Passwordless SSH configured across machines.

### Commands to Run
```bash
cd p1
vagrant up
```

### Verification
Connect to the server node via SSH and verify cluster status:
```bash
vagrant ssh yzioualS
sudo kubectl get nodes -o wide
```
Expected output shows both `yzioualS` and `yzioualSW` in `Ready` state.

---

## Part 2: K3s and Three Simple Applications

### Description
Part 2 expands K3s usage to deploy three distinct web application deployments behind a single Traefik Ingress controller on a single virtual machine (`waiziS` at `192.168.56.110`).

### Infrastructure & Application Architecture
1. **App 1 (`app1`)**:
   * Replica count: 1
   * Image: `paulbouwer/hello-kubernetes:1.10`
   * Routing Host: `app1.com`
2. **App 2 (`app2`)**:
   * Replica count: 3 (demonstrating pod scaling)
   * Image: `paulbouwer/hello-kubernetes:1.10`
   * Routing Host: `app2.com`
3. **App 3 (`app3`)**:
   * Replica count: 1
   * Image: `paulbouwer/hello-kubernetes:1.10`
   * Purpose: Serves as the default fallback backend for unmatched host headers.

### Ingress Configuration
The `p2/confs/ingress.yml` file configures Traefik annotations and rules:
* Requests with `Host: app1.com` map to `app1-service:80`.
* Requests with `Host: app2.com` map to `app2-service:80`.
* All unmapped requests route to `defaultBackend: app3-service:80`.

### Commands to Run
```bash
cd p2
vagrant up
```
Vagrant automatically applies all manifests in `/vagrant/confs` upon initial boot.

### Verification
Inside the virtual machine or on the host (with `/etc/hosts` mapped):
```bash
# Host routing test for App 1
curl -H "Host: app1.com" http://192.168.56.110

# Host routing test for App 2
curl -H "Host: app2.com" http://192.168.56.110

# Default backend test (unmatched host)
curl http://192.168.56.110
```

---

## Part 3: K3d and Argo CD

### Description
Part 3 transitions from heavy Virtual Machines to lightweight containerized Kubernetes clusters using K3d (K3s in Docker). It introduces GitOps Continuous Delivery using Argo CD.

### Cluster & Namespace Structure
* **Cluster Name**: `iot-cluster` (1 server node, 2 agent nodes).
* **Namespaces**:
  * `argocd`: Dedicated namespace for Argo CD controllers and UI.
  * `dev`: Namespace where the application is automatically deployed.

### Setup Script Flow (`p3/setup.sh`)
1. Installs system dependencies: Docker, K3d, and `kubectl`.
2. Creates K3d cluster with load balancer port mappings (`80:80`, `443:443`).
3. Creates required namespaces (`argocd` and `dev`).
4. Installs Argo CD server via official manifests.
5. Applies Argo CD Application manifest (`p3/confs/application.yaml`).
6. Configures port forwarding for Argo CD web UI (`localhost:8080`) and application endpoint (`localhost:8888`).
7. Retrieves and displays the initial admin password for Argo CD.

### Application Deployment & GitOps Synchronization
* **App Repository**: Argo CD monitors a public GitHub repository.
* **Manifests**: `p3/app/deployment.yaml` and `p3/app/service.yaml`.
* **Docker Image**: `wil42/playground:v1` or `wil42/playground:v2`.
* **Automated Sync Policy**:
  * `prune: true`: Automatically deletes resources removed from Git.
  * `selfHeal: true`: Reverts manual cluster changes to match Git state.

### Commands to Run
```bash
cd p3
bash setup.sh
```

### Testing Version Updates
1. Access application endpoint:
   ```bash
   curl http://localhost:8888/
   ```
2. Update application image tag in your remote GitHub repository (`v1` -> `v2`).
3. Argo CD automatically detects the change, synchronizes the cluster, and updates the running pods.
4. Verify updated version:
   ```bash
   curl http://localhost:8888/
   ```

---

## Bonus Part: Self-Hosted GitLab Integration

### Description
The bonus section replaces external GitHub dependency with a fully self-hosted GitLab instance running inside the K3d Kubernetes cluster. Argo CD synchronizes application deployments directly from the local GitLab repository.

### Cluster Architecture
* **Cluster Name**: `iot-bonus` (1 server node, 2 agent nodes).
* **Namespaces**:
  * `argocd`: Argo CD deployment.
  * `dev`: Target application environment.
  * `gitlab`: Local GitLab deployment.

### Setup Script Flow (`bonus/scripts/setup.sh`)
1. Installs Docker, K3d, `kubectl`, and Helm.
2. Spins up the `iot-bonus` K3d cluster with port forwarding.
3. Installs GitLab using Helm / Kubernetes resources in the `gitlab` namespace.
4. Deploys Argo CD in the `argocd` namespace and links it to the local GitLab repo.
5. Provisions application resources in `dev`.

### Version Switch Helper (`bonus/scripts/switch.sh`)
The `switch.sh` script automates local version updates:
```bash
cd bonus/scripts
bash switch.sh v1   # Deploys v1 manifest to local GitLab and triggers Argo CD sync
bash switch.sh v2   # Deploys v2 manifest to local GitLab and triggers Argo CD sync
```

---

## Requirements & Prerequisites

To execute and evaluate this project, the following software must be available on the host system:

* **Virtualization**: VirtualBox
* **VM Management**: Vagrant
* **Containers**: Docker Engine
* **Kubernetes Tools**: K3d, kubectl, Helm
* **Utilities**: curl, git, bash

---

## Author

* **Login**: `yzioual` / `waizi`
* **School**: 42 School
