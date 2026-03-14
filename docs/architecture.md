# Architecture and GitOps Patterns

The repository implements a fully declarative, GitOps-driven installation of Red Hat OpenShift AI (RHOAI) 3.3 on OpenShift. The entire platform -- from GPU drivers to AI model serving -- is expressed as Kubernetes manifests managed by ArgoCD via an **app-of-apps pattern**.

## Repository Structure

```
rhoai-deploy-gitops/
├── bootstrap/                        # OpenShift GitOps (ArgoCD) operator install
├── clusters/                         # Per-cluster overlays (dev, prod, etc.)
│   ├── base/                         # Common: AppSets + ArgoCD projects
│   └── overlays/dev/
│       ├── bootstrap-app.yaml        # Self-managing app-of-apps
│       ├── rhoai-instance-app.yaml   # DSC with ignoreDifferences
│       └── training-workloads-app.yaml
├── components/
│   ├── argocd/                       # ArgoCD projects and ApplicationSets
│   │   ├── apps/
│   │   │   ├── cluster-operators-appset.yaml
│   │   │   ├── cluster-instances-appset.yaml
│   │   │   ├── cluster-models-appset.yaml
│   │   │   └── cluster-services-appset.yaml
│   │   └── projects/
│   ├── operators/                    # OLM operator subscriptions
│   │   ├── cert-manager/
│   │   ├── servicemesh/
│   │   ├── nfd/
│   │   ├── gpu-operator/
│   │   ├── kueue-operator/
│   │   ├── jobset-operator/
│   │   └── rhoai-operator/
│   └── instances/                    # Operator instance CRs
│       ├── nfd-instance/
│       ├── gpu-instance/
│       ├── gpu-workers/              # GPU MachineSets + MachineAutoscalers
│       ├── cluster-autoscaler/
│       ├── kueue-instance/
│       ├── kueue-config/             # ResourceFlavors + ClusterQueue
│       ├── jobset-instance/
│       ├── dashboard-config/         # Enables GenAI Studio in RHOAI dashboard
│       ├── mcp-servers/              # Registers MCP servers in RHOAI dashboard
│       └── rhoai-instance/           # DataScienceCluster (DSC) with composable overlays
│           ├── base/                 # Minimal DSC (Dashboard only)
│           └── overlays/             # dev, minimal, serving, training, full
└── usecases/
    ├── models/                       # Model deployments (one dir per model)
    │   ├── orchestrator-8b/
    │   ├── qwen-math-7b/
    │   └── gpt-oss-120b/
    └── services/                     # Application services
        ├── toolorchestra-app/        # NVIDIA ToolOrchestra UI
        ├── llamastack/               # Meta LlamaStack Distribution
        ├── genai-toolbox/            # GenAI Toolbox MCP Server
        └── rhokp/                    # Red Hat OKP MCP Server
```

!!! warning "Using a fork? Update the repo URL"
    All ArgoCD manifests reference `https://github.com/rrbanda/rhoai-deploy-gitops.git`. If you forked this repo, run `./setup.sh --repo <your-repo-url>` to update all `repoURL` references, or manually update them in the files listed in `clusters/overlays/dev/`, `components/argocd/apps/`, and `components/argocd/projects/base/`. See the [Quick Start](quickstart.md).

## App-of-Apps Pattern

The installation requires exactly **two** manual commands. After that, Git becomes the single source of truth.

```mermaid
graph TD
  subgraph bootstrap ["Phase 1: Bootstrap"]
    Human["oc apply -k bootstrap/"] --> GitOpsOp["OpenShift GitOps Operator"]
    GitOpsOp --> ArgoCD["ArgoCD Instance"]
  end

  subgraph appOfApps ["Phase 2: App-of-Apps"]
    Human2["oc apply -k clusters/overlays/dev/"] --> BootstrapApp["cluster-bootstrap App"]
    BootstrapApp --> OperatorsAppSet["cluster-operators AppSet"]
    BootstrapApp --> InstancesAppSet["cluster-instances AppSet"]
    BootstrapApp --> ModelsAppSet["cluster-models AppSet"]
    BootstrapApp --> ServicesAppSet["cluster-services AppSet"]
    BootstrapApp --> RhoaiApp["instance-rhoai App"]
    BootstrapApp --> TrainingApp["training-workloads App"]
  end

  subgraph operators ["Phase 3: Operators"]
    OperatorsAppSet --> CertMgr["cert-manager"]
    OperatorsAppSet --> ServiceMesh["ServiceMesh"]
    OperatorsAppSet --> NFDOp["NFD"]
    OperatorsAppSet --> GPUOp["GPU Operator"]
    OperatorsAppSet --> KueueOp["Kueue"]
    OperatorsAppSet --> JobSetOp["JobSet"]
    OperatorsAppSet --> RHOAIOp["RHOAI Operator"]
  end

  subgraph instances ["Phase 4: Instances"]
    InstancesAppSet --> NFDInst["NFD Instance"]
    InstancesAppSet --> GPUInst["GPU ClusterPolicy"]
    InstancesAppSet --> ClusterAS["ClusterAutoscaler"]
    InstancesAppSet --> KueueInst["Kueue Instance"]
    InstancesAppSet --> KueueCfg["Kueue Config"]
    InstancesAppSet --> JobSetInst["JobSet Instance"]
    InstancesAppSet --> DashConfig["Dashboard Config"]
    InstancesAppSet --> McpServers["MCP Servers"]
    RhoaiApp --> DSC["DataScienceCluster"]
  end

  subgraph platform ["Phase 5: RHOAI Platform"]
    DSC --> Dashboard["Dashboard"]
    DSC --> KServe["KServe"]
    DSC --> ModelMesh["ModelMesh"]
    DSC --> Ray["Ray/KubeRay"]
    DSC --> TrainOp["Training Operator"]
    DSC --> Pipelines["DS Pipelines"]
    DSC --> Registry["Model Registry"]
    DSC --> TrustyAI["TrustyAI"]
    DSC --> CodeFlare["CodeFlare"]
    DSC --> LlamaStack["LlamaStack"]
  end

  subgraph models ["Phase 6a: Models"]
    ModelsAppSet --> Orch8b["orchestrator-8b"]
    ModelsAppSet --> QwenMath["qwen-math-7b"]
    ModelsAppSet --> GptOss["gpt-oss-120b"]
  end

  subgraph services ["Phase 6b: Services"]
    ServicesAppSet --> ToolOrch["ToolOrchestra App"]
    ServicesAppSet --> LlamaStackUC["LlamaStack"]
    ServicesAppSet --> GenAIToolbox["GenAI Toolbox"]
    ToolOrch --> UI["Orchestrator UI"]
    ToolOrch --> TrainInfra["Training Infra"]
    TrainingApp --> TrainWorkloads["Training Workloads"]
    LlamaStackUC --> LlamaStackSvr["LlamaStack Server"]
    LlamaStackUC --> Postgres["PostgreSQL"]
  end
```

