# Architecture and Repository Structure

This repository implements a fully declarative, GitOps-driven installation of Red Hat OpenShift AI (RHOAI) on OpenShift. The entire platform -- from GPU drivers to AI model serving -- is expressed as Kubernetes manifests managed by ArgoCD via an **app-of-apps pattern**. The repo tracks the latest RHOAI release by default (`fast` channel) and supports switching to `beta` (EA) or `stable` (LTS) via configuration.

This page describes **this repository's structure** — how the GitOps manifests, ArgoCD Applications, and Kustomize overlays are organized. For an overview of RHOAI the product's internal architecture, see [RHOAI Architecture](concepts/rhoai-architecture.md).

!!! tip "New to these concepts?"
    If terms like "app-of-apps", "ApplicationSet", or "Kustomize overlay" are unfamiliar, read the [Concepts](concepts/index.md) section first. This page assumes familiarity with those foundations.

## Repository Structure

```
rhoai-deploy-gitops/
├── bootstrap/                          # ← SINGLE ENTRY POINT
│   ├── base/                           # OpenShift GitOps operator + RBAC
│   └── overlays/default/
│       ├── kustomization.yaml          # Aggregates everything + Kustomize replacements
│       ├── argocd-instance.yaml        # ArgoCD CR configuration
│       ├── cluster-config.yaml         # ← THE ONLY FILE YOU EDIT
│       └── gitops-controller.yaml      # Self-management (ArgoCD manages itself)
├── components/
│   ├── argocd/
│   │   ├── applicationsets/            # Auto-discovery ApplicationSets
│   │   │   ├── cluster-operators-appset.yaml
│   │   │   ├── cluster-instances-appset.yaml
│   │   │   ├── cluster-models-appset.yaml
│   │   │   └── cluster-services-appset.yaml
│   │   ├── projects/                   # AppProject definitions (platform, usecases)
│   │   └── apps/                       # Standalone Applications (DSC)
│   ├── operators/                      # OLM operator subscriptions
│   │   ├── cert-manager/
│   │   ├── cma-operator/
│   │   ├── external-secrets/
│   │   ├── gpu-operator/
│   │   ├── jobset-operator/
│   │   ├── kueue-operator/
│   │   ├── lws/
│   │   ├── nfd/
│   │   ├── rhcl/
│   │   ├── rhdh/
│   │   ├── rhoai-operator/
│   │   └── servicemesh/
│   └── instances/                      # Operator instance CRs
│       ├── cluster-autoscaler/         # ClusterAutoscaler CR
│       ├── dashboard-config/           # RHOAI Dashboard customization
│       ├── evalhub/                    # Model evaluation hub
│       ├── external-secrets-config/    # SecretStore + ExternalSecret wiring
│       ├── gpu-instance/               # NVIDIA ClusterPolicy CR
│       ├── gpu-workers/                # GPU MachineSets (cloud-specific examples)
│       ├── hardware-profiles/          # HardwareProfile CRs for model serving
│       ├── jobset-instance/            # JobSet operator instance
│       ├── kueue-config/               # ResourceFlavors + ClusterQueue
│       ├── kueue-instance/             # Kueue operator instance
│       ├── lws-instance/               # LeaderWorkerSet operator instance
│       ├── maas-dns-patch/             # DNS configuration patch for MaaS routes
│       ├── maas-gateway/               # API gateway configuration for MaaS
│       ├── maas-postgres/              # PostgreSQL database for Models-as-a-Service
│       ├── mcp-servers/                # MCP server deployments
│       ├── mlflow-instance/            # MLflow tracking server
│       ├── monitoring-config/          # Enables user workload monitoring
│       ├── nfd-instance/               # NodeFeatureDiscovery CR
│       ├── observability/              # ServiceMonitors + Grafana dashboards
│       ├── oidc-integration/           # OIDC AuthConfig for MaaS authentication
│       ├── rhcl-instance/              # Red Hat Connectivity Link instance
│       └── rhoai-instance/             # DataScienceCluster with composable overlays
│           ├── base/                   # Full DSC (all components enabled)
│           └── overlays/               # dev, minimal, serving, training, full, maas
├── usecases/
│   ├── models/                         # Model deployments
│   └── services/                       # AI application services
├── docs/                               # This documentation site (MkDocs)
├── scripts/configure.sh                            # One-time configuration script
├── mkdocs.yml                          # Documentation configuration
└── .github/workflows/                  # CI/CD (validation + docs deployment)
```

