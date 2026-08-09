# OpenShift AI — GitOps Deployment

<p align="center">
  <strong>Deploy a production-grade AI/ML platform on any OpenShift cluster using two commands.</strong><br>
  <em>Declarative. Reproducible. Self-healing. Fully managed through Git.</em>
</p>

<p align="center">
  <a href="https://rrbanda.github.io/rhoai-deploy-gitops/"><img src="https://img.shields.io/badge/Documentation-blue?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Docs"></a>
  <a href="https://github.com/rrbanda/rhoai-deploy-gitops/releases"><img src="https://img.shields.io/github/v/release/rrbanda/rhoai-deploy-gitops?include_prereleases&style=for-the-badge&label=Release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-green?style=for-the-badge" alt="License"></a>
</p>

---

## The Challenge

Organizations deploying AI on Kubernetes face a recurring pattern:

- **Manual installs** that cannot be reproduced — every cluster becomes a snowflake
- **Configuration drift** — someone changes something, nobody knows what or when
- **GPU waste** — no governance over who uses expensive accelerators and how much
- **No audit trail** — compliance teams cannot verify what is deployed
- **Day-2 fragility** — upgrades and changes require heroics, not automation

## The Solution

This repository provides the entire Red Hat OpenShift AI (RHOAI) platform as **declarative Kustomize manifests**, managed by **ArgoCD**. You describe your desired state in Git. ArgoCD makes it real and keeps it that way.

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                       │
│   Git Repository (this repo)                                         │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  cluster-config.yaml   ←── THE ONLY FILE YOU EDIT           │   │
│   │                                                              │   │
│   │  repoURL: https://github.com/your-org/rhoai-deploy-gitops   │   │
│   │  targetRevision: main                                        │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                              │                                        │
│                              ▼                                        │
│   ArgoCD (self-managing, self-healing)                               │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  Discovers 11 operators, instances, workloads from Git      │   │
│   │  Installs them in dependency order                           │   │
│   │  Monitors for drift — reverts manual changes automatically  │   │
│   │  Retries on failure — converges within 15-30 minutes        │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                              │                                        │
│                              ▼                                        │
│   OpenShift Cluster                                                  │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  GPU Scheduling  │  Model Serving   │  Distributed Training │   │
│   │  Batch Inference │  AI Gateway      │  Workbenches          │   │
│   │  Model Registry  │  MLflow          │  Pipelines            │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

**The result:** A fully governed GPU-as-a-Service platform where teams get model serving, training capacity, and notebooks — all managed through Git with zero manual cluster access.

---

## Deploy in 2 Commands

**Prerequisites:** OpenShift 4.19+ cluster with cluster-admin access.

```bash
# 1. Fork this repo, clone your fork, and configure it
git clone https://github.com/YOUR-ORG/rhoai-deploy-gitops.git
cd rhoai-deploy-gitops
./setup.sh --repo https://github.com/YOUR-ORG/rhoai-deploy-gitops.git
git add -A && git commit -m "Configure for my cluster" && git push

# 2. Bootstrap (installs ArgoCD, then ArgoCD manages everything else)
oc apply -k bootstrap/
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
oc apply -k clusters/overlays/dev/
```

**That's it.** ArgoCD discovers all operators, instances, and workloads from Git, installs them in dependency order, and self-heals any drift. The platform converges in 15-30 minutes.

From this point forward, every change goes through Git:
- Need a new model? Add a directory, push.
- Need to change GPU quotas? Edit `kueue-config/`, push.
- Need to scale down? Edit the DSC overlay, push.

No more `oc apply`. No more SSH. No more snowflakes.

---

## What Gets Deployed

| Layer | Components | Purpose |
|-------|-----------|---------|
| **Operators** | cert-manager, NFD, GPU Operator, Kueue, JobSet, LWS, CMA, ServiceMesh, AI Gateway, RHCL, RHOAI | Infrastructure foundations |
| **GPU Infrastructure** | Node detection, driver installation, quota management, auto-scaling | Make GPUs schedulable and governed |
| **AI Platform** | Dashboard, KServe, ModelMesh, Ray, Training Operator, Pipelines, Workbenches, Model Registry, MLflow, TrustyAI, OGX | Full AI/ML capabilities |
| **Advanced Inference** | Batch Gateway (llm-d), Distributed Inference, Hardware Profiles, AI Gateway | Enterprise model serving at scale |
| **Governance** | Models-as-a-Service, rate limiting, access control, usage tracking | Multi-tenant GPU sharing |

### Capability Profiles

Choose what to deploy. Each profile is a Kustomize overlay:

| Profile | Enables | Use Case |
|---------|---------|----------|
| `minimal` | Dashboard only | Exploring the platform |
| `serving` | Dashboard + KServe + Model Registry | Model inference |
| `training` | Dashboard + Ray + Training Operator | Distributed training |
| `maas` | Dashboard + KServe + AI Gateway + Batch | Models-as-a-Service |
| **`full`** | **All 12+ components** | **Complete AI platform** |

```bash
./setup.sh --repo <your-url> --overlay full
```

---

## Architecture

The repository implements an **app-of-apps pattern**: one ArgoCD Application bootstraps everything else through auto-discovery.

