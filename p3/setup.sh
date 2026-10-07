#!/bin/bash
set -e

CLUSTER_NAME="iot-cluster"
ARGOCD_NS="argocd"
DEV_NS="dev"
ARGOCD_PORT="443"
ARGOCD_PORT_LOCAL="8080"
DOCKER_PORT="8888"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_docker() {
    if command_exists docker; then
        log_info "Docker is already installed: $(docker --version)"
        return 0
    fi

    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh

    log_info "Adding user to docker group..."
    sudo usermod -aG docker "$USER"
    newgrp docker <<< exit

    log_info "Docker installed successfully: $(docker --version)"
}

install_k3d() {
    if command_exists k3d; then
        log_info "K3d is already installed: $(k3d version)"
        return 0
    fi

    log_info "Installing K3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

    log_info "K3d installed successfully"
}

install_kubectl() {
    if command_exists kubectl; then
        log_info "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || echo 'installed')"
        return 0
    fi

    log_info "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    log_info "kubectl installed successfully"
}

create_k3d_cluster() {
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_info "Cluster '$CLUSTER_NAME' already exists"
        return 0
    fi

    log_info "Creating K3d cluster: $CLUSTER_NAME"
    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --servers 1 \
        --wait \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer"

    log_info "K3d cluster created successfully"
}

setup_kubeconfig() {
    log_info "Setting up kubeconfig..."

    CLUSTER_CONTEXT="k3d-$CLUSTER_NAME"

    if ! kubectl config get-contexts | grep -q "$CLUSTER_CONTEXT"; then
        log_warn "Context not found, switching to cluster context..."
    fi

    kubectl config use-context "$CLUSTER_CONTEXT" || true

    log_info "Using context: $CLUSTER_CONTEXT"
}

create_namespaces() {
    log_info "Creating namespaces..."

    for NS in "$ARGOCD_NS" "$DEV_NS"; do
        if kubectl get namespace "$NS" >/dev/null 2>&1; then
            log_info "Namespace '$NS' already exists"
        else
            log_info "Creating namespace '$NS'"
            kubectl create namespace "$NS"
        fi
    done
}

install_argocd() {
    if kubectl get namespace "$ARGOCD_NS" >/dev/null 2>&1 && \
       kubectl get deployment -n "$ARGOCD_NS" argocd-server >/dev/null 2>&1; then
        log_info "Argo CD is already installed"
        return 0
    fi

    log_info "Installing Argo CD..."

    kubectl apply --server-side -n "$ARGOCD_NS" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log_info "Argo CD manifests applied"
}

wait_for_argocd() {
    log_info "Waiting for Argo CD pods to be ready..."

	sleep 5  # Initial wait before checking pod status

    kubectl wait --for=condition=available deployment \
        -l app.kubernetes.io/part-of=argocd \
        -n "$ARGOCD_NS" \
        --timeout=300s || log_warn "Some pods may not be ready yet"

    log_info "Argo CD pods are ready (or timed out)"
}

apply_argocd_app() {
    log_info "Applying Argo CD Application..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    APP_MANIFEST="$SCRIPT_DIR/p3/confs/application.yaml"

    if [ ! -f "$APP_MANIFEST" ]; then
        log_error "Application manifest not found at $APP_MANIFEST"
        log_warn "Skipping application deployment"
        return 1
    fi

    kubectl apply -f "$APP_MANIFEST"

    log_info "Argo CD Application applied"
}

setup_port_forwarding() {
    log_info "Setting up port-forwarding for Argo CD UI..."

    pkill -f "kubectl port-forward.*argocd-server" || true
    sleep 1

    kubectl port-forward \
        -n "$ARGOCD_NS" \
        svc/argocd-server "$ARGOCD_PORT_LOCAL:$ARGOCD_PORT" &

    PF_PID=$!

	kubectl port-forward \
		-n "$DEV_NS" \
		svc/playground "$DOCKER_PORT:8888" &

    log_info "Port-forwarding started (PID: $PF_PID)"
    log_info "Argo CD UI will be available at: https://localhost:$ARGOCD_PORT_LOCAL"
    log_info "Docker Registry will be available at: https://localhost:$DOCKER_PORT"

    sleep 3
}

get_argocd_password() {
    log_info "Retrieving Argo CD admin password..."

    ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_FOUND")

    if [ "$ARGOCD_PASSWORD" != "NOT_FOUND" ]; then
        log_info "Argo CD admin username: admin"
        log_info "Argo CD admin password: $ARGOCD_PASSWORD"
    else
        log_warn "Could not retrieve Argo CD admin password (may not be ready yet)"
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."

    log_info "Cluster nodes:"
    kubectl get nodes

    log_info "Namespaces:"
    kubectl get ns | grep -E "($ARGOCD_NS|$DEV_NS)"

    log_info "Argo CD pods:"
    kubectl get pods -n "$ARGOCD_NS" || log_warn "No pods found in $ARGOCD_NS"
}

main() {
    log_info "Starting IoT Part 3 setup..."

    install_docker
    install_k3d
    install_kubectl

    create_k3d_cluster
    setup_kubeconfig

    create_namespaces
    install_argocd
    wait_for_argocd

    verify_deployment

    setup_port_forwarding
    get_argocd_password

    apply_argocd_app

    log_info "Setup completed successfully!"
    log_info "Access Argo CD UI at: https://localhost:$ARGOCD_PORT_LOCAL"
    log_info "Username: admin"
    log_info "Run 'kubectl logs -f -n $ARGOCD_NS -l app.kubernetes.io/part-of=argocd' to see logs"
}

main "$@"
