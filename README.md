# Deploying OpenShift AI

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-GitHub_Pages-blue)](https://rrbanda.github.io/rhoai-deploy-gitops/)
[![RHOAI](https://img.shields.io/badge/RHOAI-3.4-red)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.19_|_4.20-red)](https://docs.openshift.com/)

Production-ready Kustomize manifests for deploying **Red Hat OpenShift AI 3.4** on OpenShift -- using ArgoCD (GitOps) or plain `oc apply -k` (manual).

Composable overlays let you deploy the full stack or pick individual capabilities (model serving, training, pipelines, workbenches) without modifying the base manifests.

> **Use cases (models, services, training workloads)** are in the companion repo: [rhoai-usecases](https://github.com/rrbanda/rhoai-usecases)

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
│   │   ├── servicemesh/
│   │   ├── nfd/
│   │   ├── gpu-operator/
│   │   ├── kueue-operator/
│   │   ├── jobset-operator/
│   │   ├── leader-worker-set/
│   │   ├── opentelemetry/
│   │   ├── tempo/
│   │   ├── cluster-observability-operator/
│   │   ├── custom-metrics-autoscaler/
│   │   ├── rhcl-operator/
│   │   └── rhoai-operator/
│   └── instances/                    # Operator instance CRs
│       ├── nfd-instance/
│       ├── gpu-instance/
│       ├── gpu-workers/              # GPU node provisioning (cloud-specific)
│       ├── cluster-autoscaler/
│       ├── kueue-instance/
│       ├── kueue-config/             # ResourceFlavors + ClusterQueue
│       ├── jobset-instance/
│       ├── dashboard-config/         # Enables GenAI Studio in RHOAI dashboard
│       ├── mcp-servers/              # Registers MCP servers in RHOAI dashboard
│       ├── mlflow-instance/          # MLflow tracking server instance
│       └── rhoai-instance/           # DSCInitialization + DataScienceCluster
│           ├── base/                 # DSCI + minimal DSC (Dashboard only)
│           └── overlays/             # dev, minimal, serving, training, full
├── setup.sh                          # Configure repo URL for your fork
└── UPGRADING.md                      # Version upgrade guide
```

## Prerequisites

- **OpenShift Container Platform 4.19 or 4.20** (other versions are not supported)
- **Minimum 2 worker nodes** with 8 CPUs and 32 GiB RAM each
- **Default storage class** with dynamic provisioning configured
- **Identity provider configured** -- `kubeadmin` is not sufficient for RHOAI
- `oc` CLI authenticated as cluster-admin
- **Open Data Hub must NOT be installed** on the same cluster
- **No upgrade path from RHOAI 2.x (as of 3.4)** -- 3.0 requires a fresh installation; upgrade support is planned for a later release

## Cluster Setup

After forking this repo, configure it for your cluster:

```bash
# 1. Point all ArgoCD apps at your fork
./setup.sh --repo https://github.com/YOURORG/rhoai-deploy-gitops.git

# 2. (AWS only) Edit GPU MachineSets with your cluster's infra ID, AMI, subnet, etc.
#    See components/instances/gpu-workers/README.md

# 3. Install pre-commit hooks for secret scanning
pip install pre-commit
pre-commit install
git config core.hooksPath .githooks
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
# Phase 1 -- Pre-RHOAI Operators (wait for all CSVs before proceeding)
oc apply -k components/operators/cert-manager/
oc apply -k components/operators/servicemesh/
oc apply -k components/operators/nfd/
oc apply -k components/operators/gpu-operator/
oc apply -k components/operators/kueue-operator/
oc apply -k components/operators/jobset-operator/
oc apply -k components/operators/leader-worker-set/
oc apply -k components/operators/opentelemetry/
oc apply -k components/operators/tempo/
oc apply -k components/operators/cluster-observability-operator/
oc apply -k components/operators/custom-metrics-autoscaler/
oc apply -k components/operators/rhcl-operator/
oc apply -k components/operators/rhoai-operator/

watch "oc get csv -A | grep -E 'cert-manager|servicemesh|nfd|gpu-operator|kueue|jobset|leader|opentelemetry|tempo|observability|autoscaler|rhcl|rhods'"

# Phase 2 -- Pre-DSC Instances (order matters)
oc apply -k components/instances/nfd-instance/
oc apply -k components/instances/gpu-instance/
oc apply -k components/instances/gpu-workers/examples/aws/  # Cloud-specific
oc apply -k components/instances/cluster-autoscaler/
oc apply -k components/instances/kueue-instance/
oc apply -k components/instances/kueue-config/
oc apply -k components/instances/jobset-instance/

# Phase 3 -- DSCInitialization + DataScienceCluster
oc apply -k components/instances/rhoai-instance/overlays/dev/
oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
  datasciencecluster/default-dsc --timeout=600s
oc apply -k components/instances/dashboard-config/
oc apply -k components/instances/mcp-servers/
```

For deploying models and services on top of the platform, see [rhoai-usecases](https://github.com/rrbanda/rhoai-usecases).

## Capabilities

Red Hat OpenShift AI is modular -- deploy only what you need.

| Capability | DSC Component | Guide |
|------------|---------------|-------|
| KServe Model Serving | `kserve` | [Model Serving](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/model-serving/) |
| Distributed Training | `ray`, `trainingoperator` | [Training](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/training/) |
| Data Science Pipelines | `aipipelines` | [Pipelines](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/pipelines/) |
| Workbenches | `workbenches` | [Workbenches](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/workbenches/) |
| Model Registry | `modelregistry` | [Model Registry](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/model-registry/) |
| MLflow | `mlflowoperator` | [MLflow](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/mlflow/) |
| GPU Infrastructure | N/A (operators) | [GPU Infrastructure](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/gpu-infrastructure/) |
| Kueue (GPU Quotas) | `kueue` (Unmanaged) | [Kueue](https://rrbanda.github.io/rhoai-deploy-gitops/capabilities/kueue/) |

### DSC Overlays

The base DataScienceCluster starts minimal (Dashboard only). Pick an overlay:

| Overlay | Components | Command |
|---------|-----------|---------|
| `minimal` | Dashboard | `oc apply -k components/instances/rhoai-instance/overlays/minimal/` |
| `serving` | Dashboard, KServe | `oc apply -k components/instances/rhoai-instance/overlays/serving/` |
| `training` | Dashboard, Ray, Training Operator | `oc apply -k components/instances/rhoai-instance/overlays/training/` |
| `full` | All DSC components | `oc apply -k components/instances/rhoai-instance/overlays/full/` |
| `dev` | All DSC components (default) | `oc apply -k components/instances/rhoai-instance/overlays/dev/` |

## Security

This repo includes secret leak prevention:

- **Pre-commit hooks** -- gitleaks scans every commit for credentials, tokens, and keys
- **Pre-push hook** -- secondary gitleaks scan before pushing to remote
- **`.gitignore`** -- blocks `*.pem`, `*.key`, `*.env`, `credentials.json`, `kubeconfig`
- **No real secrets in Git** -- all Secret YAMLs use `CHANGE_ME` placeholders

## References

- [RHOAI 3.4 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.4 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [rhoai-usecases](https://github.com/rrbanda/rhoai-usecases) -- Models, services, and training workloads
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
- [UPGRADING.md](UPGRADING.md) -- Guide for upgrading to future RHOAI versions
