<h1 align="center">
  🚀 OpenShift AI — GitOps Deployment
</h1>

<p align="center">
  <strong>Production-ready Kustomize manifests for deploying Red Hat OpenShift AI on any OpenShift cluster using ArgoCD (GitOps) or manual apply.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg" alt="License"></a>
  <a href="https://rrbanda.github.io/rhoai-deploy-gitops/"><img src="https://img.shields.io/badge/docs-GitHub_Pages-blue" alt="Docs"></a>
  <a href="https://github.com/rrbanda/rhoai-deploy-gitops/releases"><img src="https://img.shields.io/github/v/release/rrbanda/rhoai-deploy-gitops?include_prereleases&label=release" alt="Release"></a>
  <a href="https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5"><img src="https://img.shields.io/badge/RHOAI-3.5-red" alt="RHOAI"></a>
  <a href="https://docs.openshift.com/"><img src="https://img.shields.io/badge/OpenShift-4.18+_-red" alt="OpenShift"></a>
</p>

<p align="center">
  <a href="#-quick-start-5-minutes">Quick Start</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-capabilities">Capabilities</a> •
  <a href="#-version-support">Version Support</a> •
  <a href="docs/">Documentation</a> •
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

---

## What is this?

This repository provides a **complete, declarative, GitOps-driven deployment** of [Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai) (RHOAI) — the enterprise AI/ML platform built on OpenShift.

**One fork. One config edit. Full AI platform.**

```
┌─────────────────────────────────────────────────────────────────┐
│  You edit ONE file:  clusters/overlays/dev/cluster-config.yaml  │
│                                                                  │
│  repoURL: "https://github.com/YOU/rhoai-deploy-gitops.git"     │
│  targetRevision: "main"                                          │
│  rhoaiChannel: "beta"                                            │
│  rhoaiOverlay: "full"                                            │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              ArgoCD auto-syncs everything:                        │
│  ✓ 12+ operators (RHOAI, GPU, Kueue, Service Mesh, ...)        │
│  ✓ DataScienceCluster with all components                        │
│  ✓ GPU scheduling & quotas (Kueue + Hardware Profiles)          │
│  ✓ Model serving (KServe, vLLM, NIM)                            │
│  ✓ Distributed training (Ray, PyTorch, DeepSpeed)               │
│  ✓ Models-as-a-Service (MaaS) with governance                   │
│  ✓ AI Gateway for inference routing                              │
│  ✓ MLflow experiment tracking                                    │
│  ✓ TrustyAI for evaluation & guardrails                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start (5 minutes)

### Prerequisites

| Requirement | Details |
|-------------|---------|
| OpenShift cluster | 4.18+ with cluster-admin access |
| Worker nodes | 2+ nodes with 8 CPU / 32 GiB RAM minimum |
| Storage | Default StorageClass with dynamic provisioning |
| GPU nodes | Optional — for model serving and training |
| Tools | `oc` CLI, `git` |

### Step 1: Fork & Configure

```bash
# Fork this repo on GitHub, then clone your fork
git clone https://github.com/YOUR_ORG/rhoai-deploy-gitops.git
cd rhoai-deploy-gitops

# Configure for your fork (updates one file)
./setup.sh --repo https://github.com/YOUR_ORG/rhoai-deploy-gitops.git

# Commit and push
git add -A && git commit -m "Configure for my cluster" && git push
```

### Step 2: Bootstrap ArgoCD

```bash
# Install OpenShift GitOps (ArgoCD) if not already present
oc apply -k bootstrap/

# Wait for ArgoCD to be ready
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
```

### Step 3: Deploy

```bash
# Apply your cluster overlay — ArgoCD takes over from here
oc apply -k clusters/overlays/dev/

# Watch the magic happen
watch oc get applications.argoproj.io -n openshift-gitops
```

That's it. ArgoCD will install all operators, create instances, deploy the DataScienceCluster, and keep everything in sync with your Git repository.

### Step 4: Verify

```bash
# Check RHOAI is fully ready (all conditions True)
oc get datasciencecluster default-dsc \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.status}{"\n"}{end}'
```

---

## 🏗️ Architecture

```
rhoai-deploy-gitops/
│
├── bootstrap/                          # OpenShift GitOps operator install
│
├── clusters/                           # Per-cluster configuration
│   ├── base/                           # Shared: includes ArgoCD apps
│   └── overlays/
│       ├── dev/                        # Development cluster config
│       │   ├── cluster-config.yaml     # ← THE ONE FILE YOU EDIT
│       │   ├── kustomization.yaml      # Wires config into all apps
│       │   └── bootstrap-app.yaml      # Self-managing bootstrap
│       └── prod/                       # Production (create with setup.sh)
│
├── components/
│   ├── argocd/                         # ArgoCD ApplicationSets
│   │   ├── apps/                       # Auto-discovers operators & instances
│   │   └── projects/                   # ArgoCD project definitions
│   │
│   ├── operators/                      # OLM subscriptions (one dir per operator)
│   │   ├── rhoai-operator/            # Red Hat OpenShift AI
│   │   ├── kueue-operator/            # GPU scheduling & quotas
│   │   ├── servicemesh/               # Service Mesh (Istio)
│   │   ├── cma-operator/             # Custom Metrics Autoscaler (KEDA)
│   │   ├── lws/                       # LeaderWorkerSet
│   │   ├── rhcl/                      # Red Hat Connectivity Link (Kuadrant)
│   │   └── ...                         # cert-manager, NFD, GPU, etc.
│   │
│   └── instances/                      # Operator instance CRs
│       ├── rhoai-instance/            # DataScienceCluster (DSC)
│       │   ├── base/                   # Common DSC configuration
│       │   └── overlays/              # Composable capability sets
│       │       ├── minimal/            # Dashboard only
│       │       ├── serving/            # + KServe model serving
│       │       ├── training/           # + Ray, Training Operator
│       │       └── full/               # Everything enabled
│       ├── kueue-config/              # GPU quotas & scheduling
│       ├── hardware-profiles/         # GPU/CPU compute profiles
│       ├── dashboard-config/          # RHOAI dashboard features
│       ├── maas-gateway/             # Models-as-a-Service gateway
│       └── ...
│
├── usecases/                           # Reference deployments
│   ├── models/                         # LLM model deployments
│   └── services/                       # AI services (LlamaStack, etc.)
│
├── setup.sh                            # One-command configuration
├── CHANGELOG.md                        # Release history
└── UPGRADING.md                        # Version upgrade guide
```

### How It Works

```mermaid
graph LR
    A[You push to Git] --> B[ArgoCD detects change]
    B --> C[ApplicationSets generate apps]
    C --> D[Operators installed via OLM]
    D --> E[Instances created]
    E --> F[DSC reconciles components]
    F --> G[Platform ready]
