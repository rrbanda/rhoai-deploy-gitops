# Red Hat OpenShift AI — GitOps Deployment

<p align="center">
  <strong>Deploy a production-grade AI/ML platform on any OpenShift cluster with a single command.</strong><br>
  <em>Declarative. Reproducible. Self-healing. Fully managed through Git.</em>
</p>

<p align="center">
  <a href="https://rrbanda.github.io/rhoai-deploy-gitops/"><img src="https://img.shields.io/badge/Documentation-blue?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Docs"></a>
  <a href="https://github.com/rrbanda/rhoai-deploy-gitops/releases"><img src="https://img.shields.io/github/v/release/rrbanda/rhoai-deploy-gitops?include_prereleases&style=for-the-badge&label=Release" alt="Release"></a>
  <a href="https://github.com/rrbanda/rhoai-deploy-gitops/actions/workflows/validate.yml"><img src="https://img.shields.io/github/actions/workflow/status/rrbanda/rhoai-deploy-gitops/validate.yml?style=for-the-badge&label=CI" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-green?style=for-the-badge" alt="License"></a>
</p>

---

## Deploy in 1 Command

**Prerequisites:** OpenShift 4.18+ with cluster-admin access.

```bash
# Fork this repo → edit bootstrap/overlays/default/cluster-config.yaml → push

until oc apply -k bootstrap/overlays/default; do sleep 10; done
```

**That's it.** This single command:

1. Installs the OpenShift GitOps operator
2. Configures ArgoCD with production-grade settings
3. Creates ApplicationSets that auto-discover all platform components
4. Deploys 11+ operators, the DataScienceCluster, and GPU infrastructure
5. Sets up self-management — ArgoCD manages itself from Git going forward

The platform converges in 15–30 minutes. From this point, every change goes through Git.

---

## How It Works

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  1. You edit ONE file:                                                   │
│     bootstrap/overlays/default/cluster-config.yaml                       │
│                                                                          │
│       repoURL: https://github.com/YOUR-ORG/rhoai-deploy-gitops.git      │
│       targetRevision: main                                               │
│                                                                          │
│  2. You run ONE command:                                                 │
│     until oc apply -k bootstrap/overlays/default; do sleep 10; done      │
│                                                                          │
│  3. ArgoCD takes over:                                                   │
│     ┌──────────────────────────────────────────────────────────────┐     │
│     │  Discovers operators, instances, workloads from Git          │     │
│     │  Installs them in dependency order (sync waves)              │     │
│     │  Self-heals drift — reverts manual changes automatically     │     │
│     │  Manages its own configuration from Git                      │     │
│     └──────────────────────────────────────────────────────────────┘     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Fork & Clone

```bash
# Fork on GitHub, then:
git clone https://github.com/YOUR-ORG/rhoai-deploy-gitops.git
cd rhoai-deploy-gitops
```

### 2. Configure (edit one file)

```bash
vi bootstrap/overlays/default/cluster-config.yaml
```

```yaml
data:
  repoURL: "https://github.com/YOUR-ORG/rhoai-deploy-gitops.git"
  targetRevision: "main"
  rhoaiChannel: "fast"       # fast = latest GA, beta = EA/preview, stable = LTS
  rhoaiOverlay: "full"       # minimal | serving | training | full | maas
```

### 3. Push & Deploy

```bash
git add -A && git commit -m "Configure for my cluster" && git push

# Bootstrap — the until loop handles CRD timing (operator not ready yet)
until oc apply -k bootstrap/overlays/default; do sleep 10; done
```

### 4. (Optional) Enable models and services

Models and services are **opt-in** — the platform deploys but workloads don't until you enable them:

```bash
./scripts/configure.sh enable-model gemma2-9b-fp8
./scripts/configure.sh enable-service llm-d-epp
git add -A && git commit -m "Enable gemma2 and EPP" && git push
```

---

## Repository Structure

