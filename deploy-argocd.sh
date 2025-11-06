#!/bin/bash

################################################################################
# ArgoCD v2.13.3 Deployment Automation
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
# │  - kubernetes-admin@kubernetes (C2 MAIN)                       │
# │  - kubernetes-admin@kubernetes (C1 REMOTE)                     │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 1: Instalar ArgoCD no MAIN (C2)                         │
# │  $ ./deploy-argocd.sh install-main kubernetes-admin@kubernetes │
# │                                                                │
# │  Instala 5 componentes em ordem:                               │
# │  1. Application CRD (v2.13.3)                                  │
# │  2. Namespace argocd                                           │
# │  3. ArgoCD Server                                              │
# │  4. Core Components (redis, repo-server, etc)                  │
# │  5. GitLab Runner + On-Premises (+ INGRESS)                    │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 2: Instalar componentes no REMOTE (C1)                  │
# │  $ ./deploy-argocd.sh install-remote kubernetes-admin@kubern.. │
# │                                                                │
# │  Instala 3 componentes em ordem:                               │
# │  1. Application CRD                                            │
# │  2. argocd-manager (ServiceAccount + ClusterRole)              │
# │  3. argocd-application-controller (para sync remoto)           │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 3: Obter Credenciais (via Ingress)                      │
# │  $ ./deploy-argocd.sh show-credentials kubernetes-admin@kubern │
# │                                                                │
# │  Retorna: Usuário, Senha, URL (Ingress)                        │
# │  Senha: Gerada automaticamente pelo ArgoCD                     │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  ETAPA 4: Registrar C1 no ArgoCD de C2                         │
# │  $ ./deploy-argocd.sh register-cluster \                       │
# │      kubernetes-admin@kubernetes cluster-c1                    │
# │                                                                │
# │  O que acontece internamente:                                  │
# │  1. Detecta Ingress automaticamente                            │
# │  2. Faz login no ArgoCD via CLI (sem port-forward)             │
# │  3. Extrai credenciais de C1 do kubeconfig                     │
# │  4. Cria um secret em C2 MAIN                                  │
# │  5. Registra C1 como cluster gerenciável                       │
# │  6. Verifica conectividade bidirecional                        │
# └────────────────────────────────────────────────────────────────┘
#            ↓
# ┌────────────────────────────────────────────────────────────────┐
# │  RESULTADO FINAL                                               │
# │  C2 MAIN: ArgoCD Server operacional                            │
# │  C1 REMOTE: Pronto para gerenciamento                          │
# │  Multi-cluster: Pronto para GitOps distribuído                 │
# └────────────────────────────────────────────────────────────────┘
#
################################################################################
#
# PRINCIPAIS COMANDOS DISPONÍVEIS:
#
# INSTALAÇÃO:
#   install-main <contexto>
#     Instalar ArgoCD MAIN
#     Ex: ./deploy-argocd.sh install-main kubernetes-admin@kubernetes
#
#   install-remote <contexto>
#     Instalar componentes REMOTE
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
# NOTES:
# - Todas as funções registram logs em ./logs/deploy.log
# - Backups são salvos automaticamente em ./backups/
# - Suporta remoção com confirmação interativa
# - Valida contextos em kubeconfig antes de qualquer operação
#
################################################################################

set -e

# URL DO ARGOCD (PARAMETRIZAÇÃO)
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd.domain.com.br}"

# Namespace padrão
ARGOCD_NAMESPACE="argocd"

# Contexto padrão
DEFAULT_CONTEXT="kubernetes-admin@kubernetes"

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
# INSTALAÇÃO MAIN
# ============================================================================

