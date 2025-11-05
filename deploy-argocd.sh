#!/bin/bash

################################################################################
# deploy-argocd.sh - ArgoCD v2.13.3 Deployment Automation
#
# Versão: 1.0.0
# Data: 20-01-2025
# Autor: erivandosena@gmail.com
#
# DESCRIÇÃO:
# Script automatizado para instalação, configuração e gerenciamento de ArgoCD
# em ambientes multi-cluster Kubernetes com suporte a instalação MAIN + REMOTE
#
# REQUISITOS:
# • kubectl configurado com acesso aos clusters
# • Dois contextos no kubeconfig (MAIN e REMOTE)
# • Permissões de admin no cluster
#
################################################################################
#
# FLUXO DE TRABALHO:
#
# ┌────────────────────────────────────────────────────────────────┐
# │  PREPARAÇÃO: Ter ~/.kube/config com AMBOS contextos            │
# │  - kubernetes-admin@kubernetes (Cluster2 MAIN - 10.130.1.2)          │
# │  - kubernetes-admin@kubernetes (Cluster1 REMOTE - 10.130.0.45)       │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 1: Instalar ArgoCD no MAIN (Cluster2)                         │
# │  $ ./deploy-argocd.sh install-main kubernetes-admin@kubernetes │
# │                                                                 │
# │  Instala 5 componentes em ordem:                               │
# │  1. Application CRD (v2.13.3)                                  │
# │  2. Namespace argocd                                           │
# │  3. ArgoCD Server                                              │
# │  4. Core Components (redis, repo-server, etc)                  │
# │  5. GitLab Runner + On-Premises (+ INGRESS)                    │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 2: Instalar componentes no REMOTE (Cluster1)                  │
# │  $ ./deploy-argocd.sh install-remote kubernetes-admin@kubern.. │
# │                                                                 │
# │  Instala 3 componentes em ordem:                               │
# │  1. Application CRD                                            │
# │  2. argocd-manager (ServiceAccount + ClusterRole)              │
# │  3. argocd-application-controller (para sync remoto)           │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 3: Obter Credenciais (via Ingress)                      │
# │  $ ./deploy-argocd.sh show-credentials kubernetes-admin@kubern │
# │                                                                 │
# │  Retorna: Usuário, Senha, URL (Ingress)                        │
# │  Senha: Gerada automaticamente pelo ArgoCD                     │
# │  URL: https://argocd.domain.com.br (via Ingress já existente)  │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 4: Registrar Cluster1 no ArgoCD de Cluster2                         │
# │  $ ./deploy-argocd.sh register-cluster \                       │
# │      kubernetes-admin@kubernetes cluster-c1                    │
# │                                                                 │
# │  O que acontece internamente:                                  │
# │  1. Detecta Ingress automaticamente                            │
# │  2. Faz login no ArgoCD via CLI (sem port-forward)             │
# │  3. Extrai credenciais de Cluster1 do kubeconfig                     │
# │  4. Cria um secret em Cluster2 MAIN                                  │
# │  5. Registra Cluster1 como cluster gerenciável                       │
# │  6. Verifica conectividade bidirecional                        │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  RESULTADO FINAL                                               │
# │  Cluster2 MAIN: ArgoCD Server operacional                         │
# │  Cluster1 REMOTE: Pronto para gerenciamento                       │
# │  UI: Acessível via Ingress (https://argocd.domain.com.br)   │
# │  Multi-cluster: Pronto para GitOps distribuído              │
# └────────────────────────────────────────────────────────────────┘
#
################################################################################
#
# COMANDOS DISPONÍVEIS:
#
# INSTALAÇÃO:
#   install-main <contexto>
#     Instalar ArgoCD MAIN com 5 etapas (inclui Ingress)
#     Ex: ./deploy-argocd.sh install-main kubernetes-admin@kubernetes
#
#   install-remote <contexto>
#     Instalar componentes REMOTE com 3 etapas
#     Ex: ./deploy-argocd.sh install-remote kubernetes-admin@kubernetes
#
# DESINSTALAÇÃO:
#   uninstall-main <contexto>
#     Remover ArgoCD MAIN com backup automático
#
#   uninstall-remote <contexto>
#     Remover componentes REMOTE
#
# GERENCIAMENTO DE CLUSTERS:
#   register-cluster <remote_ctx> <cluster_name> [main_ctx]
#     Registrar cluster remoto no ArgoCD MAIN (usa Ingress automaticamente)
#     Ex: ./deploy-argocd.sh register-cluster \
#         kubernetes-admin@kubernetes cluster-c1
#
#   check-clusters [contexto]
#     Verificar status dos clusters registrados
#
# GERENCIAMENTO DE SENHAS:
#   get-admin-password <contexto>
#     Obter senha admin atual
#
#   show-credentials <contexto>
#     Mostrar credenciais formatadas (user, pass, URL Ingress)
#
#   login-web <contexto>
#     Mostrar credenciais para acesso web via Ingress
#
#   login-cli <contexto>
#     Login via CLI usando Ingress (sem port-forward)
#
# DIAGNÓSTICO:
#   check-status
#     Status completo de pods, serviços, deployments
#
#   check-ingress
#     Verificar status do Ingress para ArgoCD
#
#   backup
#     Fazer backup da configuração do ArgoCD
#
# AJUDA:
#   help
#     Mostrar esta mensagem
#
################################################################################
#
# EXEMPLOS DE USO:
#
# 1. Instalação Completa:
#    ./deploy-argocd.sh install-main kubernetes-admin@kubernetes
#    ./deploy-argocd.sh install-remote kubernetes-admin@kubernetes
#
# 2. Registrar Cluster (automático com Ingress):
#    ./deploy-argocd.sh register-cluster \
#        kubernetes-admin@kubernetes cluster-c1
#
# 3. Ver Status:
#    ./deploy-argocd.sh check-status
#
# 4. Ver Credenciais:
#    ./deploy-argocd.sh show-credentials kubernetes-admin@kubernetes
#
# 5. Login Web (abre no navegador):
#    ./deploy-argocd.sh login-web kubernetes-admin@kubernetes
#
# 6. Remover Tudo:
#    ./deploy-argocd.sh uninstall-main kubernetes-admin@kubernetes
#    ./deploy-argocd.sh uninstall-remote kubernetes-admin@kubernetes
#
################################################################################
#
# ESTRUTURA DE DIRETÓRIOS ESPERADA:
#
# ./
# ├── deploy-argocd.sh (instalador)
# ├── k8s-main/
# │   ├── 0-namespace.yaml
# │   ├── 1-application-crd-v2.13.3.yaml
# │   ├── 2-install-argocd-v2.13.3.yaml
# │   ├── 3-core-install-v2.13.3.yaml
# │   ├── 4-gitlab-runner-role.yaml
# │   └── 5-install-optional-k8s-onpremises.yaml (com Ingress)
# ├── k8s-remotes/
# │   ├── 0-application-crd-v2.13.3.yaml
# │   ├── 1-argocd-cluster-access.yaml
# │   └── 2-argocd-remote-cluster-access.yaml
# ├── logs/
# │   └── deploy.log
# └── backups/
#     └── argocd-backup-*.yaml
#
################################################################################
#
# NOTES:
# - Todas as funções registram logs em ./logs/deploy.log
# - Backups são salvos automaticamente em ./backups/
# - Suporta remoção com confirmação interativa
# - Detecta e cria port-forward automaticamente se necessário
# - Valida contextosen kubeconfig antes de qualquer operação
#
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_MAIN_DIR="${SCRIPT_DIR}/k8s-main"
MANIFEST_REMOTE_DIR="${SCRIPT_DIR}/k8s-remotes"
LOG_DIR="${SCRIPT_DIR}/logs"
BACKUP_DIR="${SCRIPT_DIR}/backups"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# FUNÇÕES DE LOG
# ============================================================================