## The Parameterization Layer

A key design decision: **no hardcoded repository URLs or branch names** exist in any ArgoCD manifest. Instead, a single configuration file drives everything:

```yaml
# bootstrap/overlays/default/cluster-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-gitops-config
data:
  repoURL: "https://github.com/YOUR-ORG/rhoai-deploy-gitops.git"
  targetRevision: "main"
```

Kustomize **replacements** in `bootstrap/overlays/default/kustomization.yaml` inject these values into every Application and ApplicationSet at build time. This means:

- Fork the repo, run `./scripts/configure.sh`, and all references update automatically
- Switch branches by editing one field
- No find-and-replace across dozens of files

## App-of-Apps Deployment Flow

```mermaid
graph TD
  subgraph bootstrap ["Phase 1: Bootstrap (single command, once)"]
    Human["oc apply -k bootstrap/overlays/default/"] --> GitOpsOp["OpenShift GitOps Operator"]
    GitOpsOp --> ArgoCD["ArgoCD Instance"]
    ArgoCD --> BootstrapApp["gitops-controller App"]
  end

  subgraph autoManaged ["Phase 2+: Auto-managed (GitOps forever)"]
    BootstrapApp --> OperatorsAS["cluster-operators AppSet"]
    BootstrapApp --> InstancesAS["cluster-instances AppSet"]
    BootstrapApp --> ModelsAS["cluster-models AppSet"]
    BootstrapApp --> ServicesAS["cluster-services AppSet"]
    BootstrapApp --> DSCApp["rhoai-dsc App"]
  end

  subgraph operators ["Operators (auto-discovered)"]
    OperatorsAS --> CertMgr["cert-manager"]
    OperatorsAS --> NFDOp["NFD"]
    OperatorsAS --> GPUOp["GPU Operator"]
    OperatorsAS --> KueueOp["Kueue"]
    OperatorsAS --> RHOAIOp["RHOAI Operator"]
    OperatorsAS --> MoreOps["+ 6 more"]
  end

  subgraph instances ["Instances (auto-discovered)"]
    InstancesAS --> NFDInst["NFD Instance"]
    InstancesAS --> GPUInst["GPU ClusterPolicy"]
    InstancesAS --> KueueInst["Kueue Config"]
    InstancesAS --> MoreInst["+ more"]
    DSCApp --> DSC["DataScienceCluster"]
  end

  subgraph platform ["RHOAI Platform (operator-managed)"]
    DSC --> KServe["KServe"]
    DSC --> Ray["Ray"]
    DSC --> Training["Training"]
    DSC --> BatchGW["Batch Gateway"]
    DSC --> MoreComp["+ 8 more"]
  end
```

After Phase 2, you never run `oc apply` again. Git becomes the interface.

## ApplicationSet Auto-Discovery

Four ApplicationSets use Git directory generators to discover content automatically:

| ApplicationSet | Scans Path | Creates | Naming |
|---------------|-----------|---------|--------|
| `cluster-operators` | `components/operators/*/` | Operator subscriptions | `operator-<dirname>` |
| `cluster-instances` | `components/instances/*/` | Operator instance CRs | `instance-<dirname>` |
| `cluster-models` | `usecases/models/*/profiles/tier1-minimal/` | Model serving deployments | `model-<dirname>` |
| `cluster-services` | `usecases/services/*/profiles/tier1-minimal/` | AI applications | `service-<dirname>` |

**To add a new component:** Create a directory, push to Git. ArgoCD discovers it and creates an Application automatically. No manual configuration.

## Dependency Chain

Resources must be installed in order. ArgoCD handles this through retry policies -- if a resource fails because its CRD does not exist yet, ArgoCD retries until the dependency is installed.

```mermaid
graph LR
  CertMgr["cert-manager"] --> KServe["KServe (internal)"]
  CertMgr --> Kueue["Kueue"]
  ServiceMesh["ServiceMesh"] --> BatchGW["Batch Gateway"]
  NFD["NFD"] --> GPU["GPU Operator"]
  GPU --> GPUNodes["GPU Nodes"]
  GPUNodes --> Serving["Model Serving"]
  GPUNodes --> Training["Training Jobs"]
  LWS["LeaderWorkerSet"] --> BatchGW
  RHCL["RHCL"] --> AIGateway["AI Gateway"]
  RHOAIOp["RHOAI Operator"] --> DSC["DSC"]
  DSC --> KServe
  DSC --> Ray["Ray"]
  DSC --> BatchGW
  KueueOp["Kueue"] --> KueueCfg["Quotas"]
  KueueCfg --> Training
  JobSet["JobSet"] --> Training
```

