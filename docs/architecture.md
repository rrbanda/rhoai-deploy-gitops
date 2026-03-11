# Architecture

The repository implements a fully declarative, GitOps-driven installation of RHOAI 3.3 on OpenShift. The entire platform -- from GPU drivers to AI model serving -- is expressed as Kubernetes manifests managed by ArgoCD via an **app-of-apps pattern**.

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
│   │   │   └── cluster-usecases-appset.yaml
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
│       ├── gpu-workers/              # GPU MachineSets + MachineAutoscalers
│       ├── cluster-autoscaler/
│       ├── kueue-instance/
│       ├── kueue-config/             # ResourceFlavors + ClusterQueue
│       ├── jobset-instance/
│       └── rhoai-instance/           # DataScienceCluster with composable overlays
│           ├── base/                 # Minimal DSC (Dashboard only)
│           └── overlays/             # dev, minimal, serving, training, full
└── usecases/
    └── toolorchestra/                # NVIDIA ToolOrchestra
```

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
    BootstrapApp --> UsecasesAppSet["cluster-usecases AppSet"]
    BootstrapApp --> RhoaiApp["instance-rhoai App"]
    BootstrapApp --> TrainingApp["training-workloads App"]
  end

  subgraph operators ["Phase 3: Operators"]
    OperatorsAppSet --> CertMgr["cert-manager"]
    OperatorsAppSet --> NFDOp["NFD"]
    OperatorsAppSet --> GPUOp["GPU Operator"]
    OperatorsAppSet --> KueueOp["Kueue"]
    OperatorsAppSet --> JobSetOp["JobSet"]
    OperatorsAppSet --> RHOAIOp["RHOAI Operator"]
  end

  subgraph instances ["Phase 4: Instances"]
    InstancesAppSet --> NFDInst["NFD Instance"]
    InstancesAppSet --> GPUInst["GPU ClusterPolicy"]
    InstancesAppSet --> GPUWorkers["GPU MachineSets"]
    InstancesAppSet --> ClusterAS["ClusterAutoscaler"]
    InstancesAppSet --> KueueInst["Kueue Instance"]
    InstancesAppSet --> KueueCfg["Kueue Config"]
    InstancesAppSet --> JobSetInst["JobSet Instance"]
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

  subgraph usecases ["Phase 6: Use Cases"]
    UsecasesAppSet --> ToolOrch["ToolOrchestra"]
    ToolOrch --> Models["Model Serving"]
    ToolOrch --> UI["Orchestrator UI"]
    ToolOrch --> TrainInfra["Training Infra"]
    TrainingApp --> TrainWorkloads["Training Workloads"]
  end
```

## ApplicationSet Auto-Discovery

Three `ApplicationSet` resources use **Git directory generators** to auto-discover content:

| ApplicationSet | Discovers | Naming Pattern |
|---------------|-----------|---------------|
| `cluster-operators` | `components/operators/*` | `operator-<dirname>` |
| `cluster-instances` | `components/instances/*` (excludes `rhoai-instance`) | `instance-<dirname>` |
| `cluster-usecases` | `usecases/*/profiles/tier1-minimal` | `usecase-<dirname>` |

Adding a new directory and pushing to Git automatically creates a new ArgoCD Application.

## Dependency Chain

```mermaid
graph LR
  CertMgr["cert-manager"] --> KServe["KServe"]
  NFD["NFD Instance"] --> GPU["GPU ClusterPolicy"]
  GPU --> GPUWorkers["GPU MachineSets"]
  GPUWorkers --> ModelServing["Model Serving"]
  RHOAIOp["RHOAI Operator"] --> DSC["DataScienceCluster"]
  DSC --> KServe
  DSC --> ModelMesh["ModelMesh"]
  DSC --> Ray["Ray"]
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

Six operators are installed via OLM Subscriptions:

| Operator | Source | Channel | Purpose |
|----------|--------|---------|---------|
| cert-manager | redhat-cop catalog | `stable-v1` | TLS for KServe/Knative |
| NFD | redhat-cop catalog | `stable` | GPU node feature labels |
| GPU Operator | redhat-cop catalog | `stable` | NVIDIA drivers + toolkit |
| Kueue | Custom subscription | `stable-v1.2` | GPU quota management |
| JobSet | Custom subscription | (default) | Kubeflow Trainer v2 dependency |
| **RHOAI** | redhat-cop catalog + patch | **`fast-3.x`** | The core AI platform |

The RHOAI operator uses a Kustomize patch (`components/operators/rhoai-operator/patch-channel.yaml`) to override the channel to `fast-3.x`, required for RHOAI 3.3.
