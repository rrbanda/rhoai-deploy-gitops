# ArgoCD Applications

After bootstrap, ArgoCD manages **~18 Applications** across three layers.

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
| `operator-servicemesh` | `components/operators/servicemesh/` | Auto (selfHeal) | Red Hat OpenShift Service Mesh 3 operator (required for LlamaStack) |
| `operator-leader-worker-set` | `components/operators/leader-worker-set/` | Auto (selfHeal) | Red Hat Leader Worker Set Operator (required for distributed inference) |
| `operator-opentelemetry` | `components/operators/opentelemetry/` | Auto (selfHeal) | Red Hat OpenTelemetry Operator |
| `operator-tempo` | `components/operators/tempo/` | Auto (selfHeal) | Red Hat Tempo Operator |
| `instance-nfd-instance` | `components/instances/nfd-instance/` | Auto (selfHeal) | NFD NodeFeatureDiscovery CR |
| `instance-gpu-instance` | `components/instances/gpu-instance/` | Auto (selfHeal) | GPU ClusterPolicy CR |
| `instance-kueue-instance` | `components/instances/kueue-instance/` | Auto (selfHeal) | Kueue operator instance |
| `instance-cluster-autoscaler` | `components/instances/cluster-autoscaler/` | Auto (selfHeal) | ClusterAutoscaler for GPU node auto-scaling |
| `instance-kueue-config` | `components/instances/kueue-config/` | Auto (selfHeal) | GPU ResourceFlavors + ClusterQueue |
| `instance-jobset-instance` | `components/instances/jobset-instance/` | Auto (selfHeal) | JobSet operator instance |
| `instance-rhoai` | `components/instances/rhoai-instance/overlays/dev/` | Auto (selfHeal, no prune) | DataScienceCluster with ignoreDifferences |
| `instance-dashboard-config` | `components/instances/dashboard-config/` | Auto (selfHeal) | Enables genAiStudio in the RHOAI dashboard |
| `instance-mcp-servers` | `components/instances/mcp-servers/` | Auto (selfHeal) | Registers MCP servers (GenAI Toolbox, OKP) in the RHOAI dashboard |
| `instance-mlflow-instance` | `components/instances/mlflow-instance/` | Auto (selfHeal) | MLflow tracking server instance |

## App-of-Apps Bootstrap

The `cluster-bootstrap` Application watches `clusters/overlays/dev/` and auto-syncs any changes. This means:

- Adding a new `Application` YAML to `clusters/overlays/dev/` and pushing to Git automatically creates the new ArgoCD Application
- Adding a new operator directory to `components/operators/` automatically creates a new operator Application via the `cluster-operators` ApplicationSet
- Same for `components/instances/*`

The only manual `oc apply` ever needed is the initial bootstrap.

## Adding a New Operator

1. Create `components/operators/my-operator/kustomization.yaml` with a Subscription resource
2. Create `components/instances/my-instance/kustomization.yaml` with the instance CR
3. Push to Git -- `cluster-bootstrap` auto-syncs the AppSets, which auto-discover the new directories and create ArgoCD Applications
