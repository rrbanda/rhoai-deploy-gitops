# Deploying OpenShift AI

Production-ready Kustomize manifests for deploying **Red Hat OpenShift AI 3.3** and AI use cases on OpenShift -- using ArgoCD (GitOps) or plain `oc apply -k` (manual).

Composable overlays let you deploy the full stack or pick individual capabilities (model serving, training, pipelines, workbenches) without modifying the base manifests.

> **Full documentation:** [rrbanda.github.io/rhoai-deploy-gitops](https://rrbanda.github.io/rhoai-deploy-gitops/)

## Architecture

```
rhoai-deploy-gitops/
├── bootstrap/                        # OpenShift GitOps (ArgoCD) operator install
├── clusters/                         # Per-cluster overlays (dev, prod, etc.)
│   ├── base/                         # Common: AppSets + ArgoCD projects
│   └── overlays/dev/
├── components/
│   ├── argocd/                       # ArgoCD projects and ApplicationSets
│   ├── operators/                    # OLM operator subscriptions
│   │   ├── cert-manager/
│   │   ├── nfd/
│   │   ├── gpu-operator/
│   │   ├── kueue-operator/
│   │   ├── jobset-operator/
│   │   └── rhoai-operator/
│   └── instances/                    # Operator instance CRs
│       ├── nfd-instance/
│       ├── gpu-instance/
│       ├── gpu-workers/              # GPU node provisioning (cloud-specific, see examples/)
│       ├── cluster-autoscaler/
│       ├── kueue-instance/
│       ├── kueue-config/             # ResourceFlavors + ClusterQueue
│       ├── jobset-instance/
│       └── rhoai-instance/           # DataScienceCluster with composable overlays
│           ├── base/                 # Minimal DSC (Dashboard only)
│           └── overlays/             # dev, minimal, serving, training, full
├── usecases/
│   ├── models/                       # Model serving catalog (per-model GitOps)
│   │   ├── gpt-oss-120b/
│   │   ├── orchestrator-8b/
│   │   └── qwen-math-7b/
│   └── services/                     # Supporting services
│       ├── genai-toolbox/
│       ├── llamastack/
│       └── toolorchestra-app/
└── setup.sh                          # Configure repo URL for your fork
```

## Prerequisites

- **OpenShift Container Platform 4.19 or 4.20** (other versions are not supported)
- **Minimum 2 worker nodes** with 8 CPUs and 32 GiB RAM each
- **Default storage class** with dynamic provisioning configured
- **Identity provider configured** -- `kubeadmin` is not sufficient for RHOAI
- `oc` CLI authenticated as cluster-admin
- **Open Data Hub must NOT be installed** on the same cluster
- **No upgrade path from RHOAI 2.x (as of 3.3)** -- 3.0 requires a fresh installation; upgrade support is planned for a later release
- GPU nodes available (any NVIDIA GPU supported by the GPU Operator) for model serving and training
- At least 50Gi storage per model in the GPU node availability zone

## Cluster Setup

After forking this repo, configure it for your cluster:

```bash
# 1. Point all ArgoCD apps at your fork
./setup.sh --repo https://github.com/YOURORG/rhoai-deploy-gitops.git

# 2. (AWS only) Edit GPU MachineSets with your cluster's infra ID, AMI, subnet, etc.
#    See components/instances/gpu-workers/README.md

# 3. Update secrets (pg-secret.yaml, etc.) for your environment
```

## Quick Start

### Option A: GitOps (ArgoCD)

```bash
oc apply -k bootstrap/
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
oc apply -k clusters/overlays/dev/
watch oc get application.argoproj.io -n openshift-gitops
```

After the second `oc apply`, the `cluster-bootstrap` app-of-apps takes over. Any future changes pushed to Git are auto-synced.

### Option B: Manual (no ArgoCD)

```bash
# 1. Install operators
oc apply -k components/operators/cert-manager/
oc apply -k components/operators/nfd/
oc apply -k components/operators/gpu-operator/
oc apply -k components/operators/kueue-operator/
oc apply -k components/operators/jobset-operator/
oc apply -k components/operators/rhoai-operator/

# 2. Create instances (order matters)
oc apply -k components/instances/nfd-instance/
oc apply -k components/instances/gpu-instance/
oc apply -k components/instances/kueue-instance/
oc apply -k components/instances/kueue-config/
oc apply -k components/instances/jobset-instance/
oc apply -k components/instances/rhoai-instance/overlays/dev/

# 3. Deploy a model
oc apply -k usecases/models/gpt-oss-120b/profiles/tier1-minimal/
```

See the [Quick Start Guide](https://rrbanda.github.io/rhoai-deploy-gitops/quickstart/) for detailed instructions with wait commands and verification steps.

## Capabilities

Red Hat OpenShift AI is modular -- deploy only what you need. Each capability has its own guide with dependencies, deployment steps, and examples.

| Capability | DSC Component | Guide |
|------------|---------------|-------|
| KServe Model Serving | `kserve` | [Model Serving](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/model-serving/) |
| ModelMesh Serving | `modelmeshserving` | [ModelMesh](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/modelmesh/) |
| Distributed Training | `ray`, `trainingoperator` | [Training](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/training/) |
| Data Science Pipelines | `datasciencepipelines` | [Pipelines](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/pipelines/) |
| Workbenches | `workbenches` | [Workbenches](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/workbenches/) |
| Model Registry | `modelregistry` | [Model Registry](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/model-registry/) |
| GPU Infrastructure | N/A (operators) | [GPU Infrastructure](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/gpu-infrastructure/) |
| Kueue (GPU Quotas) | `kueue` (Unmanaged) | [Kueue](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/kueue/) |

See the [Capabilities Guide](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/) for the full dependency map, composable DSC overlays, and instructions for building a custom profile.

### DSC Overlays

The base DataScienceCluster starts minimal (Dashboard only). Pick an overlay:

| Overlay | Components | Command |
|---------|-----------|---------|
| `minimal` | Dashboard | `oc apply -k components/instances/rhoai-instance/overlays/minimal/` |
| `serving` | Dashboard, KServe, ModelMesh | `oc apply -k components/instances/rhoai-instance/overlays/serving/` |
| `training` | Dashboard, Ray, Training Operator | `oc apply -k components/instances/rhoai-instance/overlays/training/` |
| `full` | All 10 DSC components | `oc apply -k components/instances/rhoai-instance/overlays/full/` |
| `dev` | All 10 DSC components (default) | `oc apply -k components/instances/rhoai-instance/overlays/dev/` |

## Models and Services

Models are independently deployable via the `cluster-models` ApplicationSet. Services are discovered by the `cluster-services` ApplicationSet. See [usecases/README.md](usecases/README.md) for the full catalog.

| Category | Name | Description |
|----------|------|-------------|
| Model | **gpt-oss-120b** | OpenAI GPT-OSS 120B MoE (MXFP4 quantized, Red Hat AI validated) |
| Model | **orchestrator-8b** | NVIDIA Nemotron-Orchestrator-8B for multi-tool coordination |
| Model | **qwen-math-7b** | Qwen2.5-Math-7B-Instruct math specialist |
| Service | **genai-toolbox** | MCP Toolbox for Databases (PostgreSQL) |
| Service | **llamastack** | Meta LlamaStack Distribution with agents, RAG, and tool use |
| Service | **toolorchestra-app** | ToolOrchestra UI for multi-model orchestration |

## Documentation

The full documentation site covers:

- [Architecture and GitOps Patterns](https://rrbanda.github.io/rhoai-deploy-gitops/architecture/) -- app-of-apps, ApplicationSets, dependency chain
- [Quick Start Guide](https://rrbanda.github.io/rhoai-deploy-gitops/quickstart/) -- GitOps and manual deployment paths
- [Capabilities Guide](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/) -- per-capability deployment with composable DSC overlays
- [ArgoCD Applications](https://rrbanda.github.io/rhoai-deploy-gitops/reference/argocd-apps/) -- all 18 managed applications
- [Sync Configuration](https://rrbanda.github.io/rhoai-deploy-gitops/reference/sync-config/) -- production-grade ArgoCD settings
- [Teardown](https://rrbanda.github.io/rhoai-deploy-gitops/reference/teardown/) -- complete removal procedure
- [Known Issues](https://rrbanda.github.io/rhoai-deploy-gitops/reference/known-issues/) -- gotchas and workarounds

## References

- [RHOAI 3.3 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
- [ToolOrchestra Paper](https://arxiv.org/abs/2503.02495) -- NVIDIA's multi-model orchestration approach
- [verl Framework](https://github.com/volcengine/verl) -- Reinforcement learning training framework
