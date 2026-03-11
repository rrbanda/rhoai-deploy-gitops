# RHOAI Deploy GitOps

End-to-end GitOps deployment of **Red Hat OpenShift AI 3.3** and AI use cases on OpenShift.

This repository contains everything needed to install, configure, and manage an RHOAI platform and deploy AI applications on top of it -- using either ArgoCD (GitOps) or plain `oc apply -k` (manual).

## Architecture

```
rhoai-deploy-gitops/
├── bootstrap/                        # OpenShift GitOps (ArgoCD) operator install
├── clusters/                         # Per-cluster overlays (dev, prod, etc.)
│   ├── base/                         # Common: AppSets + ArgoCD projects
│   └── overlays/dev/
│       ├── bootstrap-app.yaml        # Self-managing app-of-apps (auto-syncs this overlay)
│       ├── rhoai-instance-app.yaml   # DSC with ignoreDifferences
│       └── training-workloads-app.yaml  # Manual-sync training workloads
├── components/
│   ├── argocd/                       # ArgoCD projects and ApplicationSets
│   │   ├── apps/
│   │   │   ├── cluster-operators-appset.yaml    # Auto-discovers components/operators/*
│   │   │   ├── cluster-instances-appset.yaml    # Auto-discovers components/instances/*
│   │   │   └── cluster-usecases-appset.yaml     # Auto-discovers usecases/*/profiles/tier1-minimal
│   │   └── projects/
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
│       ├── gpu-workers/              # GPU MachineSets (L4, L40S) + MachineAutoscalers
│       ├── cluster-autoscaler/       # ClusterAutoscaler for GPU node auto-scaling
│       ├── kueue-instance/
│       ├── kueue-config/             # ResourceFlavors (gpu-l4, gpu-l40s) + ClusterQueue
│       ├── jobset-instance/
│       └── rhoai-instance/           # DataScienceCluster (v1) with composable overlays
│           ├── base/                # Minimal DSC (Dashboard only)
│           └── overlays/
│               ├── dev/             # All components (default for ArgoCD)
│               ├── minimal/         # Dashboard only
│               ├── serving/         # KServe + ModelMesh
│               ├── training/        # Ray + Training Operator
│               └── full/            # All components
└── usecases/
    └── toolorchestra/                # NVIDIA ToolOrchestra multi-model orchestrator
        ├── manifests/
        │   ├── base/                 # Namespace, RBAC, ConfigMaps, NetworkPolicy
        │   ├── serving/
        │   │   ├── orchestrator/     # Nemotron-Orchestrator-8B (ServingRuntime, InferenceService, download Job)
        │   │   ├── qwen-math-7b/     # Qwen2.5-Math-7B-Instruct
        │   │   └── qwen3-32b/        # Qwen3-32B (for larger clusters)
        │   ├── services/ui/          # Orchestrator web UI
        │   └── training/
        │       ├── infra/            # LocalQueue, PVC, training ConfigMap (always deployed)
        │       └── workloads/        # Download jobs + RayJob (on-demand via manual sync)
        └── profiles/
            ├── tier1-minimal/        # 2 models + UI + training infra (auto-synced)
            ├── tier2-standard/       # Extended config
            ├── tier3-full/           # All models
            └── training/             # Serving + training (standalone kustomize target)
```

## Prerequisites

- OpenShift Container Platform 4.19+
- `oc` CLI authenticated as cluster-admin
- GPU nodes available (NVIDIA L4, L40S, A100, or H100)
- At least 50Gi storage per model in the GPU node availability zone

## Quick Start

### Option A: GitOps (ArgoCD)

```bash
# 1. Install OpenShift GitOps operator (Red Hat, not community ArgoCD)
oc apply -k bootstrap/

# 2. Wait for GitOps operator to be ready
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s

# 3. Bootstrap the cluster (one-time manual apply, self-manages after this)
oc apply -k clusters/overlays/dev/

# 4. Monitor convergence (~15-30 min for full stack)
watch oc get application.argoproj.io -n openshift-gitops
```

After step 3, the `cluster-bootstrap` app-of-apps takes over. Any future changes
pushed to Git (new Applications, updated manifests) are auto-synced -- no further
`oc apply` needed.

### Option B: Manual (no ArgoCD)