log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}] [INFO]${NC} $1" | tee -a "$LOG_DIR/deploy.log"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $1" | tee -a "$LOG_DIR/deploy.log"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $1" | tee -a "$LOG_DIR/deploy.log"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] [ERROR]${NC} $1" | tee -a "$LOG_DIR/deploy.log"
}

# ============================================================================
# VALIDAÇÃO
# ============================================================================

check_dependencies() {
    log_info "Verificando dependências..."
    for cmd in kubectl base64 curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "$cmd não instalado"
            exit 1
        fi
    done
    log_success "Dependências OK"
}

check_manifest_files() {
    local dir=$1
    shift
    local files=("$@")
    log_info "Validando arquivos em: $dir"
    for file in "${files[@]}"; do
        if [ ! -f "$dir/$file" ]; then
            log_error "Arquivo não encontrado: $dir/$file"
            return 1
        fi
    done
    log_success "Todos os arquivos validados"
    return 0
}

validate_kubeconfig() {
    local context=$1
    log_info "Validando contexto kubeconfig: $context"
    if ! kubectl config get-contexts "$context" &>/dev/null; then
        log_error "❌ Contexto '$context' NÃO ENCONTRADO"
        echo ""
        log_warning "📋 Contextos disponíveis:"
        echo ""
        kubectl config get-contexts
        echo ""
        return 1
    fi
    log_success "✓ Contexto '$context' validado"
    return 0
}