```

1. **You** edit `cluster-config.yaml` and push
2. **ArgoCD** detects the change and syncs
3. **ApplicationSets** auto-discover new operators/instances from directory structure
4. **OLM** installs the operators
5. **RHOAI Operator** reconciles the DataScienceCluster
6. **Done** — all AI/ML capabilities are live

---

## 🎛️ Capabilities

### DSC Overlays — Deploy What You Need

| Overlay | What's Included | Use When |
|---------|----------------|----------|
| `minimal` | Dashboard | Exploring the UI |
| `serving` | Dashboard + KServe + Model Registry | Deploying models |
| `training` | Dashboard + Ray + Training Operator | Training models |
| `full` | **All components** (recommended) | Production AI platform |
| `dev` | Same as full + dev settings | Development/testing |

### Component Matrix

| Component | Description | Overlay |
|-----------|-------------|---------|
| Dashboard | Web UI for managing AI workloads | All |
| KServe | Model serving (vLLM, NIM, custom) | serving, full |
| Model Cache | Pre-pull models to GPU nodes | full |
| Models-as-a-Service | Centralized LLM governance | full |
| AI Gateway | Inference routing + batch inference | full |
| Ray | Distributed computing framework | training, full |
| Training Operator | PyTorch/DeepSpeed distributed training | training, full |
| Kueue | GPU quota management & fair-share scheduling | full |
| Pipelines | Data Science Pipelines (Argo Workflows) | full |
| Model Registry | Model versioning & lineage | serving, full |
| MLflow | Experiment tracking | full |
| TrustyAI | Model evaluation & guardrails | full |
| OGX | Orchestration extensions | full |
| Workbenches | Jupyter notebooks | All |

---

## 📋 Version Support

| Release | RHOAI Version | OCP Version | Branch/Tag | Status |
|---------|--------------|-------------|------------|--------|
| v3.5.0-ea2 | 3.5 EA2 | 4.18+ | `main` / `v3.5.0-ea2` | **Current** |
| v3.4.0 | 3.4 GA | 4.17–4.20 | `archive/v3.4.0` | Archived |

### Upgrading Between Versions

See [UPGRADING.md](UPGRADING.md) for detailed upgrade instructions.

**Quick version:** Change `rhoaiChannel` in your `cluster-config.yaml` and push.

---

## 🔧 Customization

### Change the RHOAI version

Edit `clusters/overlays/<env>/cluster-config.yaml`:
```yaml
data:
  rhoaiChannel: "fast"   # Change from "beta" to "fast" for GA releases
```

### Change which components are deployed

```bash
./setup.sh --repo <your-url> --dsc serving  # Only model serving
./setup.sh --repo <your-url> --dsc full     # Everything
```

### Add GPU nodes

See [`components/instances/gpu-workers/README.md`](components/instances/gpu-workers/README.md) for cloud-specific GPU MachineSet examples.

### Add custom operators

Create a new directory under `components/operators/my-operator/` with a `kustomization.yaml` and `subscription.yaml`. The ApplicationSet will auto-discover it on next sync.

### Pin to a specific release

```bash
./setup.sh --repo <your-url> --branch v3.5.0-ea2
```

---

## 🛡️ Security

- **Pre-commit hooks** — [gitleaks](https://github.com/gitleaks/gitleaks) scans every commit
- **No real secrets in Git** — all Secret YAMLs use placeholder values
- **`.gitignore`** blocks `*.pem`, `*.key`, `*.env`, `kubeconfig`
- See [SECURITY.md](SECURITY.md) for responsible disclosure

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick ways to contribute:**
- Add GPU MachineSet examples for Azure/GCP/bare-metal
- Add new model deployment use cases
- Improve documentation
- Report bugs or suggest features

---

## 📚 References

- [RHOAI 3.5 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5)
- [OpenShift GitOps (ArgoCD)](https://docs.openshift.com/gitops/latest/understanding_openshift_gitops/about-redhat-openshift-gitops.html)
- [Kueue Documentation](https://kueue.sigs.k8s.io/)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) — Kustomize bases for operators

---

## ⭐ Star History

If this repo helps you deploy OpenShift AI, consider giving it a star! It helps others discover it.

---

## License

[Apache License 2.0](LICENSE)
