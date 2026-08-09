# Red Hat OpenShift AI — GitOps Deployment

Production-grade, GitOps-driven deployment of [Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai) on any OpenShift 4.19+ cluster. One configuration file, one command, fully self-healing.

[![CI](https://github.com/rrbanda/rhoai-deploy-gitops/actions/workflows/validate.yml/badge.svg)](https://github.com/rrbanda/rhoai-deploy-gitops/actions/workflows/validate.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## Overview

This repository implements the [app-of-apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) using ArgoCD ApplicationSets to deploy and manage the complete RHOAI stack — 12 operators (10 auto-deployed via ApplicationSet; NFD and GPU Operator deploy via instance CRs), GPU infrastructure, model serving, distributed training, and AI services — entirely through Git.

**Key properties:**

- **Single entry point** — edit `cluster-config.yaml`, run one `oc apply`, everything else is automatic
- **Auto-discovery** — add a directory under `components/operators/` or `usecases/models/`, push, and ArgoCD creates the Application
- **Self-healing** — every Application uses `selfHeal: true`; manual cluster drift is reverted automatically
- **Self-managing** — ArgoCD manages its own configuration from Git after bootstrap
- **Composable profiles** — choose `minimal`, `serving`, `training`, `full`, `maas`, or `dev` DataScienceCluster profiles via Kustomize overlays
- **Opt-in workloads** — models and services are disabled by default; enable via `config.json` flags

## Quick Start

### 1. Fork and configure

```bash
git clone https://github.com/<YOUR-ORG>/rhoai-deploy-gitops.git
cd rhoai-deploy-gitops

./scripts/configure.sh \
  --repo https://github.com/<YOUR-ORG>/rhoai-deploy-gitops.git \
  --channel fast \
  --dsc full

git add -A && git commit -m "Configure for my cluster" && git push
```

### 2. Bootstrap

```bash
until oc apply -k bootstrap/overlays/default; do sleep 10; done
```

This installs the OpenShift GitOps operator, configures ArgoCD, and deploys four ApplicationSets that auto-discover all platform components. The `until` loop handles CRD timing — the operator needs a few seconds before its resources are accepted.

The platform converges in 15–30 minutes. **This is the only `oc apply` you will ever run.** From here, Git is your interface.

### 3. Enable models and services (optional)

Models and services are opt-in. Enable them by setting `"enabled": "true"` in their `config.json`:

```bash
./scripts/configure.sh enable-model gemma2-9b-fp8
./scripts/configure.sh enable-service llm-d-epp
git add -A && git commit -m "Enable gemma2 and EPP" && git push
```

### 4. Verify

```bash
# Watch ArgoCD Applications converge
watch oc get applications.argoproj.io -n openshift-gitops

# Confirm DSC is ready
oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

## Prerequisites

| Requirement | Details |
|---|---|
| OpenShift | 4.19+ with cluster-admin access |
| Worker nodes | 2+ nodes, 8 CPU / 32 GiB each (minimum) |
| Storage | Default StorageClass with dynamic provisioning |
| GPU | NVIDIA GPU nodes for inference/training workloads |
| Network | Access to `registry.redhat.io`, `quay.io`, `cdn.redhat.com` |
| CLI | `oc` authenticated as cluster-admin |

## Repository Structure

```
├── bootstrap/                          # Entry point
│   ├── base/                           # GitOps operator + RBAC
│   └── overlays/default/
│       ├── cluster-config.yaml         # ← The only file you edit
│       ├── argocd-instance.yaml        # ArgoCD CR with health checks
│       ├── kustomization.yaml          # Kustomize replacements
│       └── gitops-controller.yaml      # Self-management Application
│
├── components/
│   ├── argocd/                         # ApplicationSets, AppProjects, Apps
│   ├── operators/                      # OLM subscriptions (auto-discovered)
│   └── instances/                      # Operator CRs (auto-discovered)
│       └── rhoai-instance/overlays/    # DSC profiles: full|serving|training|minimal
│
├── usecases/
│   ├── models/                         # Model deployments (opt-in)
│   └── services/                       # AI services (opt-in)
│
├── scripts/configure.sh                # Configuration helper
└── docs/                               # Documentation (MkDocs)
```

## What Gets Deployed

### Platform (always deployed)

| Category | Components |
|---|---|
| **Operators** | RHOAI, cert-manager, NFD, GPU Operator, Kueue, JobSet, LeaderWorkerSet, CMA, ServiceMesh, RHCL, External Secrets |
| **Instances** | DataScienceCluster, GPU ClusterPolicy, NFD discovery, Kueue quotas |

### DataScienceCluster Profiles

| Profile | What it does | Use case |
|---|---|---|
| `minimal` | Dashboard only (all other components Removed) | Platform exploration |
| `serving` | Full platform minus training (removes ray, sparkoperator, trainer, trainingoperator, batchGateway) | Model inference |
| `training` | Full platform minus serving (removes aigateway, kserve, mlflowoperator, modelregistry, ogx) | Distributed training |
| **`full`** | **All components (no patches)** | **Complete AI platform (default)** |
| `maas` | Same as serving (removes training components) | Models-as-a-Service |
| `dev` | Same as full (no patches) | Development and testing |

### Models and Services (opt-in)

| Models | Services |
|---|---|
| gemma2-9b-fp8 | AI Gateway (Kuadrant) |
| qwen25-7b-instruct | Guardrails Gateway |
| qwen-math-7b | GenAI Toolbox |
| orchestrator-8b | LlamaStack |
| gpt-oss-120b (multi-GPU) | llm-d EPP, RHOKP, ToolOrchestra |

## Configuration

All configuration flows through a single ConfigMap:

```yaml
# bootstrap/overlays/default/cluster-config.yaml
data:
  repoURL: "https://github.com/<YOUR-ORG>/rhoai-deploy-gitops.git"
  targetRevision: "main"
  rhoaiChannel: "fast"       # fast = GA, beta = EA, stable = LTS
  rhoaiOverlay: "full"       # minimal | serving | training | full | maas | dev
```

Kustomize replacements inject these values into every ArgoCD Application and ApplicationSet at build time. See [docs/configuration.md](docs/configuration.md) for details.

## Version Support

| Channel | Release stream | Use case |
|---|---|---|
| `fast` | Latest GA release | **Default** — production deployments |
| `beta` | Early Access / preview | Testing upcoming features |
| `stable` | Long Term Support | Regulated environments |

## Multi-Cluster

Create additional bootstrap overlays per environment:

```bash
cp -r bootstrap/overlays/default bootstrap/overlays/prod
vi bootstrap/overlays/prod/cluster-config.yaml

until oc apply -k bootstrap/overlays/prod; do sleep 10; done
```

## Disconnected / Air-Gapped

For environments without internet access, mirror all images to a private registry first:

```bash
# List required images
./scripts/mirror-images.sh list

# Mirror to your registry
./scripts/mirror-images.sh mirror --target-registry myregistry.example.com:5000

# Configure and deploy
./scripts/configure.sh --repo <url> --overlay disconnected --new-overlay
until oc apply -k bootstrap/overlays/disconnected; do sleep 10; done
```

See [docs/disconnected.md](docs/disconnected.md) for the full guide.

## Documentation

- [Quick Start](docs/quickstart.md) — step-by-step deployment guide
- [Architecture](docs/architecture.md) — app-of-apps flow, dependency chain, design decisions
- [Configuration](docs/configuration.md) — replacements, overlays, opt-in pattern
- [Upgrading](docs/upgrading.md) — channel switching and version migration

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short:

1. Fork and clone
2. Install pre-commit hooks: `pip install pre-commit && pre-commit install`
3. Create a feature branch
4. Test with `oc kustomize bootstrap/overlays/default` to verify output
5. Submit a pull request

## License

[Apache License 2.0](LICENSE)
