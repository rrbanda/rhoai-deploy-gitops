# ToolOrchestra Multi-Model Orchestrator

NVIDIA ToolOrchestra is a multi-model orchestrator that coordinates specialized AI models for complex reasoning tasks.

## Components

| Component | Description |
|-----------|-------------|
| `orchestrator-8b` | Nemotron-Orchestrator-8B -- orchestrates tool calls across specialist models |
| `qwen-math-7b` | Qwen2.5-Math-7B-Instruct -- math reasoning specialist |
| `orchestrator-ui` | Web UI for interactive orchestration with SSE streaming |

## Profiles

| Profile | Models | Training | Use Case |
|---------|--------|----------|----------|
| `tier1-minimal` | orchestrator-8b, qwen-math-7b | Not included | Development, demos |
| `training` | orchestrator-8b, qwen-math-7b | Full (infra + workloads) | Training runs |

!!! tip "Adding profiles"
    Create additional profiles (e.g. `tier2-standard` with more models) by adding a new directory under `profiles/`. See [CONTRIBUTING.md](https://github.com/rrbanda/rhoai-deploy-gitops/blob/main/CONTRIBUTING.md) for conventions.

## Prerequisites

ToolOrchestra deploys InferenceServices that require a fully configured RHOAI platform. Ensure the following are installed and ready before deploying:

| Requirement | Why | Guide |
|-------------|-----|-------|
| RHOAI Operator + DSC with `kserve: Managed` | InferenceServices require the KServe serving platform | [Quick Start](../quickstart.md) or [Model Serving](../capabilities/model-serving.md) |
| cert-manager Operator | KServe requires TLS certificates via Knative | [Capabilities](../capabilities/index.md) |
| GPU infrastructure (NFD + GPU Operator + GPU workers) | Models require NVIDIA L4 or L40S GPUs | [GPU Infrastructure](../capabilities/gpu-infrastructure.md) |
| Kueue + JobSet (for training only) | Training workloads need GPU quota management | [Training](../capabilities/training.md) |

!!! warning "GPU MachineSet customization"
    GPU worker provisioning is cloud-specific. Example manifests for AWS are in `components/instances/gpu-workers/examples/aws/`. Customize them for your cluster or create your own. See [GPU Infrastructure](../capabilities/gpu-infrastructure.md).

## Deploy

!!! warning "Model dependencies required"
    ToolOrchestra requires **orchestrator-8b** and **qwen-math-7b** models to be deployed and Ready. The ToolOrchestra UI connects to these model endpoints at runtime. Without them, the UI will load but inference calls will fail.

=== "GitOps"

    ToolOrchestra is auto-deployed by the `cluster-services` ApplicationSet when using the `tier1-minimal` profile.

    After bootstrapping the cluster, the `service-toolorchestra-app` Application is created automatically. Model dependencies (orchestrator-8b, qwen-math-7b) are deployed separately by the `cluster-models` ApplicationSet.

=== "Manual"

    ```bash
    # Deploy models first (services depend on these endpoints)
    oc apply -k usecases/models/orchestrator-8b/profiles/tier1-minimal/
    oc apply -k usecases/models/qwen-math-7b/profiles/tier1-minimal/

    # Wait for models to download and become Ready
    oc wait --for=condition=Ready inferenceservice/orchestrator-8b \
      -n orchestrator-8b --timeout=1800s
    oc wait --for=condition=Ready inferenceservice/qwen-math-7b \
      -n qwen-math-7b --timeout=1800s

    # Deploy the ToolOrchestra service
    oc apply -k usecases/services/toolorchestra-app/profiles/tier1-minimal/
    ```

## Sync Wave Ordering

Sync waves ensure correct resource ordering across the related ArgoCD Applications:

**`model-orchestrator-8b` and `model-qwen-math-7b` apps:**

| Wave | Resources | Purpose |
|------|-----------|---------|
| -1 (default) | Namespace, PVCs, ServingRuntimes, Service, Route | Infrastructure created first |
| 0 | `download-orchestrator-8b`, `download-qwen-math-7b` Jobs | Model downloads run before predictors start |
| 1 | `orchestrator-8b`, `qwen-math-7b` InferenceServices | Predictors created after models are downloaded |

Download jobs are idempotent (check for `.download_complete` marker) and have no TTL, so completed jobs persist as Synced/Healthy in ArgoCD.

**`service-toolorchestra-app` app:** Deploys Namespace, RBAC, ConfigMaps, NetworkPolicy, and the ToolOrchestra UI Deployment at the default wave. No sync wave ordering is needed since it contains no download jobs or InferenceServices.

## Training Pipeline

The repository includes a GRPO training pipeline using **KubeRay** for distributed training and **Kueue** for GPU quota management.

### Training Infrastructure (deploy separately)

Training infrastructure lives in `usecases/services/toolorchestra-app/manifests/training/infra/` and must be deployed before running training workloads:

- **LocalQueue** (`training-queue`) -- namespaced queue pointing to `training-cluster-queue`
- **PVC** (`training-checkpoints`, 100Gi) -- stores base model, dataset, and checkpoints
- **ConfigMap** (`grpo-training-config`) -- GRPO hyperparameters adapted for L4 GPUs

!!! warning "Not included in tier1-minimal"
    The `tier1-minimal` profile deploys only the ToolOrchestra UI. Training infrastructure and workloads require separate deployment.

### Training Workloads (on-demand)

Managed by `usecase-toolorchestra-training` (explicit Application in `clusters/overlays/dev/`) with **manual sync**:

- **Download Jobs** (sync-wave 0):
    - `download-qwen3-8b` -- downloads Qwen/Qwen3-8B base model
    - `download-training-data` -- downloads nvidia/ToolScale dataset
- **RayJob** (sync-wave 1):
    - `grpo-training` -- 1 head node (no GPU) + 3 GPU worker nodes (1xL4 each)
    - Uses verl framework with GRPO algorithm

### Running Training

=== "ArgoCD CLI"

    ```bash
    argocd app sync usecase-toolorchestra-training
    ```

    ArgoCD processes sync waves: download jobs first (wave 0), then RayJob (wave 1).

=== "ArgoCD UI"

    Navigate to `usecase-toolorchestra-training` and click **Sync**.

=== "Manual"

    ```bash
    # Deploys both training infra (LocalQueue, PVC, ConfigMap) and workloads (download jobs, RayJob)
    oc apply -k usecases/services/toolorchestra-app/manifests/training/
    ```

### Monitor Training

```bash
oc get rayjob grpo-training -n orchestrator-rhoai -w
oc logs -f -l app.kubernetes.io/name=grpo-head -n orchestrator-rhoai
```

## GPU Worker Node Scaling

GPU worker nodes can be managed via Git (cloud-specific, see `components/instances/gpu-workers/examples/aws/`).

### Manual Scaling via Git

```bash
# Edit components/instances/gpu-workers/examples/aws/gpu-machineset-l4.yaml
#   spec.replicas: 5
git commit -am "Scale L4 GPU workers to 5" && git push
```

### Auto-scaling

| Resource | Config | Effect |
|----------|--------|--------|
| ClusterAutoscaler | max 20 nodes, max 8 GPUs | Cluster-wide scaling limits |
| MachineAutoscaler (L4) | min: 1, max: 6 | Auto-scales `g6.2xlarge` nodes |
| MachineAutoscaler (L40S) | min: 0, max: 4 | Auto-scales `g6e.2xlarge` nodes |

When a pod requests `nvidia.com/gpu` and no capacity is available, the ClusterAutoscaler automatically adds GPU nodes. Idle nodes are removed after 10 minutes.