## Operators Deployed

| Operator | Channel | Purpose | Required For |
|----------|---------|---------|-------------|
| cert-manager | `stable-v1` | TLS certificates | KServe, Kueue, training |
| ServiceMesh 3 | `stable` | Service mesh for batch gateway | Batch inference |
| NFD | `stable` | GPU node detection | GPU workloads |
| GPU Operator | `stable` | NVIDIA drivers + toolkit | GPU workloads |
| Kueue | `stable-v1` | GPU quota management | Training |
| JobSet | (default) | Multi-pod job orchestration | Training |
| LeaderWorkerSet | `stable` | Leader-worker topology | Distributed inference |
| CMA/KEDA | `stable` | Custom metrics autoscaling | Auto-scaling |
| AI Gateway | `beta` | API gateway for models | MaaS |
| RHCL | `stable` | Connectivity link | AI Gateway |
| **RHOAI** | `beta` | Core AI platform | Everything |

## Instances Deployed

Each instance is auto-discovered by the `cluster-instances` ApplicationSet. They configure operator CRs, platform services, and supporting infrastructure:

| Instance | Purpose |
|----------|---------|
| `cluster-autoscaler` | ClusterAutoscaler CR for node auto-scaling |
| `dashboard-config` | RHOAI Dashboard configuration and customization |
| `evalhub` | Model evaluation hub for benchmarking and comparison |
| `external-secrets-config` | SecretStore and ExternalSecret wiring for external secrets management (e.g., HashiCorp Vault) |
| `gpu-instance` | NVIDIA ClusterPolicy CR — installs GPU drivers and toolkit |
| `gpu-workers` | GPU MachineSets for cloud provider GPU node provisioning |
| `hardware-profiles` | HardwareProfile CRs defining GPU/CPU resource shapes for model serving |
| `jobset-instance` | JobSet operator instance CR |
| `kueue-config` | ResourceFlavors, ClusterQueue, and quota policies for GPU scheduling |
| `kueue-instance` | Kueue operator instance CR |
| `lws-instance` | LeaderWorkerSet operator instance CR for distributed inference |
| `maas-dns-patch` | DNS configuration patch for Models-as-a-Service routes |
| `maas-gateway` | API gateway configuration for MaaS endpoint routing |
| `maas-postgres` | PostgreSQL database instance for Models-as-a-Service metadata |
| `mcp-servers` | MCP (Model Context Protocol) server deployments |
| `mlflow-instance` | MLflow tracking server for experiment and model registry |
| `monitoring-config` | Enables user workload monitoring on OpenShift (`ConfigMap` in `openshift-user-workload-monitoring`) |
| `nfd-instance` | NodeFeatureDiscovery CR — detects hardware features on nodes |
| `observability` | ServiceMonitors and Grafana dashboards for RHOAI platform monitoring |
| `oidc-integration` | OIDC/AuthConfig for MaaS authentication via Keycloak or external IdP |
| `rhcl-instance` | Red Hat Connectivity Link instance CR |
| `vault-dev` | Development-mode HashiCorp Vault instance (for testing external secrets) |

!!! note "DSC is separate"
    The `rhoai-instance` (DataScienceCluster) is **not** managed by the `cluster-instances` ApplicationSet. It has its own dedicated Application (`rhoai-dsc`) due to special sync requirements. See below.

## Why the DSC Has Its Own Application

The DataScienceCluster is excluded from the `cluster-instances` ApplicationSet and managed by a dedicated Application (`rhoai-dsc`). This is because:

1. **Operator mutation** -- RHOAI enriches the DSC with sub-fields not in Git
2. **No pruning** -- `prune: false` prevents deleting operator-created resources
3. **ignoreDifferences** -- Suppresses false drift from operator-managed fields
4. **Replace sync** -- Uses `Replace=true` instead of three-way merge to avoid null-field conflicts

See [Sync Configuration](reference/sync-config.md) for the full list of `ignoreDifferences` rules.

## External Dependencies

| Dependency | Referenced How | Purpose |
|-----------|--------------|---------|
| [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) | HTTPS URL in kustomization.yaml | Base manifests for cert-manager, NFD, GPU, RHOAI operators |
| OLM (built into OpenShift) | Subscriptions | Operator installation |
| RHOAI operator (internal) | DSC reconciliation | Installs KServe, Knative, Authorino, etc. |
