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
| `tier1-minimal` | orchestrator-8b, qwen-math-7b | Infra only | Development, demos |
| `tier2-standard` | orchestrator-8b, qwen-math-7b, qwen3-32b | Infra only | Staging |
| `tier3-full` | orchestrator-8b, qwen-math-7b, qwen3-32b | Infra only | Production |
| `training` | orchestrator-8b, qwen-math-7b | Full (infra + workloads) | Training runs |

!!! note "tier2 vs tier3"
    `tier2-standard` and `tier3-full` currently deploy the same models. They differ only by a `tier` label ("2" vs "3") for environment separation. Extend `tier3-full` with additional models as your cluster scales.

## Prerequisites

ToolOrchestra deploys InferenceServices that require a fully configured RHOAI platform. Ensure the following are installed and ready before deploying:

| Requirement | Why | Guide |
|-------------|-----|-------|
| RHOAI Operator + DSC with `kserve: Managed` | InferenceServices require the KServe serving platform | [Quick Start](../quickstart.md) or [Model Serving](../capabilities/model-serving.md) |
| cert-manager Operator | KServe requires TLS certificates via Knative | [Capabilities](../capabilities/index.md) |
| GPU infrastructure (NFD + GPU Operator + GPU workers) | Models require NVIDIA L4 or L40S GPUs | [GPU Infrastructure](../capabilities/gpu-infrastructure.md) |
| Kueue + JobSet (for training only) | Training workloads need GPU quota management | [Training](../capabilities/training.md) |

!!! warning "GPU MachineSet customization"
    The `gpu-workers` manifests contain cluster-specific values (AMI ID, subnet, instance type). Edit them to match your cluster before deploying. See [GPU Infrastructure](../capabilities/gpu-infrastructure.md).

## Deploy

=== "GitOps"

    ToolOrchestra is auto-deployed by the `cluster-usecases` ApplicationSet when using the `tier1-minimal` profile.

    After bootstrapping the cluster, the `usecase-toolorchestra` Application is created automatically.

=== "Manual"

    ```bash
    oc apply -k usecases/toolorchestra/profiles/tier1-minimal/

    # Wait for models to download and become Ready
    oc wait --for=condition=Ready inferenceservice/orchestrator-8b \
      -n orchestrator-rhoai --timeout=1800s
    oc wait --for=condition=Ready inferenceservice/qwen-math-7b \
      -n orchestrator-rhoai --timeout=1800s
    ```

## Sync Wave Ordering

Within the `usecase-toolorchestra` app, sync waves ensure correct resource ordering:

| Wave | Resources | Purpose |
|------|-----------|---------|
| -1 (default) | Namespace, RBAC, ConfigMaps, PVCs, ServingRuntimes, Service, Route, NetworkPolicy, LocalQueue | Infrastructure created first |
| 0 | `download-orchestrator-8b`, `download-qwen-math-7b` Jobs | Model downloads run before predictors start |
| 1 | `orchestrator-8b`, `qwen-math-7b` InferenceServices | Predictors created after models are downloaded |

Download jobs are idempotent (check for `.download_complete` marker) and have no TTL, so completed jobs persist as Synced/Healthy in ArgoCD.

## Training Pipeline

The repository includes a GRPO training pipeline using **KubeRay** for distributed training and **Kueue** for GPU quota management.

### Training Infrastructure (always deployed)

Deployed automatically by `tier1-minimal`:

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

=== "ArgoCD CLI"

    ```bash
    argocd app sync usecase-toolorchestra-training
    ```

    ArgoCD processes sync waves: download jobs first (wave 0), then RayJob (wave 1).

=== "ArgoCD UI"

    Navigate to `usecase-toolorchestra-training` and click **Sync**.

=== "Manual"

    ```bash
    oc apply -k usecases/toolorchestra/manifests/training/workloads/
    ```

### Monitor Training

```bash
oc get rayjob grpo-training -n orchestrator-rhoai -w
oc logs -f -l app.kubernetes.io/name=grpo-head -n orchestrator-rhoai
```

## GPU Worker Node Scaling

GPU worker nodes are fully GitOps-managed.

### Manual Scaling via Git

```bash
# Edit components/instances/gpu-workers/gpu-machineset-l4.yaml
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