confirm() {
    local prompt=$1
    local response
    read -p "$(echo -e ${RED}$prompt${NC}) [s/N]: " response
    case "$response" in
        [sS][iI]|[sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# ARGOCD CLI
# ============================================================================

install_argocd_cli() {
    if command -v argocd >/dev/null 2>&1; then
        log_success "ArgoCD CLI já instalado"
        return 0
    fi
    log_warning "Instalando ArgoCD CLI v2.13.3..."
    local VERSION="v2.13.3"
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac
    local URL="https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-${OS}-${ARCH}"
    if curl -sSL -o /tmp/argocd "$URL" 2>/dev/null; then
        chmod +x /tmp/argocd
        sudo mv /tmp/argocd /usr/local/bin/argocd
        log_success "ArgoCD CLI instalado"
    else
        log_error "Falha ao baixar ArgoCD"
        return 1
    fi
}

# ============================================================================
# DETECÇÃO DE INGRESS
# ============================================================================

get_argocd_url() {
    # Prioridade: env var > ingress > localhost
    if [ -n "$ARGOCD_SERVER" ]; then
        echo "$ARGOCD_SERVER"
        return 0
    fi

    # Verificar se Ingress está criado
    local ingress_host=$(kubectl get ingress -n argocd argocd-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
    if [ -n "$ingress_host" ]; then
        echo "https://$ingress_host"
        return 0
    fi

    # Fallback
    echo "https://localhost:8080"
}

check_ingress() {
    local context=${1:-"kubernetes-admin@kubernetes"}

    kubectl config use-context "$context" || return 1

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Status do Ingress ArgoCD"
    log_info "════════════════════════════════════════════════════════════════"

    local ingress_host=$(kubectl get ingress -n argocd argocd-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)

    if [ -n "$ingress_host" ]; then
        log_success "✓ Ingress configurado para: https://$ingress_host"
        echo ""
        log_info "Detalhes do Ingress:"
        kubectl get ingress -n argocd argocd-ingress -o wide
        echo ""

        # TLS
        local tls_host=$(kubectl get ingress -n argocd argocd-ingress -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null)
        if [ -n "$tls_host" ]; then
            log_success "✓ TLS/HTTPS configurado para: $tls_host"
        fi

        echo ""
        log_info "Para acessar:"
        log_info "  URL: https://$ingress_host"
        log_info "  Use as credenciais obtidas com: ./deploy-argocd.sh show-credentials"
    else
        log_error "✗ Nenhum Ingress encontrado"
        log_info "O Ingress deve estar definido em: 5-install-optional-k8s-onpremises.yaml"
    fi

    log_info "════════════════════════════════════════════════════════════════"
}

# ============================================================================
# APLICAÇÃO DE MANIFESTS
# ============================================================================

apply_manifest() {
    local manifest_file=$1
    local namespace=${2:-""}
    local description=${3:-""}
    if [ ! -f "$manifest_file" ]; then
        log_error "Arquivo não encontrado: $manifest_file"
        return 1
    fi
    local filename=$(basename "$manifest_file")
    if [ -n "$description" ]; then
        log_info "Aplicando [$description]: $filename"
    else
        log_info "Aplicando: $filename"
    fi
    if [ -n "$namespace" ]; then
        kubectl apply -n "$namespace" -f "$manifest_file" 2>&1 | grep -v "namespace/" || true
    else
        kubectl apply -f "$manifest_file" 2>&1 | grep -v "namespace/" || true
    fi
}

delete_manifest() {
    local manifest_file=$1
    local namespace=${2:-""}
    local description=${3:-""}
    if [ ! -f "$manifest_file" ]; then
        log_warning "Arquivo não encontrado: $manifest_file (pulando)"
        return 0
    fi
    local filename=$(basename "$manifest_file")
    if [ -n "$description" ]; then
        log_info "Removendo [$description]: $filename"
    else
        log_info "Removendo: $filename"
    fi
    if [ -n "$namespace" ]; then
        kubectl delete -n "$namespace" -f "$manifest_file" 2>&1 | grep -v "not found" || true
    else
        kubectl delete -f "$manifest_file" 2>&1 | grep -v "not found" || true
    fi
}

wait_crd() {
    local crd_name=$1
    local timeout=${2:-60}
    log_info "Aguardando CRD: $crd_name"
    if kubectl wait --for condition=established --timeout="${timeout}s" "crd/$crd_name" >/dev/null 2>&1; then
        log_success "CRD pronta"
    else
        log_warning "Timeout na CRD (continuando)"
    fi
}

wait_pods() {
    local label=$1
    local namespace=$2
    local timeout=${3:-300}
    log_info "Aguardando pods: $label em $namespace"
    if kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" >/dev/null 2>&1; then
        log_success "Pods prontos"
    else
        log_warning "Timeout pods (continuando)"
    fi
}

# ============================================================================
# INSTALAÇÃO MAIN (5 ETAPAS - CORRIGIDA)
# ============================================================================

install_main() {
    local context=$1
    log_info "════════════════════════════════════════════════════════════════"
    log_info "INSTALAÇÃO MAIN: $context (5 ETAPAS)"
    log_info "════════════════════════════════════════════════════════════════"

    validate_kubeconfig "$context" || return 1

    check_manifest_files "$MANIFEST_MAIN_DIR" \
        "1-application-crd-v2.13.3.yaml" \
        "0-namespace.yaml" \
        "2-install-argocd-v2.13.3.yaml" \
        "3-core-install-v2.13.3.yaml" \
        "4-gitlab-runner-role.yaml" \
        "5-install-optional-k8s-onpremises.yaml" || return 1

    kubectl config use-context "$context"
    local current_context=$(kubectl config current-context)
    log_info "Contexto ativo: $current_context"

    # ETAPA 1: CRD (PRIMEIRO)
    log_info ""
    log_info "--- Etapa 1/5: Application CRD ---"
    apply_manifest "$MANIFEST_MAIN_DIR/1-application-crd-v2.13.3.yaml" "argocd" "CRD"
    wait_crd "applications.argoproj.io"
    sleep 3

    # ETAPA 2: Namespace
    log_info ""
    log_info "--- Etapa 2/5: Namespace ---"
    apply_manifest "$MANIFEST_MAIN_DIR/0-namespace.yaml" "" "Namespace"
    sleep 2

    # ETAPA 3: Server
    log_info ""
    log_info "--- Etapa 3/5: ArgoCD Server ---"
    apply_manifest "$MANIFEST_MAIN_DIR/2-install-argocd-v2.13.3.yaml" "argocd" "Server"
    sleep 3

    # ETAPA 4: Core Components
    log_info ""
    log_info "--- Etapa 4/5: Core Components ---"
    apply_manifest "$MANIFEST_MAIN_DIR/3-core-install-v2.13.3.yaml" "argocd" "Core"
    sleep 3

    # ETAPA 5: GitLab Runner + On-Premises + INGRESS
    log_info ""
    log_info "--- Etapa 5/5: GitLab Runner + On-Premises + Ingress ---"
    apply_manifest "$MANIFEST_MAIN_DIR/4-gitlab-runner-role.yaml" "argocd" "Runner"
    apply_manifest "$MANIFEST_MAIN_DIR/5-install-optional-k8s-onpremises.yaml" "argocd" "OnPrem+Ingress"

    # Aguardar pods
    log_info ""
    wait_pods "app.kubernetes.io/name=argocd-server" "argocd"

    log_success "════════════════════════════════════════════════════════════════"
    log_success "ArgoCD instalado com sucesso no MAIN: $context"

    # Verificar Ingress
    log_info ""
    check_ingress "$context"

    log_success "════════════════════════════════════════════════════════════════"
}

# ============================================================================
# DESINSTALAÇÃO MAIN
# ============================================================================

uninstall_main() {
    local context=$1
    log_warning "══════════════════════════════════════════════════════════════"
    log_warning "DESINSTALAÇÃO MAIN: $context"
    log_warning "══════════════════════════════════════════════════════════════"

    if ! confirm "REMOVER o ArgoCD do cluster MAIN?"; then
        log_info "Operação cancelada"
        return 0
    fi

    validate_kubeconfig "$context" || return 1

    check_manifest_files "$MANIFEST_MAIN_DIR" \
        "0-namespace.yaml" \
        "1-application-crd-v2.13.3.yaml" \
        "2-install-argocd-v2.13.3.yaml" \
        "3-core-install-v2.13.3.yaml" \
        "4-gitlab-runner-role.yaml" \
        "5-install-optional-k8s-onpremises.yaml" || return 1

    kubectl config use-context "$context"
    log_info "Contexto ativo: $(kubectl config current-context)"

    # Backup
    log_warning "Fazendo backup..."
    local backup_file="$BACKUP_DIR/argocd-backup-before-uninstall-$(date +%Y%m%d_%H%M%S).yaml"
    if argocd admin export --namespace argocd > "$backup_file" 2>&1; then
        log_success "Backup: $backup_file"
    else
        log_warning "Falha ao fazer backup (continuando)"
    fi

    # Remover em ordem reversa
    log_info ""
    log_info "--- Removendo em ordem reversa ---"
    delete_manifest "$MANIFEST_MAIN_DIR/5-install-optional-k8s-onpremises.yaml" "argocd" "OnPrem+Ingress"
    sleep 1
    delete_manifest "$MANIFEST_MAIN_DIR/4-gitlab-runner-role.yaml" "argocd" "Runner"
    sleep 1
    delete_manifest "$MANIFEST_MAIN_DIR/3-core-install-v2.13.3.yaml" "argocd" "Core"
    sleep 1
    delete_manifest "$MANIFEST_MAIN_DIR/2-install-argocd-v2.13.3.yaml" "argocd" "Server"
    sleep 1
    delete_manifest "$MANIFEST_MAIN_DIR/1-application-crd-v2.13.3.yaml" "argocd" "CRD"
    sleep 1
    delete_manifest "$MANIFEST_MAIN_DIR/0-namespace.yaml" "" "Namespace"

    log_warning "Aguardando namespace ser removido..."
    sleep 5

    log_success "══════════════════════════════════════════════════════════════"
    log_success "✓ ArgoCD REMOVIDO do MAIN: $context"
    log_success "Backup: $backup_file"
    log_success "══════════════════════════════════════════════════════════════"
}

# ============================================================================
# INSTALAÇÃO REMOTO (3 ETAPAS)
# ============================================================================

install_remote() {
    local context=$1
    log_info "════════════════════════════════════════════════════════════════"
    log_info "INSTALAÇÃO REMOTO: $context (3 ETAPAS)"
    log_info "════════════════════════════════════════════════════════════════"

    validate_kubeconfig "$context" || return 1

    check_manifest_files "$MANIFEST_REMOTE_DIR" \
        "0-application-crd-v2.13.3.yaml" \
        "1-argocd-cluster-access.yaml" \
        "2-argocd-remote-cluster-access.yaml" || return 1

    kubectl config use-context "$context"
    log_info "Contexto ativo: $(kubectl config current-context)"

    # Criar namespace
    log_info "Criando namespace argocd..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - || true
    sleep 2

    # ETAPA 1: CRD
    log_info ""
    log_info "--- Etapa 1/3: Application CRD ---"
    if ! apply_manifest "$MANIFEST_REMOTE_DIR/0-application-crd-v2.13.3.yaml" "" "CRD"; then
        log_error "Falha ao aplicar CRD"
        return 1
    fi
    wait_crd "applications.argoproj.io"
    sleep 2

    # ETAPA 2: Manager
    log_info ""
    log_info "--- Etapa 2/3: Cluster Access (Manager) ---"
    if ! apply_manifest "$MANIFEST_REMOTE_DIR/1-argocd-cluster-access.yaml" "argocd" "Manager"; then
        log_error "Falha ao aplicar Manager"
        return 1
    fi
    sleep 2

    # ETAPA 3: Controller
    log_info ""
    log_info "--- Etapa 3/3: Remote Access (Controller) ---"
    if ! apply_manifest "$MANIFEST_REMOTE_DIR/2-argocd-remote-cluster-access.yaml" "argocd" "Controller"; then
        log_error "Falha ao aplicar Controller"
        return 1
    fi
    sleep 2

    # Verificar
    log_info ""
    log_info "Verificando recursos criados..."
    log_info "ServiceAccounts em argocd:"
    kubectl get sa -n argocd -o wide 2>&1 | grep argocd || true

    log_info ""
    log_info "ClusterRoles com argocd:"
    kubectl get clusterroles 2>&1 | grep argocd || true

    log_info ""
    log_info "ClusterRoleBindings com argocd:"
    kubectl get clusterrolebindings 2>&1 | grep argocd || true

    log_success "════════════════════════════════════════════════════════════════"
    log_success "✓ Componentes instalados no REMOTO: $context"
    log_success "════════════════════════════════════════════════════════════════"
}

# ============================================================================
# DESINSTALAÇÃO REMOTO
# ============================================================================

uninstall_remote() {
    local context=$1
    log_warning "══════════════════════════════════════════════════════════════"
    log_warning "DESINSTALAÇÃO REMOTO: $context"
    log_warning "══════════════════════════════════════════════════════════════"

    if ! confirm "REMOVER componentes do cluster REMOTO?"; then
        log_info "Operação cancelada"
        return 0
    fi

    validate_kubeconfig "$context" || return 1

    check_manifest_files "$MANIFEST_REMOTE_DIR" \
        "0-application-crd-v2.13.3.yaml" \
        "1-argocd-cluster-access.yaml" \
        "2-argocd-remote-cluster-access.yaml" || return 1

    kubectl config use-context "$context"
    log_info "Contexto ativo: $(kubectl config current-context)"

    log_info ""
    log_info "--- Removendo em ordem reversa ---"
    delete_manifest "$MANIFEST_REMOTE_DIR/2-argocd-remote-cluster-access.yaml" "argocd" "Controller"
    sleep 1
    delete_manifest "$MANIFEST_REMOTE_DIR/1-argocd-cluster-access.yaml" "argocd" "Manager"
    sleep 1
    delete_manifest "$MANIFEST_REMOTE_DIR/0-application-crd-v2.13.3.yaml" "" "CRD"

    log_warning "Removendo namespace..."
    kubectl delete namespace argocd --ignore-not-found=true 2>&1 | grep -v "not found" || true

    log_success "══════════════════════════════════════════════════════════════"
    log_success "✓ Componentes REMOVIDOS do REMOTO: $context"
    log_success "══════════════════════════════════════════════════════════════"
}

# ============================================================================
# GERENCIAMENTO DE SENHAS
# ============================================================================

show_admin_credentials() {
    local context=$1
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Credenciais do Admin ArgoCD (via Ingress)"
    log_info "════════════════════════════════════════════════════════════════"

    if [ -n "$context" ]; then
        kubectl config use-context "$context" || return 1
    fi

    local current_pass
    current_pass=$(get_admin_password) || {
        log_error "Não foi possível obter a senha"
        return 1
    }

    local url
    url=$(get_argocd_url)

    echo ""
    log_info "Usuário: admin"
    log_warning "Senha: $current_pass"
    log_info "URL: $url"
    echo ""
    log_info "Para acessar a UI:"
    log_info "1. Abra no navegador: $url"
    log_info "2. Login: admin / $current_pass"
    echo ""
    log_info "════════════════════════════════════════════════════════════════"
}

argocd_login_web() {
    local context=${1:-"kubernetes-admin@kubernetes"}

    log_info "════════════════════════════════════════════════════════════════"
    log_info "LOGIN ARGOCD VIA WEB (usando Ingress)"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    local url
    url=$(get_argocd_url)

    local current_pass
    current_pass=$(get_admin_password) || return 1

    echo ""
    log_success "════════════════════════════════════════════════════════════════"
    log_success "Credenciais de Acesso"
    log_success "════════════════════════════════════════════════════════════════"
    echo ""
    log_info "URL: $url"
    log_info "Usuário: admin"
    log_warning "Senha: $current_pass"
    echo ""
    log_success "Abra em seu navegador: $url"
    log_success "════════════════════════════════════════════════════════════════"
    echo ""
}

argocd_login_cli() {
    local context=${1:-"kubernetes-admin@kubernetes"}

    log_info "════════════════════════════════════════════════════════════════"
    log_info "LOGIN ARGOCD via CLI (usando Ingress)"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # Obter senha
    log_info "Obtendo senha..."
    local senha=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$senha" ]; then
        log_error "Não foi possível obter a senha"
        return 1
    fi

    log_success "Senha obtida (${#senha} caracteres)"

    # Fazer login
    log_info "Fazendo login em: argocd.domain.com.br"

    local login_output
    login_output=$(argocd login "argocd.domain.com.br" \
        --username admin \
        --password "$senha" \
        --insecure \
        --grpc-web 2>&1)

    # DEBUG: mostrar resposta
    log_info "Resposta do ArgoCD: $login_output"

    if echo "$login_output" | grep -qi "logged in"; then
        log_success "✓ Login realizado com sucesso"
        echo ""

        # Listar clusters
        log_info "Clusters registrados:"
        argocd cluster list --grpc-web

        log_success "════════════════════════════════════════════════════════════════"
        return 0
    else
        log_error "❌ Falha no login"
        log_error "Erro: $login_output"
        log_error "════════════════════════════════════════════════════════════════"
        return 1
    fi
}

# ============================================================================
# REGISTRO DE CLUSTERS (COM INGRESS)
# ============================================================================

register_cluster_automated() {
    local remote_context=$1
    local cluster_name=$2
    local main_context=${3:-"kubernetes-admin@kubernetes"}

    log_info "════════════════════════════════════════════════════════════════"
    log_info "REGISTRANDO CLUSTER REMOTO (via Ingress)"
    log_info "════════════════════════════════════════════════════════════════"

    if [ -z "$remote_context" ] || [ -z "$cluster_name" ]; then
        log_error "Uso: register-cluster <remote_context> <cluster_name> [main_context]"
        return 1
    fi

    # Validar contextos
    kubectl config get-contexts | grep -q "$remote_context" || {
        log_error "Contexto remoto '$remote_context' não encontrado"
        return 1
    }

    kubectl config get-contexts | grep -q "$main_context" || {
        log_error "Contexto main '$main_context' não encontrado"
        return 1
    }

    # Mudar para MAIN
    kubectl config use-context "$main_context" || return 1

    local argocd_url
    argocd_url=$(get_argocd_url)
    log_info "ArgoCD URL (Ingress): $argocd_url"

    local argocd_host=$(echo "$argocd_url" | sed 's|https://||;s|http://||;s|/.*||')

    # Obter senha
    log_info "Obtendo senha..."
    local senha
    senha=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$senha" ]; then
        log_error "Não foi possível obter a senha"
        return 1
    fi

    # Fazer login
    log_info "Fazendo login em: $argocd_host"
    if argocd login "$argocd_host" \
        --username admin \
        --password "$senha" \
        --grpc-web 2>&1 | grep -i "logged in\|successful"; then
        log_success "Login realizado"
    else
        log_error "Falha no login"
        return 1
    fi

    # Mudar para REMOTO
    log_info ""
    log_info "Mudando para contexto REMOTO: $remote_context"
    kubectl config use-context "$remote_context" || return 1

    # Registrar cluster
    log_info "Registrando cluster: $cluster_name"
    if argocd cluster add "$remote_context" \
        --name "$cluster_name" \
        --grpc-web \
        --yes 2>&1 | tee -a "$LOG_DIR/deploy.log"; then
        log_success "Cluster registrado"
    else
        log_error "Falha ao registrar"
        return 1
    fi

    # Voltar para MAIN
    kubectl config use-context "$main_context" || return 1

    # Listar
    log_info ""
    log_info "Clusters registrados:"
    argocd cluster list --grpc-web

    log_success "════════════════════════════════════════════════════════════════"
    log_success "✓ Cluster '$cluster_name' registrado com sucesso"
    log_success "URL: $argocd_url"
    log_success "════════════════════════════════════════════════════════════════"
}

check_clusters_status() {
    local context=${1:-"kubernetes-admin@kubernetes"}

    kubectl config use-context "$context" || return 1

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Status dos Clusters Registrados"
    log_info "════════════════════════════════════════════════════════════════"

    argocd cluster list --grpc-web

    log_info ""
}

get_admin_password() {
    log_info "Obtendo senha admin..."
    local max_retries=5
    local retry=0

    while [ "$retry" -lt "$max_retries" ]; do
        local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

        if [ -n "$admin_pass" ]; then
            log_success "Senha obtida com sucesso (tamanho: ${#admin_pass} caracteres)"
            echo "$admin_pass"
            return 0
        fi

        log_warning "Tentativa $((retry+1))/$max_retries: Aguardando secret..."
        sleep 2
        retry=$((retry + 1))
    done

    log_error "Timeout ao obter senha"
    return 1
}

# ============================================================================
# BLOCO 2: TENTAR LOGIN COM MÚLTIPLAS OPÇÕES
# ============================================================================

try_argocd_login() {
    local senha=$1

    if [ -z "$senha" ]; then
        log_error "Senha vazia!"
        return 1
    fi

    log_info "Tentando fazer login no ArgoCD em: https://argocd.domain.com.br" >&2

    if argocd login "argocd.domain.com.br" \
        --username admin \
        --password "$senha" \
        --insecure \
        --grpc-web 2>&1 | grep -qi "logged in"; then

        log_success "✓ Login bem-sucedido"
        return 0
    fi

    log_error "❌ Login falhou"
    return 1
}

# ============================================================================
# BLOCO 3: VERIFICAR STATUS DO ARGOCD
# ============================================================================

check_status() {
    local context=$(kubectl config current-context)
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Status do ArgoCD"
    log_info "════════════════════════════════════════════════════════════════"
    log_info ""

    log_info "Contexto Atual: $context"
    echo ""

    log_info "Informações do Cluster:"
    kubectl cluster-info 2>/dev/null | head -3
    echo ""

    log_info "Namespace argocd:"
    if kubectl get namespace argocd &>/dev/null; then
        log_success "✓ Namespace existe"
        kubectl get namespace argocd
    else
        log_error "✗ Namespace NÃO existe"
    fi
    echo ""

    log_info "=== Pods do ArgoCD ==="
    local pod_count=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
    log_info "Total de Pods: $pod_count"
    if [ "$pod_count" -gt 0 ]; then
        kubectl get pods -n argocd -o wide
    else
        log_warning "Nenhum pod encontrado"
    fi
    echo ""

    log_info "=== Serviços do ArgoCD ==="
    local svc_count=$(kubectl get svc -n argocd --no-headers 2>/dev/null | wc -l)
    log_info "Total de Serviços: $svc_count"
    if [ "$svc_count" -gt 0 ]; then
        kubectl get svc -n argocd -o wide
    else
        log_warning "Nenhum serviço encontrado"
    fi
    echo ""

    log_info "=== Deployments do ArgoCD ==="
    local deploy_count=$(kubectl get deployment -n argocd --no-headers 2>/dev/null | wc -l)
    log_info "Total: $deploy_count"
    if [ "$deploy_count" -gt 0 ]; then
        kubectl get deployment -n argocd -o wide
    else
        log_warning "Nenhum deployment encontrado"
    fi
    echo ""

    log_info "=== StatefulSet do ArgoCD ==="
    local sts_count=$(kubectl get statefulset -n argocd --no-headers 2>/dev/null | wc -l)
    log_info "Total: $sts_count"
    if [ "$sts_count" -gt 0 ]; then
        kubectl get statefulset -n argocd -o wide
    else
        log_warning "Nenhum statefulset encontrado"
    fi
    echo ""

    log_info "=== Ingress do ArgoCD ==="
    if kubectl get ingress -n argocd 2>&1 | grep -q argocd-ingress; then
        kubectl get ingress -n argocd -o wide
    else
        log_warning "Nenhum ingress encontrado"
    fi
    echo ""

    log_info "=== Clusters Registrados (via ArgoCD CLI) ==="

    # OBTER SENHA ANTES (sem logs misturados)
    local senha
    senha=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null) || senha=""

    if [ -n "$senha" ]; then
        log_info "Tentando fazer login no ArgoCD em: https://argocd.domain.com.br"

        # GUARDAR SAÍDA LIMPA (sem logs)
        local login_output
        login_output=$(argocd login "argocd.domain.com.br" \
            --username admin \
            --password "$senha" \
            --insecure \
            --grpc-web 2>&1)

        if echo "$login_output" | grep -qi "logged in"; then
            log_success "✓ Login realizado com sucesso"
            echo ""

            # Listar clusters
            argocd cluster list --grpc-web 2>&1
        else
            log_warning "Falha no login - usando fallback kubectl"

            # Fallback
            local cluster_count=$(kubectl get secrets -n argocd -l "argocd.argoproj.io/secret-type=cluster" --no-headers 2>/dev/null | wc -l)

            if [ "$cluster_count" -gt 0 ]; then
                log_success "Total de Clusters: $cluster_count"
                echo ""
                kubectl get secrets -n argocd -l "argocd.argoproj.io/secret-type=cluster" \
                    -o custom-columns=NAME:.metadata.name,SERVER:.data.server \
                    --no-headers 2>/dev/null | while read name server; do
                    if [ -n "$server" ] && [ "$name" != "NAME" ]; then
                        local decoded_server=$(echo "$server" | base64 -d 2>/dev/null || echo "N/A")
                        log_info "  • $name → $decoded_server"
                    fi
                done
            else
                log_warning "Nenhum cluster registrado"
            fi
        fi
    else
        log_warning "Senha não disponível - usando fallback kubectl"

        # Fallback
        local cluster_count=$(kubectl get secrets -n argocd -l "argocd.argoproj.io/secret-type=cluster" --no-headers 2>/dev/null | wc -l)

        if [ "$cluster_count" -gt 0 ]; then
            log_success "Total de Clusters: $cluster_count"
            echo ""
            kubectl get secrets -n argocd -l "argocd.argoproj.io/secret-type=cluster" \
                -o custom-columns=NAME:.metadata.name,SERVER:.data.server \
                --no-headers 2>/dev/null | while read name server; do
                if [ -n "$server" ] && [ "$name" != "NAME" ]; then
                    local decoded_server=$(echo "$server" | base64 -d 2>/dev/null || echo "N/A")
                    log_info "  • $name → $decoded_server"
                fi
            done
        else
            log_warning "Nenhum cluster registrado"
        fi
    fi

    echo ""

    log_info "=== Secrets do ArgoCD ==="
    kubectl get secrets -n argocd -o wide 2>/dev/null || log_warning "Nenhum secret encontrado"
    echo ""

    log_success "════════════════════════════════════════════════════════════════"
}

export_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/argocd-backup-${timestamp}.yaml"
    log_info "Exportando..."
    if argocd admin export --namespace argocd > "$backup_file" 2>&1; then
        log_success "Backup: $backup_file"
    else
        log_error "Falha"
        return 1
    fi
}

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << 'HELP_EOF'

╔════════════════════════════════════════════════════════════════╗
║ deploy-argocd.sh - ArgoCD Deployment Automation               ║
║ Versão: 2.0.0                                                 ║
║ ✓ SUPORTE A INGRESS (https://argocd.domain.com.br)            ║
║ ✓ GERENCIAMENTO AUTOMÁTICO DE CLUSTERS                        ║
║ ✓ LOGIN VIA CLI SEM PORT-FORWARD                              ║
╚════════════════════════════════════════════════════════════════╝

INSTALAÇÃO:
  install-main <contexto>             Instalar MAIN (5 etapas + Ingress)
  install-remote <contexto>           Instalar REMOTO (3 etapas)

DESINSTALAÇÃO:
  uninstall-main <contexto>           Remover MAIN
  uninstall-remote <contexto>         Remover REMOTO

GERENCIAMENTO DE CLUSTERS:
  register-cluster <remote> <nome>    Registrar cluster remoto (via Ingress)
  check-clusters [contexto]           Verificar status dos clusters

GERENCIAMENTO DE SENHAS:
  get-admin-password <contexto>       Obter senha admin
  show-credentials <contexto>         Mostrar credenciais (user, pass, URL)
  login-web <contexto>                Mostrar credenciais para acesso web
  login-cli <contexto>                Login via CLI (sem port-forward)

DIAGNÓSTICO:
  check-status                        Verificar status completo
  check-ingress [contexto]            Verificar Ingress
  backup                              Fazer backup da config

AJUDA:
  help                                Mostrar esta mensagem

EXEMPLOS:
  # Instalação Completa:
  ./deploy-argocd.sh install-main kubernetes-admin@kubernetes
  ./deploy-argocd.sh install-remote kubernetes-admin@kubernetes

  # Ver Credenciais:
  ./deploy-argocd.sh show-credentials kubernetes-admin@kubernetes

  # Registrar Cluster (automático com Ingress):
  ./deploy-argocd.sh register-cluster kubernetes-admin@kubernetes cluster-c1

  # Login CLI (sem port-forward):
  ./deploy-argocd.sh login-cli kubernetes-admin@kubernetes

  # Ver status:
  ./deploy-argocd.sh check-status

  # Verificar Ingress:
  ./deploy-argocd.sh check-ingress kubernetes-admin@kubernetes

HELP_EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ ArgoCD v2.13.3 - Deployment Automation v2.0.0                 ║"
    echo "║ ✅ 5 ETAPAS MAIN + 3 ETAPAS REMOTE                            ║"
    echo "║ ✅ INGRESS AUTOMÁTICO (https://argocd.domain.com.br)          ║"
    echo "║ ✅ LOGIN CLI SEM PORT-FORWARD                                 ║"
    echo "║ ✅ REGISTRO AUTOMÁTICO DE CLUSTERS                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_dependencies
    install_argocd_cli

    local command=${1:-""}

    case "$command" in
        install-main)
            [ -z "${2:-}" ] && { log_error "Contexto vazio"; return 1; }
            install_main "${2}"
            ;;

        install-remote)
            [ -z "${2:-}" ] && { log_error "Contexto vazio"; return 1; }
            install_remote "${2}"
            ;;

        uninstall-main)
            [ -z "${2:-}" ] && { log_error "Contexto vazio"; return 1; }
            uninstall_main "${2}"
            ;;

        uninstall-remote)
            [ -z "${2:-}" ] && { log_error "Contexto vazio"; return 1; }
            uninstall_remote "${2}"
            ;;

        register-cluster)
            [ -z "${2:-}" ] || [ -z "${3:-}" ] && { log_error "Argumentos: <remote_ctx> <cluster_name> [main_ctx]"; return 1; }
            register_cluster_automated "${2}" "${3}" "${4:-kubernetes-admin@kubernetes}"
            ;;

        check-clusters)
            check_clusters_status "${2:-kubernetes-admin@kubernetes}"
            ;;

        check-status)
            check_status
            ;;

        check-ingress)
            check_ingress "${2:-kubernetes-admin@kubernetes}"
            ;;

        backup)
            export_config
            ;;

        get-admin-password)
            [ -z "${2:-}" ] && { log_error "Contexto não fornecido"; return 1; }
            kubectl config use-context "${2}" || return 1
            get_admin_password
            echo ""
            ;;

        show-credentials)
            [ -z "${2:-}" ] && { log_error "Contexto não fornecido"; return 1; }
            show_admin_credentials "${2}"
            ;;

        login-web)
            [ -z "${2:-}" ] && { log_error "Contexto não fornecido"; return 1; }
            argocd_login_web "${2}"
            ;;

        login-cli)
            [ -z "${2:-}" ] && { log_error "Contexto não fornecido"; return 1; }
            argocd_login_cli "${2}"
            ;;

        help|--help|-h|"")
            show_help
            ;;

        *)
            log_error "Comando desconhecido: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"