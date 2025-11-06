# ArgoCD Deployment Automation

[![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.13.3-blue?style=flat-square&logo=argo)](https://argo-cd.readthedocs.io/) [![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue?style=flat-square&logo=kubernetes)](https://kubernetes.io/) [![Bash](https://img.shields.io/badge/Bash-5.0+-green?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/) [![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

Automação para instalação, configuração e gerenciamento de ArgoCD em ambientes multi-cluster Kubernetes com suporte a deployments MAIN + REMOTE via Ingress HTTPS.

![ArgoCD](https://argo-cd.readthedocs.io/en/stable/assets/argocd_architecture.png)

## 📋 Índice

- [Sobre](#sobre)
- [Requisitos](#requisitos)
- [Arquitetura](#arquitetura)
- [Instalação](#instalação)
- [Uso](#uso)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Fluxo de Trabalho](#fluxo-de-trabalho)
- [Troubleshooting](#troubleshooting)
- [Contribuição](#contribuição)

## 🎯 Sobre

Script automatizado para gerenciamento completo de **ArgoCD v2.13.3** em ambientes multi-cluster Kubernetes:

-  ✓  **Instalação automática** com 5 etapas em cluster MAIN
-  ✓  **Configuração de cluster remoto** com 3 etapas
-  ✓  **Ingress HTTPS** automático via `argocd.domain.com.br`
-  ✓  **Login automático** sem port-forward
-  ✓  **Registro de clusters** com validação bidirecional
-  ✓  **Backup automático** antes de desinstalar
-  ✓  **Logs estruturados** em tempo real
-  ✓  **GitOps distribuído** pronto para produção

## 📦 Requisitos

### Obrigatório

- **kubectl** ≥ 1.24
- **ArgoCD CLI** v2.13.3 (instalado automaticamente)
- **Dois clusters Kubernetes** com RBAC ativado
- **Kubeconfig** com 2 contextos:
  - `kubernetes-admin@kubernetes` (MAIN - Cluster2)
  - `kubernetes-admin@kubernetes` (REMOTE - Cluster1)

### Opcional

- **Ingress Controller** (nginx ou HAProxy) - para acesso via HTTPS
- **Cert-Manager** (certificados TLS automáticos)
- **DNS** configurado para `argocd.domain.com.br`

### Permissões Necessárias

```sh
# Verificar permissões de admin

kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-server -n argocd
kubectl auth can-i create secrets --as=system:serviceaccount:argocd:argocd-server -n argocd
```

## 🏗️ Arquitetura

```

┌─────────────────────────────────────────────────────────────┐
│                    CLUSTER MAIN (Cluster2)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │           ArgoCD Server (v2.13.3)                     │  │
│  │  -  redis                                             │  │
│  │  -  repo-server                                       │  │
│  │  -  application-controller                            │  │
│  │  -  server (UI + API gRPC)                            │  │
│  └───────────────────────────────────────────────────────┘  │
│                            ↓                                │
│                    [Ingress HTTPS]                          │
│              argocd.domain.com.br:443                       │
└─────────────────────────────────────────────────────────────┘
↓
┌─────────────────────────────────────────────────────────────┐
│                  CLUSTER REMOTE (Cluster1)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │     ArgoCD Components (Agent)                         │  │
│  │  -  ServiceAccount: argocd-manager                    │  │
│  │  -  ClusterRole: argocd-manager                       │  │
│  │  -  application-controller                            │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│    Registrado como: cluster-c1                              │
│    Status: Gerenciado pelo MAIN                             │
└─────────────────────────────────────────────────────────────┘

```

## 🚀 Instalação

### 1. Clonar Repositório

```sh
git clone https://github.com/erivandosena/argocd-gitops.git
cd argocd-deployment
chmod +x deploy-argocd.sh
```

### 2. Preparar Kubeconfig

```sh
# Verificar contextos disponíveis

kubectl config get-contexts

# Esperado:

# CURRENT   NAME                          CLUSTER      AUTHINFO             NAMESPACE

# *         kubernetes-admin@kubernetes   kubernetes   kubernetes-admin

# kubernetes-admin@kubernetes   cluster-c1   kubernetes-admin
```

### 3. Instalar ArgoCD no MAIN (Cluster2)

```sh
# Instalação completa com 5 etapas

./deploy-argocd.sh install-main kubernetes-admin@kubernetes

# Saída esperada:

# [INFO] === Etapa 1/5: Application CRD ===

# [SUCCESS] CRD pronta

# [INFO] === Etapa 2/5: Namespace ===

# ...

# [SUCCESS] ArgoCD instalado com sucesso no MAIN
```

### 4. Instalar Componentes no REMOTE (Cluster1)

```sh
# Instalação com 3 etapas

./deploy-argocd.sh install-remote kubernetes-admin@kubernetes

# Saída esperada:

# [INFO] === Etapa 1/3: Application CRD ===

# [INFO] === Etapa 2/3: Cluster Access (Manager) ===

# [INFO] === Etapa 3/3: Remote Access (Controller) ===

# [SUCCESS] Componentes instalados no REMOTO
```

### 5. Registrar Cluster Remoto

```sh
# Registrar Cluster1 no ArgoCD de Cluster2

./deploy-argocd.sh register-cluster kubernetes-admin@kubernetes cluster-c1

# Saída esperada:

# [INFO] Registrando cluster remoto...

# [SUCCESS] Login realizado com sucesso

# [SUCCESS] Cluster 'cluster-c1' registrado com sucesso
```

## 📖 Uso

### Comandos Disponíveis

#### Instalação do zero

```bash
# 1. Instalar MAIN
./deploy-argocd.sh install-main kubernetes-admin@kubernetes # (nome do contexto do K8S)

# 2. Instalar REMOTE
./deploy-argocd.sh install-remote kubernetes-admin@kubernetes

# 3. Ver credenciais
./deploy-argocd.sh show-credentials kubernetes-admin@kubernetes

# 4. Login CLI
./deploy-argocd.sh login-cli kubernetes-admin@kubernetes

# 5. Registrar cluster remoto
./deploy-argocd.sh register-cluster kubernetes-admin@kubernetes cluster-c1 # (cluster K8S remoto)

# 6. Verificar status
./deploy-argocd.sh check-status
```

#### Gerenciamento de usuários e tokens

```bash
# 1. Criar usuário developer
./deploy-argocd.sh create-user devuser Pass@2025! # (Senha do User)

# 2. Listar usuários
./deploy-argocd.sh list-users kubernetes-admin@kubernetes

# 3. Gerar token permanente (para CI/CD)
./deploy-argocd.sh generate-token devuser

# 4. Gerar token com validade (1 hora)
./deploy-argocd.sh generate-token devuser 3600

# 5. Listar tokens do usuário
./deploy-argocd.sh list-tokens devuser

# 6. Alterar senha
./deploy-argocd.sh change-password devuser NewPass@2025^~
```

#### Backup e recuperação (DR
```bash
# 1. Fazer backup regular
./deploy-argocd.sh backup

# 2. Listar todos os backups
./deploy-argocd.sh list-backups

# 3. Restaurar do backup mais recente
./deploy-argocd.sh restore ./backups/argocd-backup-20251105-143022.yaml

# 4. Restaurar com contexto específico
./deploy-argocd.sh restore ./backups/argocd-backup-20251105-143022.yaml kubernetes-admin@kubernetes

# 5. Limpar backups com mais de 7 dias
./deploy-argocd.sh delete-old-backups 7

# 6. Limpar backups com mais de 30 dias
./deploy-argocd.sh delete-old-backups 30
```

#### Verificação e diagnóstico:

```bash
# 1. Verificar status completo
./deploy-argocd.sh check-status

# 2. Verificar clusters
./deploy-argocd.sh check-clusters kubernetes-admin@kubernetes

# 3. Verificar Ingress
./deploy-argocd.sh check-ingress kubernetes-admin@kubernetes

# 4. Obter senha admin
./deploy-argocd.sh get-admin-password kubernetes-admin@kubernetes

# 5. Fazer backup
./deploy-argocd.sh backup
```

### Exemplo Completo de Deploy

```sh
# 1. Instalar MAIN

bash deploy-argocd.sh install-main kubernetes-admin@kubernetes

# 2. Instalar REMOTE

bash deploy-argocd.sh install-remote kubernetes-admin@kubernetes

# 3. Registrar REMOTE no MAIN

bash deploy-argocd.sh register-cluster kubernetes-admin@kubernetes cluster-c1

# 4. Ver credenciais

bash deploy-argocd.sh show-credentials kubernetes-admin@kubernetes

# 5. Fazer login web

bash deploy-argocd.sh login-web kubernetes-admin@kubernetes

# 6. Verificar status

bash deploy-argocd.sh check-status
```

## 📁 Estrutura do Projeto

```bash
argocd-deployment/
├── README.md                                  \# Este arquivo
├── deploy-argocd.sh                           \# Script principal (v1.0.0)
├── .gitignore                                 \# Arquivos ignorados
│
├── k8s-main/                                  \# Manifests para MAIN (Cluster2)
│   ├── 0-namespace.yaml                       \# Namespace argocd
│   ├── 1-application-crd-v2.13.3.yaml         \# CRD Application
│   ├── 2-install-argocd-v2.13.3.yaml          \# ArgoCD Server
│   ├── 3-core-install-v2.13.3.yaml            \# Core components
│   ├── 4-gitlab-runner-role.yaml              \# RBAC GitLab Runner
│   └── 5-install-optional-k8s-onpremises.yaml \# Ingress + TLS
│
├── k8s-remotes/                               \# Manifests para REMOTE (Cluster1)
│   ├── 0-application-crd-v2.13.3.yaml         \# CRD Application
│   ├── 1-argocd-cluster-access.yaml           \# ServiceAccount
│   └── 2-argocd-remote-cluster-access.yaml    \# ClusterRole
│
├── logs/
│   └── deploy.log                             \# Log estruturado de deployments
│
└── backups/
└── argocd-backup-*.yaml                       \# Backups automáticos
```

### Descrição dos Manifests

| Arquivo | Propósito | Cluster |
|------|-----------|---------|
| `0-namespace.yaml` | Criar namespace `argocd` | MAIN |
| `1-application-crd-v2.13.3.yaml` | Instalar CRD Application (GitOps) | MAIN/REMOTE |
| `2-install-argocd-v2.13.3.yaml` | Deployment ArgoCD Server | MAIN |
| `3-core-install-v2.13.3.yaml` | Core components (redis, repo-server) | MAIN |
| `4-gitlab-runner-role.yaml` | RBAC para integração GitLab | MAIN |
| `5-install-optional-k8s-onpremises.yaml` | Ingress HTTPS + TLS | MAIN |
| `1-argocd-cluster-access.yaml` | ServiceAccount para cluster remoto | REMOTE |
| `2-argocd-remote-cluster-access.yaml` | ClusterRole para gerenciamento | REMOTE |

## 🔄 Fluxo de Trabalho

### Etapa 1: Preparação

```sh
# Verificar kubeconfig

kubectl config get-contexts

# Validar acesso aos clusters

kubectl --context=kubernetes-admin@kubernetes get nodes
kubectl --context=kubernetes-admin@kubernetes get nodes
```

### Etapa 2: Instalação MAIN

```shell

┌───────────────────────────────────────────┐
│ Pré-requisitos: namespace, CRD, RBAC      │
└───────────────────────────────────────────┘
↓
┌───────────────────────────────────────────┐
│ 1. Application CRD (v2.13.3)              │
│    CRD para Application GitOps            │
└───────────────────────────────────────────┘
↓
┌───────────────────────────────────────────┐
│ 2. Namespace (argocd)                     │
│    Isolamento de namespace                │
└───────────────────────────────────────────┘
↓
┌───────────────────────────────────────────┐
│ 3. ArgoCD Server                          │
│    Deployment (replicas: 2)               │
│    Service (port 443, 8080)               │
│    ServiceAccount \& RBAC                 │
└───────────────────────────────────────────┘
↓
┌───────────────────────────────────────────┐
│ 4. Core Components                        │
│    Redis (cache)                          │
│    Repo Server (git sync)                 │
│    Application Controller                 │
│    Notification Controller                │
└───────────────────────────────────────────┘
↓
┌───────────────────────────────────────────┐
│ 5. Ingress HTTPS                          │
│    Ingress (argocd.domain.com.br)         │
│    TLS (self-signed ou cert-manager)      │
│    GitLab Runner (opcional)               │
└───────────────────────────────────────────┘

```

### Etapa 3: Registro de Clusters

```shell

┌──────────────────────────────────────────────────┐
│ Cluster MAIN (Cluster2)                          │
│                                                  │
│ 1. Obter credenciais de REMOTE                   │
│ 2. Criar secret em MAIN com kubeconfig de REMOTE │
│ 3. Registrar cluster como "cluster-c1"           │
│ 4. Validar conectividade bidirecional            │
└──────────────────────────────────────────────────┘
↓
┌────────────────────────────┐
│ Cluster REMOTE (Cluster1)  │
│                            │
│ Autorizado para            │
│   sincronização            │
│ Pronto para apps           │
└────────────────────────────┘

```

## 🔐 Acesso

### Via Ingress HTTPS

```sh
# 1. Obter credenciais

./deploy-argocd.sh show-credentials kubernetes-admin@kubernetes

# Saída:

# Usuário: admin

# Senha: j4Yulo6G75oGKZHy

# URL: https://argocd.domain.com.br

# 2. Abrir no navegador

# https://argocd.domain.com.br

# 3. Login com:

# Usuário: admin

# Senha: <conforme acima>
```

### Via CLI

```sh
# 1. Login automático

./deploy-argocd.sh login-cli kubernetes-admin@kubernetes

# 2. Listar aplicações

argocd app list --grpc-web

# 3. Listar clusters

argocd cluster list --grpc-web

# 4. Obter status

argocd app get <app-name> --grpc-web
```

## 🐛 Troubleshooting

### Problema: Login falha com "Invalid username or password"

**Solução:**

```sh
# 1. Verificar se ArgoCD está pronto

./deploy-argocd.sh check-status | grep "Pods"

# 2. Obter nova senha

./deploy-argocd.sh get-admin-password kubernetes-admin@kubernetes

# 3. Fazer login

./deploy-argocd.sh login-cli kubernetes-admin@kubernetes
```

### Problema: Clusters não aparecem após registro

**Solução:**

```sh
# 1. Verificar clusters via kubectl

kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster

# 2. Verificar logs de erro

kubectl logs -n argocd deployment/argocd-server -f

# 3. Re-registrar cluster

./deploy-argocd.sh register-cluster kubernetes-admin@kubernetes cluster-c1 kubernetes-admin@kubernetes
```

### Problema: Ingress não funciona (certificado inválido)

**Solução:**

```sh
# 1. Verificar Ingress

kubectl get ingress -n argocd -o wide

# 2. Verificar certificado TLS

kubectl describe certificate -n argocd argocd-tls

# 3. Usar flag --insecure temporariamente

argocd login argocd.domain.com.br --insecure --grpc-web
```

### Problema: Sem acesso ao contexto REMOTE

**Solução:**

```sh
# 1. Validar kubeconfig

cat ~/.kube/config

# 2. Testar acesso

kubectl --context=kubernetes-admin@kubernetes get nodes

# 3. Adicionar contexto se necessário

kubectl config set-context kubernetes-admin@kubernetes \
--cluster=cluster-c1 \
--user=kubernetes-admin
```

## 📊 Informações de Versão

- **ArgoCD**: v2.13.3
- **Kubernetes**: ≥ 1.24
- **Script**: v1.0.0
- **Data Release**: 2025-11-04

### Changelog

#### v1.0.0 (2025-11-04)
-  ✓  Suporte automático a Ingress HTTPS
-  ✓  Login via CLI sem port-forward
-  ✓  Detecção automática de URL Ingress
-  ✓  Registro de clusters com DNS interno
-  ✓  Logs estruturados com stderr/stdout
-  ✓  Instalação MAIN (5 etapas)
-  ✓  Instalação REMOTE (3 etapas)
-  ✓  Registro de clusters automático

## 🤝 Contribuição

Contribuições são bem-vindas! Por favor:

1. **Fork** o repositório
2. **Crie uma branch** para sua feature (`git checkout -b feature/minha-feature`)
3. **Commit** suas mudanças (`git commit -am 'Adicionar nova feature'`)
4. **Push** para a branch (`git push origin feature/minha-feature`)
5. **Abra um Pull Request**

### Guidelines

- Manter compatibilidade com Bash 5.0+
- Adicionar logs estruturados
- Preservar padrões existentes
- Testar em ambos clusters (MAIN e REMOTE)

## 📝 Licença

Este projeto está licenciado sob a **MIT License** - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 📧 Suporte

Para suporte, abra uma [Issue](../../issues) ou envie um email para: `erivandosena@gmail.com`

## 🔗 Referências

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [GitOps](https://www.gitops.tech/)
- [Ingress Kubernetes](https://kubernetes.io/docs/concepts/services-networking/ingress/)

---

*⭐ Se este projeto foi útil, deixe uma star!*