install_main() {
    local context=$1
    log_info "════════════════════════════════════════════════════════════════"
    log_info "INSTALAÇÃO MAIN: $context "
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
# INSTALAÇÃO REMOTO
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
    log_info "Fazendo login em: $ARGOCD_SERVER"

    local login_output
    login_output=$(argocd login "$ARGOCD_SERVER" \
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
# CRIAR USUÁRIO
# ============================================================================

create_argocd_user() {
    local username=${1:-""}
    local password=${2:-""}
    local context=${3:-"kubernetes-admin@kubernetes"}

    if [ -z "$username" ] || [ -z "$password" ]; then
        log_error "Uso: create_argocd_user <username> <password> [context]"
        log_info "Exemplo: ./deploy-argocd.sh create-user devuser pass@user2025"
        return 1
    fi

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Criar Novo Usuário ArgoCD (role:developer)"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Obter senha do admin
    log_info "Obtendo credenciais de admin..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter senha do admin"
        return 1
    fi

    log_success "Credenciais obtidas"
    echo ""

    # 2. Fazer login como admin
    log_info "Fazendo login como admin..."
    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null; then
        log_error "Falha ao fazer login como admin"
        return 1
    fi

    log_success "Login realizado"
    echo ""

    # 3. Obter política ATUAL
    log_info "Obtendo política RBAC atual..."

    local current_policy=$(kubectl get configmap argocd-rbac-cm -n argocd -o jsonpath='{.data.policy\.csv}' 2>/dev/null)

    if [ -z "$current_policy" ]; then
        log_error "ConfigMap argocd-rbac-cm não encontrado"
        return 1
    fi

    log_success "Política obtida"
    echo ""

    # 4. Verificar se usuário já existe
    log_info "Verificando se usuário '$username' já existe..."

    if echo "$current_policy" | grep -q "^g, $username,"; then
        log_error "Usuário '$username' já existe na política RBAC"
        return 1
    fi

    log_success "Usuário não existe, prosseguindo..."
    echo ""

    # 5. Adicionar usuário à política
    log_info "Adicionando '$username' com role:developer..."

    local new_policy="$current_policy"$'\n'"    g, $username, role:developer"

    # Patch apenas a linha nova
    if ! kubectl patch configmap argocd-rbac-cm -n argocd --type merge \
        -p "{\"data\":{\"policy.csv\":$(echo "$new_policy" | jq -Rs .)}}" 2>&1 >/dev/null; then
        log_error "Falha ao atualizar RBAC"
        return 1
    fi

    log_success "Usuário adicionado à RBAC"
    echo ""

    # 6. Criar usuário no ConfigMap argocd-cm
    log_info "Criando usuário '$username' em argocd-cm..."

    if ! kubectl patch configmap argocd-cm -n argocd --type merge \
        -p "{\"data\":{\"accounts.$username\":\"apiKey,login\"}}" 2>&1 >/dev/null; then
        log_error "Falha ao criar usuário no ConfigMap"
        return 1
    fi

    log_success "Usuário criado"
    echo ""

    # 7. Reiniciar ArgoCD
    log_info "Reiniciando ArgoCD Server..."
    kubectl rollout restart deployment/argocd-server -n argocd 2>&1 >/dev/null
    kubectl rollout status deployment/argocd-server -n argocd --timeout=5m 2>&1 >/dev/null

    log_success "ArgoCD reiniciado"
    echo ""

    # 8. Definir senha
    log_info "Definindo senha do usuário '$username'..."
    sleep 5

    argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null

    if argocd account update-password \
        --account "$username" \
        --new-password "$password" \
        --current-password "$admin_pass" \
        --grpc-web 2>&1 >/dev/null; then
        log_success "✓ Senha definida com sucesso"
    else
        log_error "Falha ao definir senha"
        return 1
    fi

    echo ""
    log_success "════════════════════════════════════════════════════════════════"
    log_success "✓ Usuário criado com sucesso!"
    log_success "════════════════════════════════════════════════════════════════"
    log_info "Username: $username"
    log_info "Role: developer"
    log_info "URL: https://$ARGOCD_SERVER"
    log_success "════════════════════════════════════════════════════════════════"

    return 0
}

# ============================================================================
# ALTERAR SENHA
# ============================================================================

change_argocd_password() {
    local username=${1:-""}
    local new_password=${2:-""}
    local context=${3:-"kubernetes-admin@kubernetes"}

    if [ -z "$username" ] || [ -z "$new_password" ]; then
        log_error "Uso: change_argocd_password <username> <new_password> [context]"
        log_info "Exemplo: ./deploy-argocd.sh change-password devuser NewPass@2025"
        return 1
    fi

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Alterar Senha do Usuário"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Obter senha admin
    log_info "Obtendo credenciais de admin..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter senha do admin"
        return 1
    fi

    log_success "Credenciais obtidas"
    echo ""

    # 2. Fazer login
    log_info "Fazendo login como admin..."
    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null; then
        log_error "Falha ao fazer login"
        return 1
    fi

    log_success "Login realizado"
    echo ""

    # 3. Verificar se usuário existe
    log_info "Verificando se usuário '$username' existe..."

    if ! argocd account list --grpc-web 2>&1 | grep -q "$username"; then
        log_error "Usuário '$username' não encontrado"
        return 1
    fi

    log_success "Usuário encontrado"
    echo ""

    # 4. Alterar senha
    log_info "Alterando senha de '$username'..."

    if argocd account update-password \
        --account "$username" \
        --new-password "$new_password" \
        --current-password "$admin_pass" \
        --grpc-web 2>&1 >/dev/null; then

        log_success "✓ Senha alterada com sucesso"
        echo ""
        log_success "════════════════════════════════════════════════════════════════"
        log_info "Username: $username"
        log_info "Nova senha definida com sucesso"
        log_success "════════════════════════════════════════════════════════════════"
        return 0
    else
        log_error "Falha ao alterar senha"
        return 1
    fi
}

# ============================================================================
# LISTAR USUÁRIOS COM ROLES
# ============================================================================

list_argocd_users() {
    local context=${1:-"kubernetes-admin@kubernetes"}

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Usuários e Roles do ArgoCD"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Obter senha admin
    log_info "Obtendo credenciais..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter credenciais"
        return 1
    fi

    # 2. Fazer login
    argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null

    echo ""
    log_info "Usuários registrados:"
    echo ""
    argocd account list --grpc-web

    echo ""
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Roles RBAC configuradas:"
    log_info "════════════════════════════════════════════════════════════════"
    echo ""

    kubectl get configmap argocd-rbac-cm -n argocd -o jsonpath='{.data.policy\.csv}' | \
        grep "^g," | \
        awk '{print "  " $0}'

    echo ""
    log_success "════════════════════════════════════════════════════════════════"

    return 0
}

generate_argocd_token() {
    local username=${1:-""}
    local expiration=${2:-""}
    local context=${3:-"kubernetes-admin@kubernetes"}

    if [ -z "$username" ]; then
        log_error "Uso: generate_argocd_token <username> [expiration_seconds] [context]"
        log_info "Exemplos:"
        log_info "  - Token permanente: ./deploy-argocd.sh generate-token devuser"
        log_info "  - Token válido 1h: ./deploy-argocd.sh generate-token devuser 3600"
        return 1
    fi

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Gerar Token ArgoCD para CI/CD Pipeline"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Obter senha admin
    log_info "Obtendo credenciais de admin..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter senha do admin"
        return 1
    fi

    log_success "Credenciais obtidas"
    echo ""

    # 2. Fazer login como admin
    log_info "Fazendo login como admin..."
    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null; then
        log_error "Falha ao fazer login como admin"
        return 1
    fi

    log_success "Login realizado"
    echo ""

    # 3. Verificar se usuário existe
    log_info "Verificando se usuário '$username' existe..."

    if ! argocd account list --grpc-web 2>&1 | grep -q "^$username"; then
        log_error "Usuário '$username' não encontrado"
        return 1
    fi

    log_success "Usuário encontrado"
    echo ""

    # 4. Gerar token
    log_info "Gerando token para '$username'..."

    local token
    if [ -n "$expiration" ] && [ "$expiration" -gt 0 ]; then
        log_info "Validade: $expiration segundos ($(($expiration / 3600)) horas)"
        token=$(argocd account generate-token --account "$username" \
            --expiration "$expiration" \
            --grpc-web 2>&1)
    else
        log_info "Validade: permanente (até revogação)"
        token=$(argocd account generate-token --account "$username" \
            --grpc-web 2>&1)
    fi

    # Verificar se token foi gerado (extrair apenas o token, sem logs)
    token=$(echo "$token" | grep -v "^INFO\|^WARNING\|^ERROR\|^DEBUG\|^\[" | tail -1)

    if [ -z "$token" ] || echo "$token" | grep -q "error"; then
        log_error "Falha ao gerar token"
        return 1
    fi

    echo ""
    log_success "════════════════════════════════════════════════════════════════"
    log_success "✓ Token gerado com sucesso!"
    log_success "════════════════════════════════════════════════════════════════"
    log_info "Username: $username"
    if [ -n "$expiration" ] && [ "$expiration" -gt 0 ]; then
        local hours=$((expiration / 3600))
        local minutes=$(((expiration % 3600) / 60))
        log_info "Válido por: ${hours}h ${minutes}m"
    else
        log_info "Válido até: revogação manual"
    fi
    echo ""
    log_info "Token (ARGOCD_TOKEN):"
    echo ""
    echo "$token"
    echo ""
    log_warning "════════════════════════════════════════════════════════════════"
    log_warning "⚠️  IMPORTANTE:"
    log_warning "  • Copie e armazene em local seguro"
    log_warning "  • NUNCA commitar em Git"
    log_warning "  • Armazenar em CI/CD Secrets"
    log_warning "  • Rotacionar periodicamente"
    log_warning "════════════════════════════════════════════════════════════════"

    # Salvar em arquivo local com permissões restritas
    local token_file="${HOME}/.argocd/${username}-token.txt"
    mkdir -p "${HOME}/.argocd"

    if echo "$token" > "$token_file" 2>/dev/null; then
        chmod 600 "$token_file"
        log_success "Token salvo em: $token_file (permissões 600)"
    fi

    return 0
}

# ============================================================================
# LISTAR TOKENS ARGOCD
# ============================================================================

list_argocd_tokens() {
    local username=${1:-""}
    local context=${2:-"kubernetes-admin@kubernetes"}

    if [ -z "$username" ]; then
        log_error "Uso: list_argocd_tokens <username> [context]"
        log_info "Exemplo: ./deploy-argocd.sh list-tokens devuser"
        return 1
    fi

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Listar Tokens ArgoCD"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Obter senha admin
    log_info "Obtendo credenciais de admin..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter senha do admin"
        return 1
    fi

    log_success "Credenciais obtidas"
    echo ""

    # 2. Fazer login
    log_info "Fazendo login como admin..."
    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null; then
        log_error "Falha ao fazer login"
        return 1
    fi

    log_success "Login realizado"
    echo ""

    # 3. Listar informações do usuário (inclui tokens)
    log_info "Informações de '$username':"
    echo ""

    argocd account get --account "$username" --grpc-web

    echo ""
    log_success "════════════════════════════════════════════════════════════════"

    return 0
}

# ============================================================================
# REVOGAR TOKEN ARGOCD (POR ID)
# ============================================================================

revoke_argocd_token() {
    local username=${1:-""}
    local token_id=${2:-""}
    local context=${3:-"kubernetes-admin@kubernetes"}

    if [ -z "$username" ] || [ -z "$token_id" ]; then
        log_error "Uso: revoke_argocd_token <username> <token_id> [context]"
        log_info "Exemplo: ./deploy-argocd.sh revoke-token devuser token-123"
        log_info ""
        log_info "Para listar tokens:"
        log_info "  ./deploy-argocd.sh list-tokens devuser"
        return 1
    fi

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Revogar Token ArgoCD"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Obter senha admin
    log_info "Obtendo credenciais de admin..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter senha do admin"
        return 1
    fi

    log_success "Credenciais obtidas"
    echo ""

    # 2. Fazer login
    log_info "Fazendo login como admin..."
    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null; then
        log_error "Falha ao fazer login"
        return 1
    fi

    log_success "Login realizado"
    echo ""

    # 3. Revogar token
    log_info "Revogando token ID '$token_id' de '$username'..."

    if argocd account revoke-token --account "$username" --id "$token_id" --grpc-web 2>&1 >/dev/null; then
        echo ""
        log_success "════════════════════════════════════════════════════════════════"
        log_success "✓ Token revogado com sucesso!"
        log_success "════════════════════════════════════════════════════════════════"
        return 0
    else
        log_error "Falha ao revogar token"
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

    log_info "Tentando fazer login no ArgoCD em: https://$ARGOCD_SERVER" >&2

    if argocd login "$ARGOCD_SERVER" \
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

    # OBTER SENHA ANTES
    local senha
    senha=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null) || senha=""

    if [ -n "$senha" ]; then
        log_info "Tentando fazer login no ArgoCD em: https://$ARGOCD_SERVER"

        # GUARDAR SAÍDA LIMPA
        local login_output
        login_output=$(argocd login "$ARGOCD_SERVER" \
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

# ============================================================================
# FAZER BACKUP ARGOCD (EXPORT)
# ============================================================================

backup_argocd() {
    local context=${1:-"kubernetes-admin@kubernetes"}

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Fazer Backup ArgoCD"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Validar namespace
    log_info "Validando namespace argocd..."
    if ! kubectl get namespace argocd 2>&1 >/dev/null; then
        log_error "Namespace argocd não encontrado"
        return 1
    fi

    log_success "Namespace encontrado"
    echo ""

    # 2. Gerar nome do backup
    local backup_file="${BACKUP_DIR}/argocd-backup-$(date +%Y%m%d-%H%M%S).yaml"
    mkdir -p "$BACKUP_DIR"

    log_info "Exportando configuração ArgoCD..."
    log_info "Arquivo: $backup_file"
    echo ""

    # 3. Fazer export
    if argocd admin export --namespace argocd --grpc-web > "$backup_file" 2>&1; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_success "✓ Backup criado com sucesso"
        log_info "Tamanho: $size"
        echo ""
        log_success "════════════════════════════════════════════════════════════════"
        log_info "Arquivo: $(basename "$backup_file")"
        log_info "Caminho completo: $backup_file"
        log_success "════════════════════════════════════════════════════════════════"
        return 0
    else
        log_error "Falha ao criar backup"
        return 1
    fi
}

# ============================================================================
# RESTAURAR BACKUP ARGOCD (IMPORT)
# ============================================================================

restore_argocd_backup() {
    local backup_file=${1:-""}
    local context=${2:-"kubernetes-admin@kubernetes"}

    if [ -z "$backup_file" ]; then
        log_error "Uso: restore_argocd_backup <backup_file> [context]"
        log_info "Exemplo: ./deploy-argocd.sh restore ./backups/argocd-backup-20251105.yaml"
        return 1
    fi

    if [ ! -f "$backup_file" ]; then
        log_error "Arquivo de backup não encontrado: $backup_file"
        return 1
    fi

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Restaurar ArgoCD do Backup"
    log_info "════════════════════════════════════════════════════════════════"

    kubectl config use-context "$context" || return 1

    # 1. Validar contexto
    log_info "Validando contexto..."
    if ! kubectl get namespace argocd 2>&1 >/dev/null; then
        log_error "Namespace argocd não encontrado"
        return 1
    fi

    log_success "Namespace argocd encontrado"
    echo ""

    # 2. Mostrar informações do backup
    log_info "Informações do backup:"
    log_info "Arquivo: $(basename "$backup_file")"
    log_info "Tamanho: $(du -h "$backup_file" | cut -f1)"
    echo ""

    # 3. Criar backup de segurança
    log_warning "⚠️  Criando backup preventivo antes da restauração..."
    local safety_backup="${BACKUP_DIR}/argocd-backup-before-restore-$(date +%Y%m%d-%H%M%S).yaml"

    if argocd admin export --namespace argocd --grpc-web > "$safety_backup" 2>&1; then
        log_success "Backup de segurança criado"
    fi
    echo ""

    # 4. Obter senha admin
    log_info "Obtendo credenciais de admin..."
    local admin_pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

    if [ -z "$admin_pass" ]; then
        log_error "Não foi possível obter senha do admin"
        return 1
    fi

    log_success "Credenciais obtidas"
    echo ""

    # 5. Fazer login
    log_info "Fazendo login como admin..."
    if ! argocd login "$ARGOCD_SERVER" \
        --username admin \
        --password "$admin_pass" \
        --insecure \
        --grpc-web 2>&1 >/dev/null; then
        log_error "Falha ao fazer login"
        return 1
    fi

    log_success "Login realizado"
    echo ""

    # 6. Restaurar do backup
    log_info "Restaurando configuração do backup..."

    if argocd admin import "$backup_file" --namespace argocd --grpc-web 2>&1 >/dev/null; then
        log_success "✓ Configuração restaurada com sucesso"
    else
        log_error "Falha ao restaurar do backup"
        return 1
    fi
    echo ""

    # 7. Reiniciar pods
    log_info "Reiniciando pods do ArgoCD..."
    kubectl rollout restart deployment/argocd-server -n argocd 2>&1 >/dev/null
    kubectl rollout status deployment/argocd-server -n argocd --timeout=5m 2>&1 >/dev/null

    log_success "Pods reiniciados"
    echo ""

    log_success "════════════════════════════════════════════════════════════════"
    log_success "✓ Restauração concluída!"
    log_success "════════════════════════════════════════════════════════════════"
    log_info "Backup de segurança: $safety_backup"
    log_success "════════════════════════════════════════════════════════════════"

    return 0
}

# ============================================================================
# LISTAR BACKUPS
# ============================================================================

list_backups() {
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Backups Disponíveis"
    log_info "════════════════════════════════════════════════════════════════"
    echo ""

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_warning "Nenhum backup encontrado em $BACKUP_DIR"
        return 0
    fi

    log_info "Diretório: $BACKUP_DIR"
    echo ""

    ls -lhSr "$BACKUP_DIR"/*.yaml 2>/dev/null | awk '{
        printf "  %-50s %10s\n", $9, $5
    }' || log_warning "Sem backups"

    echo ""
    log_success "════════════════════════════════════════════════════════════════"

    return 0
}

# ============================================================================
# DELETAR BACKUPS ANTIGOS
# ============================================================================

delete_old_backups() {
    local days=${1:-7}

    log_info "════════════════════════════════════════════════════════════════"
    log_info "Deletar Backups com mais de $days dias"
    log_info "════════════════════════════════════════════════════════════════"
    echo ""

    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "Diretório de backups não encontrado"
        return 0
    fi

    log_info "Procurando backups antigos..."

    local count=$(find "$BACKUP_DIR" -name "*.yaml" -mtime "+$days" 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ]; then
        log_info "Nenhum backup antigo encontrado"
        return 0
    fi

    log_warning "Encontrados $count backups para deletar"
    find "$BACKUP_DIR" -name "*.yaml" -mtime "+$days" -exec echo "  - {}" \;
    echo ""

    find "$BACKUP_DIR" -name "*.yaml" -mtime "+$days" -delete

    log_success "✓ Backups antigos deletados"

    return 0
}

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << 'HELP_EOF'

INSTALAÇÃO (2 comandos):
  install-main <contexto>             Instalar MAIN
  install-remote <contexto>           Instalar REMOTE


DESINSTALAÇÃO (2 comandos):
  uninstall-main <contexto>           Remover MAIN com backup
  uninstall-remote <contexto>         Remover REMOTE


GERENCIAMENTO DE CLUSTERS (2 comandos):
  register-cluster <remote> <nome>    Registrar cluster remoto (via Ingress)
  check-clusters [contexto]           Verificar status dos clusters


GERENCIAMENTO DE SENHAS (4 comandos):
  get-admin-password <contexto>       Obter senha admin
  show-credentials <contexto>         Mostrar credenciais (user, pass, URL)
  login-web <contexto>                Mostrar credenciais para acesso web
  login-cli <contexto>                Login via CLI (sem port-forward)


GERENCIAMENTO DE USUÁRIOS (3 comandos):
  create-user <user> <pass>           Criar novo usuário (role:developer)
  change-password <user> <pass>       Alterar senha do usuário
  list-users [contexto]               Listar usuários e roles


GERENCIAMENTO DE TOKENS (4 comandos):
  generate-token <user>               Gerar token permanente (CI/CD)
  generate-token <user> <segundos>    Gerar token com expiração
  list-tokens <user>                  Listar tokens do usuário
  revoke-token <user> <token-id>      Revogar token por ID


BACKUP E RESTORE (4 comandos):
  backup [contexto]                   Fazer backup da configuração
  list-backups                        Listar todos os backups
  restore <arquivo> [contexto]        Restaurar do backup (com segurança)
  delete-old-backups <dias>           Deletar backups com mais de N dias


DIAGNÓSTICO (4 comandos):
  check-status                        Verificar status completo
  check-ingress [contexto]            Verificar Ingress
  help                                Mostrar esta mensagem
  --help, -h                          Mostrar esta mensagem (alternativa)


EXEMPLOS DE USO:

  # Instalação inicial
  ./deploy-argocd.sh install-main kubernetes-admin@kubernetes
  ./deploy-argocd.sh install-remote kubernetes-admin@kubernetes

  # Gerenciamento de usuários
  ./deploy-argocd.sh create-user devuser pass@dev2025
  ./deploy-argocd.sh list-users

  # Gerar tokens para CI/CD
  ./deploy-argocd.sh generate-token devuser              # Permanente
  ./deploy-argocd.sh generate-token devuser 3600         # 1 hora
  ./deploy-argocd.sh list-tokens devuser

  # Backup e restore
  ./deploy-argocd.sh backup
  ./deploy-argocd.sh list-backups
  ./deploy-argocd.sh restore ./backups/argocd-backup-20251105-143022.yaml
  ./deploy-argocd.sh delete-old-backups 7

  # Diagnóstico
  ./deploy-argocd.sh check-status
  ./deploy-argocd.sh check-clusters
  ./deploy-argocd.sh show-credentials kubernetes-admin@kubernetes

  # Desinstalação
  ./deploy-argocd.sh uninstall-main kubernetes-admin@kubernetes

CONTEXTOS PADRÃO:
  kubernetes-admin@kubernetes         Cluster MAIN (C2)

LOGS E BACKUPS:
  Logs:       ./logs/deploy.log
  Backups:    ./backups/

REQUISITOS:
  • kubectl configurado com acesso aos clusters
  • Permissões de admin no cluster
  • Internet para download de manifestos

SUPORTE:
  Para mais informações: ./deploy-argocd.sh help

HELP_EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║ ::::  ArgoCD Deployment Automation v2.13.3  ::::             ║"
    echo "║ Versão: 1.0.0                                                ║"
    echo "║ GERENCIAMENTO AUTOMÁTICO DE CLUSTERS                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
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
            backup_argocd "${2:-kubernetes-admin@kubernetes}"
            ;;

        list-backups)
            list_backups
            ;;

        restore)
            if [ -z "$2" ]; then
                log_error "Uso: ./deploy-argocd.sh restore <backup_file> [context]"
                list_backups
                return 1
            fi
            restore_argocd_backup "$2" "${3:-kubernetes-admin@kubernetes}"
            ;;

        delete-old-backups)
            delete_old_backups "${2:-7}"
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

        create-user)
            create_argocd_user "${2:-}" "${3:-}" "${4:-kubernetes-admin@kubernetes}"
            ;;

        change-password)
            change_argocd_password "${2:-}" "${3:-}" "${4:-kubernetes-admin@kubernetes}"
            ;;

        list-users)
            list_argocd_users "${2:-kubernetes-admin@kubernetes}"
            ;;

        generate-token)
            generate_argocd_token "${2:-}" "${3:-}" "${4:-kubernetes-admin@kubernetes}"
            ;;

        list-tokens)
            list_argocd_tokens "${2:-}" "${3:-kubernetes-admin@kubernetes}"
            ;;

        revoke-token)
            if [ -z "$3" ]; then
                log_error "Uso: ./deploy-argocd.sh revoke-token <username> <token_id>"
                list_argocd_tokens "$2" "$3"
            else
                revoke_argocd_token "${2:-}" "${3:-}" "${4:-kubernetes-admin@kubernetes}"
            fi
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