```
rhoai-deploy-gitops/
├── bootstrap/                     # Step 1: Install ArgoCD
├── clusters/
│   └── overlays/dev/
│       └── cluster-config.yaml    # Step 2: YOUR configuration
├── components/
│   ├── operators/                 # Auto-discovered by cluster-operators AppSet
│   │   ├── rhoai-operator/
│   │   ├── gpu-operator/
│   │   ├── kueue-operator/
│   │   └── ...                    # Add a directory = ArgoCD auto-deploys it
│   └── instances/                 # Auto-discovered by cluster-instances AppSet
│       ├── rhoai-instance/
│       │   └── overlays/          # Choose your profile here
│       ├── kueue-config/
│       └── ...
└── usecases/
    ├── models/                    # Auto-discovered by cluster-models AppSet
    └── services/                  # Auto-discovered by cluster-services AppSet
```

**Key design decisions:**

1. **Single configuration file** — `cluster-config.yaml` drives all ArgoCD apps via Kustomize replacements. No find-and-replace across dozens of files.
2. **Auto-discovery** — Add a new operator directory and push. ArgoCD creates the Application automatically. No manual ArgoCD configuration ever.
3. **Composable profiles** — The DataScienceCluster uses overlays. Stack capabilities like LEGO bricks without duplicating manifests.
4. **Portable** — No hardcoded cluster IDs, URLs, or registry paths. Fork it, configure it, deploy it on any OpenShift 4.19+ cluster.
5. **Self-healing** — Every Application has `selfHeal: true`. Manual changes are reverted. The cluster always converges to Git state.

---

## Documentation

**Full documentation with concepts, guides, and references:**

[**rrbanda.github.io/rhoai-deploy-gitops**](https://rrbanda.github.io/rhoai-deploy-gitops/)

The documentation site includes:

| Section | What You'll Learn |
|---------|------------------|
| **[Concepts](https://rrbanda.github.io/rhoai-deploy-gitops/concepts/)** | GitOps fundamentals, app-of-apps pattern, Kustomize, GPU scheduling, RHOAI architecture |
| **[Quick Start](https://rrbanda.github.io/rhoai-deploy-gitops/quickstart/)** | Step-by-step deployment with explanations of what happens at each stage |
| **[Capabilities](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/)** | Deep-dive on each AI/ML capability — how to enable, configure, and verify |
| **[Architecture](https://rrbanda.github.io/rhoai-deploy-gitops/architecture/)** | Repository structure, dependency chains, sync configuration |
| **[Troubleshooting](https://rrbanda.github.io/rhoai-deploy-gitops/reference/troubleshooting/)** | Common issues with root causes and resolution steps |

---

## Version Support

| RHOAI Version | OpenShift | Tag | Status |
|--------------|-----------|-----|--------|
| 3.5 EA2 | 4.19+ | `v3.5.0-ea2` / `main` | **Current** |
| 3.4 | 4.19+ | `archive/v3.4.0` | Archived |

Upgrading between versions: change `rhoaiChannel` in your config, push to Git, and ArgoCD handles the operator upgrade. See [UPGRADING.md](UPGRADING.md).

---

## Customization

| I want to... | Do this |
|-------------|---------|
| Deploy on my fork | `./setup.sh --repo <url>` |
| Change the RHOAI version | Edit `rhoaiChannel` in `cluster-config.yaml` |
| Deploy only model serving | `./setup.sh --overlay serving` |
| Add a new operator | Create `components/operators/my-op/` with a Subscription |
| Add a new model | Create `usecases/models/my-model/` with an InferenceService |
| Change GPU quotas | Edit `components/instances/kueue-config/cluster-queue.yaml` |
| Add GPU nodes | Copy example from `components/instances/gpu-workers/examples/` |
| Pin to a specific release | `./setup.sh --branch v3.5.0-ea2` |

---

## How It Compares

| Approach | Reproducible | Self-Healing | Audit Trail | Multi-Cluster | Upgrade Path |
|----------|:---:|:---:|:---:|:---:|:---:|
| Manual `oc apply` | No | No | No | No | Manual |
| Shell scripts | Partial | No | No | Manual | Fragile |
| Helm charts | Yes | No | Partial | Manual | Helm upgrade |
| **This repo (GitOps)** | **Yes** | **Yes** | **Yes** | **Yes** | **Git push** |

---

## Security

- No real secrets in Git — all Secret manifests use placeholder values
- Pre-commit scanning with [gitleaks](https://github.com/gitleaks/gitleaks) in CI
- `.gitignore` blocks `*.pem`, `*.key`, `*.env`, `kubeconfig`
- See [SECURITY.md](SECURITY.md) for vulnerability reporting

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**High-impact contributions:**
- GPU MachineSet examples for Azure, GCP, or bare-metal
- New model deployment use cases
- Documentation improvements
- Bug reports and feature requests

---

## References

- [RHOAI 3.5 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3-latest)
- [OpenShift GitOps](https://docs.openshift.com/gitops/latest/understanding_openshift_gitops/about-redhat-openshift-gitops.html)
- [Kueue Documentation](https://kueue.sigs.k8s.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog)

---

## License

[Apache License 2.0](LICENSE)