## ApplicationSet Auto-Discovery

Four `ApplicationSet` resources use **Git directory generators** to auto-discover content:

| ApplicationSet | Discovers | Naming Pattern |
|---------------|-----------|---------------|
| `cluster-operators` | `components/operators/*` | `operator-<dirname>` |
| `cluster-instances` | `components/instances/*` (excludes `rhoai-instance`, `gpu-workers`) | `instance-<dirname>` |
| `cluster-models` | `usecases/models/*/profiles/tier1-minimal` | `model-<dirname>` |
| `cluster-services` | `usecases/services/*/profiles/tier1-minimal` | `service-<dirname>` |

Adding a new directory and pushing to Git automatically creates a new ArgoCD Application.

## Dependency Chain

```mermaid
graph LR
  CertMgr["cert-manager"] --> KServe["KServe"]
  ServiceMesh["ServiceMesh"] --> LlamaStackOp["LlamaStack Operator"]
  NFD["NFD Instance"] --> GPU["GPU ClusterPolicy"]
  GPU --> GPUWorkers["GPU MachineSets"]
  GPUWorkers --> ModelServing["Model Serving"]
  RHOAIOp["RHOAI Operator"] --> DSC["DataScienceCluster"]
  DSC --> KServe
  DSC --> ModelMesh["ModelMesh"]
  DSC --> Ray["Ray"]
  DSC --> LlamaStackOp
  KueueOp["Kueue Operator"] --> KueueInst["Kueue Instance"]
  KueueInst --> KueueCfg["ResourceFlavors + ClusterQueue"]
  KueueCfg --> Training["Training Workloads"]
  JobSetOp["JobSet Operator"] --> JobSetInst["JobSet Instance"]
  JobSetInst --> Training
  KServe --> ModelServing
  Ray --> Training
```

## Why RHOAI Instance Is Handled Separately

The `rhoai-instance` is **excluded** from the `cluster-instances` ApplicationSet and given its own explicit Application because:

1. **Operator mutation** -- The RHOAI operator enriches the DSC's `.spec.components.*` with additional sub-fields. ArgoCD would see these as drift.
2. **Status drift** -- The `/status` field is constantly updated by the operator.
3. **No pruning** -- `prune: false` prevents ArgoCD from deleting operator-created resources.
4. **`RespectIgnoreDifferences=true`** -- Combined with 11 `jsonPointers` ignoring operator-managed paths.

## External Dependencies

- **[redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog)** -- Kustomize bases for 4 operators (cert-manager, NFD, GPU, RHOAI). Referenced via HTTPS URLs in `kustomization.yaml` files.
- **OLM (Operator Lifecycle Manager)** -- Built into OpenShift; handles operator installation from Subscriptions.
- **RHOAI operator** -- When the DSC is created, the RHOAI operator installs ~10 sub-operators (KServe, Knative, Service Mesh, Authorino, etc.) internally. These are not declared in this repo.

## Operators

Seven operators are installed via OLM Subscriptions:

| Operator | Source | Channel | Purpose |
|----------|--------|---------|---------|
| cert-manager | redhat-cop catalog | `stable-v1` | TLS for KServe/Knative |
| ServiceMesh | Red Hat catalog | `stable` | Required for LlamaStack |
| NFD | redhat-cop catalog | `stable` | GPU node feature labels |
| GPU Operator | redhat-cop catalog | `stable` | NVIDIA drivers + toolkit |
| Kueue | Custom subscription | `stable-v1.2` | GPU quota management |
| JobSet | Custom subscription | (default) | Kubeflow Trainer v2 dependency |
| **RHOAI** | redhat-cop catalog + patch | **`fast-3.x`** | The core AI platform |

The RHOAI operator uses a Kustomize patch (`components/operators/rhoai-operator/patch-channel.yaml`) to override the channel to `fast-3.x`, required for RHOAI 3.3.
