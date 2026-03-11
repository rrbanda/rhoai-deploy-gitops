# ArgoCD Applications

After bootstrap, ArgoCD manages **17 Applications** across three layers.

## Application Table

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

## Sync Wave Ordering

Within the `usecase-toolorchestra` app, sync waves ensure correct resource ordering:

| Wave | Resources | Purpose |
|------|-----------|---------|
| -1 (default) | Namespace, RBAC, ConfigMaps, PVCs, ServingRuntimes, Service, Route, NetworkPolicy, LocalQueue | Infrastructure created first |
| 0 | `download-orchestrator-8b`, `download-qwen-math-7b` Jobs | Model download jobs run and complete before predictors start |
| 1 | `orchestrator-8b`, `qwen-math-7b` InferenceServices | Predictors created only after models are downloaded to PVCs |

Download jobs are idempotent (check for `.download_complete` marker) and have no TTL, so completed jobs persist as Synced/Healthy in ArgoCD without being recreated.

## App-of-Apps Bootstrap

The `cluster-bootstrap` Application watches `clusters/overlays/dev/` and auto-syncs any changes. This means:

- Adding a new `Application` YAML to `clusters/overlays/dev/` and pushing to Git automatically creates the new ArgoCD Application
- Adding a new operator directory to `components/operators/` automatically creates a new operator Application via the `cluster-operators` ApplicationSet
- Same for `components/instances/*` and `usecases/*/profiles/tier1-minimal`

The only manual `oc apply` ever needed is the initial bootstrap.

## Adding a New Operator

1. Create `components/operators/my-operator/kustomization.yaml` with a Subscription resource
2. Create `components/instances/my-instance/kustomization.yaml` with the instance CR
3. Push to Git -- `cluster-bootstrap` auto-syncs the AppSets, which auto-discover the new directories and create ArgoCD Applications
