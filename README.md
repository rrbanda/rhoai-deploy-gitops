# RHOAI Deploy GitOps

End-to-end GitOps deployment of **Red Hat OpenShift AI 3.3** and AI use cases on OpenShift.

This repository contains everything needed to install, configure, and manage an RHOAI platform and deploy AI applications on top of it -- using either ArgoCD (GitOps) or plain `oc apply -k` (manual).

## Architecture

```
rhoai-deploy-gitops/
├── bootstrap/              # OpenShift GitOps (ArgoCD) operator install
├── clusters/               # Per-cluster overlays (dev, prod, etc.)
├── components/
│   ├── argocd/             # ArgoCD projects and ApplicationSets
│   ├── operators/          # OLM operator subscriptions
│   │   ├── cert-manager/
│   │   ├── nfd/
│   │   ├── gpu-operator/
│   │   ├── kueue-operator/
│   │   ├── jobset-operator/
│   │   └── rhoai-operator/
│   └── instances/          # Operator instance CRs
│       ├── nfd-instance/
│       ├── gpu-instance/
│       ├── kueue-instance/
│       ├── jobset-instance/
│       └── rhoai-instance/ # DataScienceCluster (v2)
└── usecases/               # AI application deployments
    └── toolorchestra/      # NVIDIA ToolOrchestra multi-model orchestrator
```

## Prerequisites

- OpenShift Container Platform 4.19+
- `oc` CLI authenticated as cluster-admin
- GPU nodes available (NVIDIA L4, L40S, A100, or H100)

## Quick Start

### Option A: GitOps (ArgoCD)

```bash
# 1. Install OpenShift GitOps operator
oc apply -k bootstrap/

# 2. Wait for GitOps operator to be ready
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s

# 3. Apply cluster configuration (triggers ArgoCD to sync everything)
oc apply -k clusters/overlays/dev/
```

ArgoCD syncs in order via sync waves:
- **Wave 0-2:** Platform operators (cert-manager, NFD, GPU, Kueue, JobSet, RHOAI)
- **Wave 3-4:** Operator instances (NFD, GPU, Kueue, JobSet CRs, DataScienceCluster)
- **Wave 5:** Use cases (ToolOrchestra)

### Option B: Manual (no ArgoCD)

```bash
# 1. Install operators one at a time
oc apply -k components/operators/cert-manager/
oc apply -k components/operators/nfd/
oc apply -k components/operators/gpu-operator/
oc apply -k components/operators/kueue-operator/
oc apply -k components/operators/jobset-operator/
oc apply -k components/operators/rhoai-operator/

# 2. Wait for operators to install, then create instances
oc apply -k components/instances/nfd-instance/
oc apply -k components/instances/gpu-instance/
oc apply -k components/instances/kueue-instance/
oc apply -k components/instances/jobset-instance/
oc apply -k components/instances/rhoai-instance/overlays/dev/

# 3. Deploy a use case
oc apply -k usecases/toolorchestra/profiles/tier1-minimal/
```

## RHOAI 3.3 Specifics

This repo targets RHOAI 3.3 with these key settings:

| Setting | Value | Notes |
|---------|-------|-------|
| RHOAI channel | `fast-3.x` | Required for 3.x releases |
| DSC API | `datasciencecluster.opendatahub.io/v2` | New in 3.x |
| Kueue | `Unmanaged` in DSC | Red Hat Build of Kueue Operator manages it |
| JobSet | Standalone operator | Required for Trainer v2 |
| Trainer v2 | `Managed` in DSC | New unified TrainJob API |
| Training Operator v1 | `Managed` (deprecated) | Still available, removal planned |

## Adding a New Use Case

1. Create a new directory under `usecases/`:
   ```
   usecases/my-app/
     manifests/
       base/
         kustomization.yaml
         namespace.yaml
         ...
       serving/
         my-model/
       services/
         my-service/
     profiles/
       default/
         kustomization.yaml    # References ../manifests/base + serving + services
   ```

2. Each profile directory is a Kustomize target. ArgoCD auto-discovers it via the `cluster-usecases-appset` ApplicationSet, or deploy manually with `oc apply -k usecases/my-app/profiles/default/`.

## References

- [RHOAI 3.3 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
- [rh-aiservices-bu/rhoaibu-cluster](https://github.com/rh-aiservices-bu/rhoaibu-cluster) -- Reference GitOps architecture