```bash
# 1. Install operators (wait for each CSV to reach Succeeded before proceeding)
oc apply -k components/operators/cert-manager/
oc apply -k components/operators/nfd/
oc apply -k components/operators/gpu-operator/
oc apply -k components/operators/kueue-operator/
oc apply -k components/operators/jobset-operator/
oc apply -k components/operators/rhoai-operator/

# Verify all operator CSVs are Succeeded
oc get csv -A | grep -E "cert-manager|nfd|gpu-operator|kueue|jobset|rhods"

# 2. Create operator instances (order matters)
oc apply -k components/instances/nfd-instance/    # NFD first (GPU depends on it)
# Wait: oc wait --for=jsonpath='{.status.conditions[0].type}'=Available \
#   nodefeaturediscovery/nfd-instance -n openshift-nfd --timeout=300s
oc apply -k components/instances/gpu-instance/
# Wait: oc wait --for=jsonpath='{.status.state}'=ready clusterpolicy/gpu-cluster-policy --timeout=600s
oc apply -k components/instances/kueue-instance/
oc apply -k components/instances/kueue-config/    # GPU ResourceFlavors + ClusterQueue
oc apply -k components/instances/jobset-instance/
oc apply -k components/instances/rhoai-instance/overlays/dev/
# Wait: oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
#   datasciencecluster/default-dsc --timeout=600s

# 3. Deploy a use case
oc apply -k usecases/toolorchestra/profiles/tier1-minimal/

# 4. Wait for models to download and become Ready
oc wait --for=condition=Ready inferenceservice/orchestrator-8b \
  -n orchestrator-rhoai --timeout=1800s
oc wait --for=condition=Ready inferenceservice/qwen-math-7b \
  -n orchestrator-rhoai --timeout=1800s
```

## Capabilities

RHOAI is modular -- you don't have to deploy everything. Each capability has its
own guide with dependencies, deployment steps, and examples.

| Capability | DSC Component | Guide |
|------------|---------------|-------|
| KServe Model Serving | `kserve` | [model-serving.md](docs/capabilities/model-serving.md) |
| ModelMesh Serving | `modelmeshserving` | [modelmesh.md](docs/capabilities/modelmesh.md) |
| Distributed Training | `ray`, `trainingoperator` | [training.md](docs/capabilities/training.md) |
| Data Science Pipelines | `datasciencepipelines` | [pipelines.md](docs/capabilities/pipelines.md) |
| Workbenches | `workbenches` | [workbenches.md](docs/capabilities/workbenches.md) |
| Model Registry | `modelregistry` | [model-registry.md](docs/capabilities/model-registry.md) |
| GPU Infrastructure | N/A (operators) | [gpu-infrastructure.md](docs/capabilities/gpu-infrastructure.md) |
| Kueue (GPU Quotas) | `kueue` (Unmanaged) | [kueue.md](docs/capabilities/kueue.md) |

See the [Capabilities Guide](docs/capabilities/README.md) for the full
dependency map, composable DSC overlays, and instructions for building a
custom profile.

### DSC Overlays

The base DSC starts minimal (Dashboard only). Pick an overlay for your needs:

| Overlay | Components | Command |
|---------|-----------|---------|
| `minimal` | Dashboard | `oc apply -k components/instances/rhoai-instance/overlays/minimal/` |
| `serving` | Dashboard, KServe, ModelMesh | `oc apply -k components/instances/rhoai-instance/overlays/serving/` |
| `training` | Dashboard, Ray, Training Operator | `oc apply -k components/instances/rhoai-instance/overlays/training/` |
| `full` | All components | `oc apply -k components/instances/rhoai-instance/overlays/full/` |
| `dev` | All components (default) | `oc apply -k components/instances/rhoai-instance/overlays/dev/` |