This repo follows the [community-standard OpenShift GitOps pattern](https://github.com/gnunn-gitops/standards/blob/master/folders.md) established by gnunn-gitops, christianh814, and Red Hat AI Services.

```
rhoai-deploy-gitops/
├── bootstrap/                              # ← ENTRY POINT
│   ├── base/                              # OpenShift GitOps operator install
│   │   ├── kustomization.yaml             #   (references redhat-cop/gitops-catalog)
│   │   └── argocd-rbac.yaml              #   cluster-admin for ArgoCD SA
│   └── overlays/
│       └── default/                       # THE SINGLE ENTRY POINT
│           ├── kustomization.yaml         #   Aggregates everything + replacements
│           ├── argocd-instance.yaml       #   ArgoCD CR (Kustomize + Helm enabled)
│           ├── cluster-config.yaml        #   ← THE ONLY FILE YOU EDIT
│           └── gitops-controller.yaml     #   Self-management Application
│
├── components/
│   ├── argocd/
│   │   ├── applicationsets/               # Auto-discovery engines
│   │   │   ├── cluster-operators-appset.yaml
│   │   │   ├── cluster-instances-appset.yaml
│   │   │   ├── cluster-models-appset.yaml
│   │   │   └── cluster-services-appset.yaml
│   │   ├── projects/                      # RBAC boundaries (platform, usecases)
│   │   └── apps/                          # Standalone Applications (DSC)
│   ├── operators/                         # Platform operators (auto-discovered)
│   │   ├── rhoai-operator/
│   │   ├── kueue-operator/
│   │   ├── cert-manager/
│   │   └── ...
│   └── instances/                         # Platform instances (auto-discovered)
│       ├── rhoai-instance/
│       │   └── overlays/                  # full | serving | training | minimal
│       ├── kueue-config/
│       └── ...
│
├── usecases/                              # Opt-in workloads (not deployed by default)
│   ├── models/                            # Model serving configs
│   │   └── gemma2-9b-fp8/
│   │       └── profiles/tier1-minimal/
│   │           └── config.json            # "enabled": "true" to deploy
│   └── services/                          # Platform services
│       └── llm-d-epp/
│           └── profiles/tier1-minimal/
│               └── config.json
│
├── scripts/
│   └── configure.sh                       # Optional CLI helper
└── docs/                                  # MkDocs documentation site
```

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **One file to configure** | `cluster-config.yaml` drives all ArgoCD resources via Kustomize replacements |
| **One command to deploy** | `oc apply -k bootstrap/overlays/default` — nothing else needed |
| **Auto-discovery** | Add an operator directory → ArgoCD creates the Application automatically |
| **Opt-in workloads** | Models/services use `config.json` markers with ArgoCD post-selectors |
| **Self-managing** | `gitops-controller` Application makes ArgoCD manage its own config from Git |
| **Portable** | No hardcoded cluster IDs or URLs — works on any OpenShift 4.18+ cluster |
| **Self-healing** | Every Application has `selfHeal: true` — manual drift is reverted |
| **Community standard** | Follows gnunn-gitops/christianh814 folder structure and patterns |

---

## What Gets Deployed

| Layer | Components | Auto-deploy? |
|-------|-----------|:------------:|
| **Operators** | cert-manager, NFD, GPU Operator, Kueue, JobSet, LWS, CMA, ServiceMesh, AI Gateway, RHCL, RHOAI | ✅ Always |
| **Instances** | DSC, Kueue config, GPU instance, NFD instance | ✅ Always |
| **Models** | gemma2-9b-fp8, qwen25-7b, orchestrator-8b, gpt-oss-120b, qwen-math-7b | ❌ Opt-in |
| **Services** | AI Gateway, LlamaStack, llm-d EPP, Guardrails, GenAI Toolbox, RHOKP, ToolOrchestra | ❌ Opt-in |

### DataScienceCluster Profiles

| Profile | Enables | Use Case |
|---------|---------|----------|
| `minimal` | Dashboard only | Platform exploration |
| `serving` | Dashboard + KServe + Model Registry | Model inference |
| `training` | Dashboard + Ray + Training Operator | Distributed training |
| **`full`** | **All 12+ components** | **Complete AI platform** |

---

## Multi-Cluster Support

For multiple clusters, create additional bootstrap overlays:

```bash
# Option A: Use the configure script
./scripts/configure.sh --repo <url> --overlay prod --new-overlay --dsc serving --channel fast

# Option B: Manually copy
cp -r bootstrap/overlays/default bootstrap/overlays/prod
vi bootstrap/overlays/prod/cluster-config.yaml
```

Then deploy each cluster to its respective overlay:

```bash
until oc apply -k bootstrap/overlays/prod; do sleep 10; done
```

---

## Version Support

This repo tracks the latest RHOAI release by default (`fast` channel). Switch channels in `cluster-config.yaml` to target a specific release stream:

| Channel | What It Tracks | Use Case |
|---------|---------------|----------|
| `fast` | Latest GA release | **Default** — production deployments |
| `beta` | Early Access / preview | Testing upcoming features |
| `stable` | Long Term Support | Conservative / regulated environments |

| OpenShift | Status |
|-----------|--------|
| 4.18+ | Supported |

---

## Documentation

**Full documentation with concepts, guides, and references:**

**[rrbanda.github.io/rhoai-deploy-gitops](https://rrbanda.github.io/rhoai-deploy-gitops/)**

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test with `oc kustomize bootstrap/overlays/default` to verify output
4. Submit a pull request

---

## License

Apache License 2.0 — See [LICENSE](LICENSE) for details.
