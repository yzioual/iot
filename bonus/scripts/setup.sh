#!/bin/bash
set -e

CLUSTER_NAME="iot-bonus"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITLAB_NS="gitlab"

ARGOCD_PORT="443"
ARGOCD_PORT_LOCAL="8080"
DOCKER_PORT="8888"
GITLAB_HTTP_PORT="80"
GITLAB_LOCAL_PORT="8081"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -------------------------------------------------------------
# Dependency Installations
# -------------------------------------------------------------
install_docker() {
    if command_exists docker; then
        log_info "Docker is already installed: $(docker --version)"
        return 0
    fi
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker "$USER"
    log_info "Docker installed successfully."
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

install_helm() {
    if command_exists helm; then
        log_info "Helm is already installed: $(helm version --short)"
        return 0
    fi
    log_info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_info "Helm installed successfully"
}

# -------------------------------------------------------------
# Cluster Creation & Namespaces
# -------------------------------------------------------------
create_k3d_cluster() {
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_info "Cluster '$CLUSTER_NAME' already exists"
        return 0
    fi

    log_info "Creating K3d cluster: $CLUSTER_NAME..."
    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --servers 1 \
        --wait \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "8888:8888@loadbalancer" \
        --port "2222:22@loadbalancer"

    log_info "K3d cluster created successfully"
}

setup_kubeconfig() {
    log_info "Setting up kubeconfig..."
    CLUSTER_CONTEXT="k3d-$CLUSTER_NAME"
    kubectl config use-context "$CLUSTER_CONTEXT" || true
    log_info "Using context: $CLUSTER_CONTEXT"
}

create_namespaces() {
    log_info "Creating namespaces..."
    for NS in "$ARGOCD_NS" "$DEV_NS" "$GITLAB_NS"; do
        if kubectl get namespace "$NS" >/dev/null 2>&1; then
            log_info "Namespace '$NS' already exists"
        else
            log_info "Creating namespace '$NS'"
            kubectl create namespace "$NS"
        fi
    done
}

# -------------------------------------------------------------
# GitLab Setup (Helm)
# -------------------------------------------------------------
install_gitlab() {
    log_info "Deploying GitLab via Helm..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    GITLAB_VALUES="$SCRIPT_DIR/confs/gitlab-values.yaml"

    if [ ! -f "$GITLAB_VALUES" ]; then
        log_error "gitlab-values.yaml not found at $GITLAB_VALUES"
        exit 1
    fi

    helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
    helm repo update

    if helm list -n "$GITLAB_NS" | grep -q gitlab; then
        log_info "GitLab Helm release already present"
    else
        helm upgrade --install gitlab gitlab/gitlab \
            --namespace "$GITLAB_NS" \
            -f "$GITLAB_VALUES" \
            --timeout 900s
        log_info "GitLab Helm deployment command executed"
    fi
}

wait_for_gitlab() {
    log_info "Waiting for GitLab core components (this may take 3-5 minutes)..."
    kubectl rollout status deployment/gitlab-webservice-default -n "$GITLAB_NS" --timeout=600s || log_warn "GitLab webservice rollout check timed out"
}

get_gitlab_password() {
    log_info "Retrieving GitLab root password..."
    GITLAB_ROOT_PW=$(kubectl -n "$GITLAB_NS" get secret gitlab-gitlab-initial-root-password \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_FOUND")

    if [ "$GITLAB_ROOT_PW" != "NOT_FOUND" ]; then
        log_info "GitLab UI URL: http://gitlab.local (or port-forwarded)"
        log_info "GitLab Username: root"
        log_info "GitLab Root Password: $GITLAB_ROOT_PW"
    else
        log_warn "GitLab root password secret not generated yet"
    fi
}

# -------------------------------------------------------------
# Argo CD Setup
# -------------------------------------------------------------
install_argocd() {
    if kubectl get deployment -n "$ARGOCD_NS" argocd-server >/dev/null 2>&1; then
        log_info "Argo CD is already installed"
        return 0
    fi
    log_info "Installing Argo CD..."
    kubectl apply --server-side -n "$ARGOCD_NS" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    log_info "Argo CD manifests applied"
}

wait_for_argocd() {
    log_info "Waiting for Argo CD pods to be ready..."
    kubectl wait --for=condition=available deployment \
        -l app.kubernetes.io/part-of=argocd \
        -n "$ARGOCD_NS" \
        --timeout=300s || log_warn "Some Argo CD pods may not be ready yet"
    log_info "Argo CD pods are ready"
}

get_argocd_password() {
    log_info "Retrieving Argo CD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_FOUND")

    if [ "$ARGOCD_PASSWORD" != "NOT_FOUND" ]; then
        log_info "Argo CD admin username: admin"
        log_info "Argo CD admin password: $ARGOCD_PASSWORD"
    else
        log_warn "Could not retrieve Argo CD admin password"
    fi
}

apply_argocd_app() {
    log_info "Applying Argo CD Application configured for local GitLab..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    APP_MANIFEST="$SCRIPT_DIR/confs/application.yaml"

    if [ -f "$APP_MANIFEST" ]; then
        kubectl apply -f "$APP_MANIFEST"
        log_info "Argo CD Application applied"
    else
        log_warn "Application manifest not found at $APP_MANIFEST (create the repo in GitLab first!)"
    fi
}

setup_port_forwarding() {
    log_info "Setting up port-forwarding..."
    pkill -f "kubectl port-forward" || true
    sleep 1

    # Argo CD
    kubectl port-forward -n "$ARGOCD_NS" svc/argocd-server "$ARGOCD_PORT_LOCAL:$ARGOCD_PORT" &
    # Dev Playground App
    kubectl port-forward -n "$DEV_NS" svc/playground "$DOCKER_PORT:8888" &
    # GitLab UI (direct web fallback)
    kubectl port-forward -n "$GITLAB_NS" svc/gitlab-webservice-default "$GITLAB_LOCAL_PORT:8181" &

    sleep 3
}

# -------------------------------------------------------------
# Main
# -------------------------------------------------------------
main() {
    log_info "Starting IoT Bonus Setup (GitLab + Argo CD)..."

    install_docker
    install_k3d
    install_kubectl
    install_helm

    create_k3d_cluster
    setup_kubeconfig
    create_namespaces

    install_gitlab
    install_argocd

    wait_for_argocd
    wait_for_gitlab

    get_argocd_password
    get_gitlab_password

    setup_port_forwarding
    apply_argocd_app

    log_info "Bonus Setup complete!"
    log_info "Argo CD UI: https://localhost:$ARGOCD_PORT_LOCAL"
    log_info "GitLab UI: http://localhost:$GITLAB_LOCAL_PORT (or via ingress)"
    log_info "Dev Playground: http://localhost:$DOCKER_PORT"
}

main "$@"