You can also compose overlays by stacking JSON patches from the capability
overlays. See [Composing a Custom Profile](docs/capabilities/README.md#composing-a-custom-profile).

## ArgoCD Applications

After bootstrap, ArgoCD manages **17 Applications** across three layers:

| Application | Source | Sync Policy | Purpose |
|-------------|--------|-------------|---------|
| `cluster-bootstrap` | `clusters/overlays/dev/` | Auto (selfHeal) | Self-manages the dev overlay: AppSets, explicit Apps |
| `operator-cert-manager` | `components/operators/cert-manager/` | Auto (selfHeal) | cert-manager operator subscription |
| `operator-nfd` | `components/operators/nfd/` | Auto (selfHeal) | Node Feature Discovery operator |
| `operator-gpu-operator` | `components/operators/gpu-operator/` | Auto (selfHeal) | NVIDIA GPU Operator |
| `operator-kueue-operator` | `components/operators/kueue-operator/` | Auto (selfHeal) | Red Hat Build of Kueue |
| `operator-jobset-operator` | `components/operators/jobset-operator/` | Auto (selfHeal) | JobSet Operator |
| `operator-rhoai-operator` | `components/operators/rhoai-operator/` | Auto (selfHeal) | Red Hat OpenShift AI operator |
| `instance-nfd-instance` | `components/instances/nfd-instance/` | Auto (selfHeal) | NFD NodeFeatureDiscovery CR |
| `instance-gpu-instance` | `components/instances/gpu-instance/` | Auto (selfHeal) | GPU ClusterPolicy CR |
| `instance-kueue-instance` | `components/instances/kueue-instance/` | Auto (selfHeal) | Kueue operator instance |
| `instance-gpu-workers` | `components/instances/gpu-workers/` | Auto (selfHeal) | GPU MachineSets (L4, L40S) + MachineAutoscalers |
| `instance-cluster-autoscaler` | `components/instances/cluster-autoscaler/` | Auto (selfHeal) | ClusterAutoscaler for GPU node auto-scaling |
| `instance-kueue-config` | `components/instances/kueue-config/` | Auto (selfHeal) | GPU ResourceFlavors + ClusterQueue |
| `instance-jobset-instance` | `components/instances/jobset-instance/` | Auto (selfHeal) | JobSet operator instance |
| `instance-rhoai` | `components/instances/rhoai-instance/overlays/dev/` | Auto (selfHeal, no prune) | DataScienceCluster with ignoreDifferences |
| `usecase-toolorchestra` | `usecases/toolorchestra/profiles/tier1-minimal/` | Auto (selfHeal, prune) | Serving (2 models), UI, training infra |
| `usecase-toolorchestra-training` | `usecases/toolorchestra/manifests/training/workloads/` | **Manual only** | Download jobs + RayJob (on-demand) |

### Sync Wave Ordering

Within the `usecase-toolorchestra` app, sync waves ensure correct resource ordering:

| Wave | Resources | Purpose |
|------|-----------|---------|
| -1 (default) | Namespace, RBAC, ConfigMaps, PVCs, ServingRuntimes, Service, Route, NetworkPolicy, LocalQueue | Infrastructure created first |
| 0 | `download-orchestrator-8b`, `download-qwen-math-7b` Jobs | Model download jobs run and complete before predictors start |
| 1 | `orchestrator-8b`, `qwen-math-7b` InferenceServices | Predictors created only after models are downloaded to PVCs |

Download jobs are idempotent (check for `.download_complete` marker) and have no TTL,
so completed jobs persist as Synced/Healthy in ArgoCD without being recreated.

## GPU Worker Node Scaling

GPU worker nodes are fully GitOps-managed. Scaling is handled two ways:

### Manual Scaling via Git

Change the `replicas` field in the MachineSet YAML and push:

```bash
# Example: scale L4 GPU nodes from 3 to 5
# Edit components/instances/gpu-workers/gpu-machineset-l4.yaml
#   spec.replicas: 5
git commit -am "Scale L4 GPU workers to 5" && git push
# ArgoCD auto-syncs → MachineSet updated → new nodes provisioned
```

### Auto-scaling

The ClusterAutoscaler and MachineAutoscalers are deployed via GitOps:

| Resource | Config | Effect |
|----------|--------|--------|
| ClusterAutoscaler | max 20 nodes, max 8 GPUs | Cluster-wide scaling limits |
| MachineAutoscaler (L4) | min: 1, max: 6 | Auto-scales `g6.2xlarge` nodes |
| MachineAutoscaler (L40S) | min: 0, max: 4 | Auto-scales `g6e.2xlarge` nodes |

When a pod requests `nvidia.com/gpu` and no capacity is available, the ClusterAutoscaler
automatically adds GPU nodes. Idle nodes are removed after 10 minutes.

### Customizing for Your Cluster

The GPU MachineSet manifests contain cluster-specific values (AMI ID, infra ID, subnet
names, security groups, IAM profile). When deploying to a new cluster, update these
fields in `components/instances/gpu-workers/gpu-machineset-*.yaml`:

- `metadata.name` and all `ocp-2qkbk` references → your cluster's infra ID
- `spec.template.spec.providerSpec.value.ami.id` → your cluster's RHCOS AMI
- `spec.template.spec.providerSpec.value.iamInstanceProfile.id` → your IAM profile
- `subnet`, `securityGroups`, `tags` → your cluster's networking config

## Training Pipeline

The repository includes a GRPO training pipeline for the ToolOrchestra model, using
**KubeRay** for distributed training and **Kueue** for GPU quota management.

### Training Infrastructure (always deployed)

Deployed automatically by `usecase-toolorchestra` via `tier1-minimal`:

- **LocalQueue** (`training-queue`) -- namespaced queue pointing to `training-cluster-queue`
- **PVC** (`training-checkpoints`, 100Gi) -- stores base model, dataset, and checkpoints
- **ConfigMap** (`grpo-training-config`) -- GRPO hyperparameters adapted for L4 GPUs

### Training Workloads (on-demand)

Managed by `usecase-toolorchestra-training` with **manual sync**:

- **Download Jobs** (sync-wave 0):
  - `download-qwen3-8b` -- downloads Qwen/Qwen3-8B base model
  - `download-training-data` -- downloads nvidia/ToolScale dataset
- **RayJob** (sync-wave 1):
  - `grpo-training` -- 1 head node (no GPU) + 3 GPU worker nodes (1xL4 each)
  - Uses verl framework with GRPO algorithm

### Running Training

```bash
# Option A: Via ArgoCD (recommended, fully GitOps)
argocd app sync usecase-toolorchestra-training

# ArgoCD processes sync waves:
#   Wave 0: download jobs run (base model + dataset)
#   Wave 1: RayJob starts GRPO training (after downloads complete)

# Option B: Via ArgoCD UI
# Navigate to usecase-toolorchestra-training → click Sync

# Option C: Manual (without ArgoCD)
oc apply -k usecases/toolorchestra/manifests/training/workloads/

# Monitor training
oc get rayjob grpo-training -n orchestrator-rhoai -w
oc logs -f -l app.kubernetes.io/name=grpo-head -n orchestrator-rhoai
```

### Kueue GPU Quota

The `kueue-config` instance defines GPU resource management:

| Resource | L40S Quota | L4 Quota |
|----------|-----------|----------|
| CPU | 16 | 32 |
| Memory | 64Gi | 128Gi |
| nvidia.com/gpu | 1 | 4 |

Preemption is enabled: `LowerPriority` within the queue, `Any` within the cohort.

## RHOAI 3.3 Specifics

| Setting | Value | Notes |
|---------|-------|-------|
| RHOAI channel | `fast-3.x` | Required for 3.x releases |
| DSC API | `datasciencecluster.opendatahub.io/v1` | Stable API for 3.3 |
| Kueue | `Unmanaged` in DSC | Red Hat Build of Kueue Operator manages it separately |
| JobSet | Standalone operator | Required for Kubeflow Trainer v2 |
| GPU Operator | Requires `spec.daemonsets` and `spec.dcgm` | Validated with v25.x |
| Kueue instance | Requires `spec.config.integrations.frameworks` | List of supported job frameworks |

## ArgoCD Sync Configuration

The ArgoCD ApplicationSets use production-grade sync options validated through testing:

| Option | Purpose |
|--------|---------|
| `ServerSideApply=true` | Handles large CRDs (DSC, InferenceService, ClusterPolicy) and prevents annotation size limits |
| `SkipDryRunOnMissingResource=true` | Allows retry-based convergence when CRDs don't exist yet |
| `CreateNamespace=true` | ArgoCD manages namespace lifecycle for use cases |
| `RespectIgnoreDifferences=true` | Honors configured `ignoreDifferences` rules |
| `ignoreDifferences` for OLM Subscriptions | Prevents perpetual drift on `.status` and `.spec.startingCSV` |
| `ignoreDifferences` for DataScienceCluster | Prevents drift on `/status` and operator-managed component fields |

Retry policies: operators retry 5x (30s-5m), instances retry 10x (60s-10m), use cases retry 10x (60s-10m).

### App-of-Apps Bootstrap

The `cluster-bootstrap` Application watches `clusters/overlays/dev/` and auto-syncs
any changes. This means:

- Adding a new `Application` YAML to `clusters/overlays/dev/` and pushing to Git
  automatically creates the new ArgoCD Application
- Adding a new operator directory to `components/operators/` automatically creates
  a new operator Application via the `cluster-operators` ApplicationSet
- Same for `components/instances/*` and `usecases/*/profiles/tier1-minimal`

The only manual `oc apply` ever needed is the initial bootstrap (step 3 in Quick Start).

## ToolOrchestra Use Case

NVIDIA ToolOrchestra is a multi-model orchestrator that coordinates specialized AI models
for complex reasoning tasks. The deployment includes:

| Component | Description |
|-----------|-------------|
| `orchestrator-8b` | Nemotron-Orchestrator-8B -- orchestrates tool calls across specialist models |
| `qwen-math-7b` | Qwen2.5-Math-7B-Instruct -- math reasoning specialist |
| `orchestrator-ui` | Web UI for interactive orchestration with SSE streaming |

### Profiles

| Profile | Models | Training | Use Case |
|---------|--------|----------|----------|
| `tier1-minimal` | orchestrator-8b, qwen-math-7b | Infra only | Development, demos |
| `tier2-standard` | + additional models | Infra only | Staging |
| `tier3-full` | All models including qwen3-32b | Infra only | Production |
| `training` | tier1-minimal models | Full (infra + workloads) | Training runs |

## Teardown Procedure

Complete removal of RHOAI and all managed operators. Run steps in order.

```bash
# 1. Delete use case namespaces
oc delete namespace orchestrator-rhoai --wait=true --timeout=300s

# 2. Delete DataScienceCluster and DSCInitialization
oc delete datasciencecluster default-dsc --wait=true --timeout=300s
oc delete dsci default-dsci --wait=true --timeout=120s

# 3. Delete operator instances
oc delete clusterpolicy gpu-cluster-policy --timeout=120s
oc delete nodefeaturediscovery nfd-instance -n openshift-nfd
oc delete kueues.kueue.openshift.io cluster
oc delete jobsetoperator cluster

# 4. Delete operator subscriptions
oc delete sub rhods-operator -n redhat-ods-operator
oc delete sub gpu-operator-certified -n nvidia-gpu-operator
oc delete sub nfd -n openshift-nfd
oc delete sub kueue-operator -n openshift-kueue-operator
oc delete sub job-set -n openshift-jobset-operator
oc delete sub openshift-cert-manager-operator -n cert-manager-operator

# 5. Delete RHOAI auto-installed dependency operators
oc delete sub authorino-operator -n openshift-operators 2>/dev/null || true
oc delete sub servicemeshoperator3 -n openshift-operators 2>/dev/null || true
oc delete sub serverless-operator -n openshift-serverless 2>/dev/null || true

# 6. Delete CSVs from all namespaces
for ns in redhat-ods-operator openshift-kueue-operator openshift-jobset-operator \
  nvidia-gpu-operator openshift-nfd cert-manager-operator openshift-operators \
  openshift-serverless; do
  oc delete csv --all -n "$ns" 2>/dev/null || true
done

# 7. Clean up InstallPlans
oc delete installplan --all -n openshift-operators 2>/dev/null || true

# 8. Delete operator namespaces
for ns in redhat-ods-operator redhat-ods-applications redhat-ods-monitoring \
  openshift-kueue-operator openshift-jobset-operator nvidia-gpu-operator \
  openshift-nfd cert-manager-operator cert-manager openshift-serverless \
  knative-serving knative-serving-ingress knative-eventing openshift-pipelines \
  rhoai-model-registries rhods-notebooks; do
  oc delete namespace "$ns" --wait=true --timeout=120s 2>/dev/null || true
done

# 9. Delete CRDs (batch by domain)
oc delete crd $(oc get crd -o name | grep -E "opendatahub|kserve|kubeflow" | tr '\n' ' ')
oc delete crd $(oc get crd -o name | grep -E "kueue|nvidia|nfd\.|jobset" | tr '\n' ' ')
oc delete crd $(oc get crd -o name | grep -E "tekton|istio|sailoperator|authorino|certmanager|knative" | tr '\n' ' ')

# 10. Fix stuck CRDs (if any remain in Terminating state)
for crd in $(oc get crd -o name | grep -E "opendatahub|kserve|kubeflow|kueue|nvidia|nfd|jobset"); do
  oc patch "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done

# 11. Delete stale webhooks (may block future installs)
oc delete validatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
oc delete mutatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true

# 12. If using GitOps, also remove ArgoCD resources
oc delete -k clusters/overlays/dev/
oc delete sub openshift-gitops-operator -n openshift-gitops-operator
oc delete namespace openshift-gitops-operator openshift-gitops
```

## Known Issues

1. **PVC zone affinity**: With `WaitForFirstConsumer` StorageClass, model download jobs
   must schedule on GPU nodes (via `nodeSelector: nvidia.com/gpu.present: "true"`) to
   ensure PVCs are provisioned in the same zone as GPU nodes.

2. **RWO PVC and download jobs**: Model download jobs share RWO PVCs with predictor pods.
   Sync waves (download at wave 0, InferenceService at wave 1) ensure downloads complete
   before predictors start. Download jobs have no TTL so they persist as completed,
   preventing ArgoCD from recreating them into a Multi-Attach conflict.

3. **DSC API version**: RHOAI 3.3 installs the `v1` DSC CRD. Fields like
   `modelsasservice`, `trainer`, `mlflowoperator` are not yet available in v1.
   Use `datasciencepipelines` (not `aipipelines`), `modelmeshserving`, `codeflare`.

4. **GPU ClusterPolicy v25.x**: Requires `spec.daemonsets` and `spec.dcgm` fields
   that were optional in earlier versions.

5. **Kueue v1.2**: Requires `spec.config.integrations.frameworks` with supported
   framework list (BatchJob, RayJob, RayCluster, JobSet, PyTorchJob, TrainJob).

6. **Stale Tekton webhooks**: After teardown, Tekton validating/mutating webhooks
   may persist and block namespace creation. Delete them explicitly.

7. **servicemeshoperator3**: May reappear after teardown if RHDH operator is installed,
   as it declares servicemesh as an OLM dependency.

8. **RHOAI admission webhooks**: InferenceService annotations referencing non-existent
   `connections` secrets or `hardware-profile` names will be rejected. Remove these
   annotations if the backing resources don't exist.

9. **Job spec immutability**: If a download job's spec changes in Git while a completed
   job exists on the cluster, ArgoCD cannot update it (Kubernetes Jobs are immutable).
   Delete the existing job manually (`oc delete job <name> -n <ns>`), then let ArgoCD
   recreate it with the new spec.

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
       tier1-minimal/
         kustomization.yaml
   ```

2. The `cluster-usecases` ApplicationSet auto-discovers `usecases/*/profiles/tier1-minimal`
   directories. Once pushed to Git, `cluster-bootstrap` syncs the AppSet, which generates
   a new `usecase-<name>` Application automatically.

3. For manual deployment without ArgoCD:
   ```bash
   oc apply -k usecases/my-app/profiles/tier1-minimal/
   ```

4. For model download jobs, always:
   - Add `nodeSelector: nvidia.com/gpu.present: "true"` to ensure PVCs are provisioned
     in the GPU availability zone
   - Add `argocd.argoproj.io/sync-wave: "0"` annotation so downloads run before
     InferenceService (wave 1)
   - Omit `ttlSecondsAfterFinished` so completed jobs persist and ArgoCD doesn't
     recreate them into RWO PVC conflicts

## Adding a New Operator

1. Create `components/operators/my-operator/kustomization.yaml` with a Subscription resource
2. Create `components/instances/my-instance/kustomization.yaml` with the instance CR
3. Push to Git -- `cluster-bootstrap` auto-syncs the AppSets, which auto-discover the
   new directories and create ArgoCD Applications

## References

- [RHOAI 3.3 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
- [ToolOrchestra Paper](https://arxiv.org/abs/2503.02495) -- NVIDIA's multi-model orchestration approach
- [verl Framework](https://github.com/volcengine/verl) -- Reinforcement learning training framework
