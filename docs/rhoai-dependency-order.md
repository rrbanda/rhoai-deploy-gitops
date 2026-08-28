# RHOAI 3.5 Complete Dependency Order

Sources:
- [RHOAI 3.5 Install Guide Section 3.1.2 "Component Requirements"](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.5 Install Guide Chapter 5 "Installing Distributed Workloads Components"](same)
- [Red Hat odh-gitops Helm chart dependency resolution](https://developers.redhat.com/articles/2026/08/26/automating-red-hat-openshift-ai-installations-with-helm-and-gitops)

---

## Master list: Every operator in a full RHOAI 3.5 GA deployment

| # | Operator | OLM Package | Namespace | Depends On | Required By |
|---|---|---|---|---|---|
| 1 | cert-manager | openshift-cert-manager-operator | cert-manager-operator | (none) | KServe, Kueue, LWS, RHCL, ServiceMesh, llm-d |
| 2 | Node Feature Discovery | nfd | openshift-nfd | (none) | GPU Operator |
| 3 | OpenShift Pipelines | openshift-pipelines-operator-rh | openshift-operators | (none) | AI Pipelines (DSP) |
| 4 | Service Mesh 3.x | servicemeshoperator3 | openshift-operators | cert-manager | OGX, RAG |
| 5 | NVIDIA GPU Operator | gpu-operator-certified | nvidia-gpu-operator | NFD | Inference, Training |
| 6 | Leader Worker Set | leader-worker-set | openshift-lws | cert-manager | RHCL, llm-d |
| 7 | Red Hat build of Kueue | kueue-operator | openshift-kueue-operator | cert-manager | Distributed workloads |
| 8 | JobSet | job-set | openshift-jobset-operator | (none) | Distributed training |
| 9 | Custom Metrics Autoscaler | openshift-custom-metrics-autoscaler-operator | openshift-custom-metrics-autoscaler | (none) | HPA for inference pods |
| 10 | Red Hat Connectivity Link | rhcl-operator | kuadrant-system | cert-manager + LWS | llm-d, API Gateway, MaaS |
| 11 | **Red Hat OpenShift AI** | rhods-operator | redhat-ods-operator | cert-manager, servicemesh (for OGX/RAG) | DSC, all RHOAI features |

---

## Per-capability dependency chain (verbatim from docs)

```
WORKBENCHES:
  Prereqs: (none beyond RHOAI operator)

AI PIPELINES:
  Prereqs: OpenShift Pipelines operator + S3 storage

KUEUE-BASED WORKLOADS (kueue, ray, trainingoperator):
  Prereqs: Red Hat build of Kueue Operator + cert-manager Operator
  DSC setting: kueue = Unmanaged (external operator manages it)

MODEL SERVING (KServe):
  Prereqs: cert-manager Operator

DISTRIBUTED INFERENCE with llm-d:
  Prereqs: cert-manager + Red Hat Connectivity Link + Leader Worker Set

OGX AND RAG WORKLOADS:
  Prereqs: Service Mesh 3.x (BEFORE RHOAI operator) + cert-manager
           + NFD + GPU Operator + S3 storage
  NOTE: Service Mesh is ONLY required if OGX/RAG is enabled.
        It is NOT a universal RHOAI prerequisite.

GPU ACCELERATION:
  Prereqs: NFD + NVIDIA GPU Operator
```

---

## Topologically sorted install order (7 phases)

Based on the Helm chart's explicit dependency declarations AND the RHOAI install guide prerequisites:

NOTE: Service Mesh 3.x is ONLY required if OGX/RAG is enabled. It is conditional.
The Helm chart does NOT list it as a managed dependency -- it's a manual prereq for OGX only.

```
PHASE 1 -- Foundation (zero dependencies, install first)
  1. cert-manager                          [no deps; needed by KServe, Kueue, LWS, RHCL]
  2. Node Feature Discovery (NFD)          [no deps; needed by GPU Operator]
  3. OpenShift Pipelines                   [no deps; needed by AI Pipelines DSP component]
  4. JobSet                                [no deps; needed by distributed training]
  5. Custom Metrics Autoscaler (KEDA)      [no deps; needed by inference HPA]
  6. OpenTelemetry (optional)              [no deps; needed by observability stack]

PHASE 2 -- Infrastructure (depends on Phase 1 operators)
  7. Leader Worker Set (LWS)      <- needs cert-manager [Helm chart: leaderWorkerSet->certManager]
  8. Red Hat build of Kueue       <- needs cert-manager [Helm chart: kueue->certManager]
  9. NVIDIA GPU Operator           <- needs NFD [Helm chart: nvidiaGPUOperator->nfd]
  10. Service Mesh 3.x            <- needs cert-manager [ONLY if OGX/RAG enabled]
  11. Tempo (optional)            <- needs OpenTelemetry [Helm chart: tempo->opentelemetry]
  12. Cluster Observability (opt) <- needs OpenTelemetry [Helm chart: clusterObservability->opentelemetry]

PHASE 3 -- Networking (depends on Phase 2: needs LWS from above)
  13. Red Hat Connectivity Link   <- needs cert-manager + LWS
      (Kuadrant/Authorino)          [Helm chart: rhcl->certManager,leaderWorkerSet]

PHASE 4 -- RHOAI Operator (depends on Phase 1 cert-manager; Phase 2 servicemesh IF OGX needed)
  14. Red Hat OpenShift AI        <- needs cert-manager (always)
      (rhods-operator)              + servicemesh (only if OGX/RAG workloads planned)

PHASE 5 -- RHOAI Configuration (depends on Phase 4 CSV=Succeeded)
  15. DSCInitialization
  16. DataScienceCluster (DSC)
      - kueue: Unmanaged (external Kueue operator from Phase 2 manages it)
      - all other GA components: Managed
      - ogx: Managed (only if ServiceMesh was installed in Phase 2)

PHASE 6 -- Platform Instances (depends on DSC Ready=True)
  17. GPU ClusterPolicy (NVIDIA)
  18. NFD NodeFeatureDiscovery instance
  19. Kueue ClusterQueue + ResourceFlavors
  20. MLflow tracking server instance
  21. Hardware Profiles
  22. Monitoring (ServiceMonitors, Dashboards)
  23. Cluster Autoscaler (GPU node scaling)

PHASE 7 -- Workloads (depends on KServe Ready, self-service)
  24. Models (InferenceService + vLLM serving)
  25. Services (GenAI Toolbox, MCP servers, etc.)
```

---

## ArgoCD wave mapping

| Phase | ArgoCD Wave | Components | Dependency Justification | Health Gate |
|---|---|---|---|---|
| 1 | wave 0 | cert-manager, NFD, Pipelines, JobSet, KEDA, OpenTelemetry | No dependencies -- these are the roots | All CSVs Succeeded |
| 2 | wave 1 | LWS, Kueue, GPU Operator, ServiceMesh(conditional), Tempo, ClusterObs | LWS needs cert-manager; Kueue needs cert-manager; GPU needs NFD | All CSVs Succeeded |
| 3 | wave 2 | RHCL (Kuadrant) | Needs cert-manager (wave 0) + LWS (wave 1). Cannot be same wave as LWS. | CSV Succeeded |
| 4 | wave 3 | RHOAI operator (rhods-operator) | Needs cert-manager (wave 0). Needs servicemesh (wave 1) only if OGX enabled. | CSV Succeeded |
| 5 | wave 4 | DSCInitialization + DataScienceCluster | RHOAI operator CRDs must be registered first | DSC phase=Ready |
| 6 | wave 5 | GPU ClusterPolicy, NFD instance, Kueue config, MLflow, HW profiles, Monitoring | DSC must be Ready for operator-managed resources to stabilize | Deployments available |
| 7 | wave 10 | Models + Services (via ApplicationSet, no internal sync waves) | KServe must be Ready, CRDs registered, webhook available | InferenceService ready |

### Verification: Why each wave is correct

**cert-manager in wave 0**: Helm chart shows certManager has no dependencies. Docs say "Install the cert-manager Operator" is a prerequisite for KServe, Kueue, LWS, and RHCL. It must be first.

**LWS in wave 1 (not wave 0)**: Helm chart explicitly declares `leaderWorkerSet -> Dependency: certManager`. It REQUIRES cert-manager to be running.

**Kueue in wave 1 (not wave 0)**: Helm chart explicitly declares `kueue -> Dependency: certManager`. Docs say "Install the Red Hat build of Kueue Operator. Install the cert-manager Operator."

**RHCL in wave 2 (not wave 1)**: Helm chart explicitly declares `rhcl -> Dependency: certManager, leaderWorkerSet`. It needs BOTH cert-manager (wave 0) AND LWS (wave 1). Therefore it must be in a later wave.

**RHOAI in wave 3 (not wave 1 or 2)**: Docs say "If you plan to use Llama Stack and RAG workloads, install the Red Hat OpenShift Service Mesh Operator 3.x before installing the OpenShift AI Operator." For a full deployment with OGX, servicemesh must be ready (wave 1) before RHOAI. Additionally, cert-manager (wave 0) must be present for KServe to work inside the DSC.

**DSC in wave 4 (not wave 3)**: You cannot create a DataScienceCluster CR until the RHOAI operator is running and has registered its CRDs. The Helm chart docs say: "The first run registered CRDs... the second run creates the Custom Resources."

**Models in wave 10 (gap)**: InferenceService CRD and webhooks must be registered by KServe (which is deployed by the DSC in wave 4). A large gap (10 vs 5) gives time for all sub-operators to stabilize.

### Note on the official Helm chart alternative

Red Hat provides `oci://registry.redhat.io/rhai/rhai-on-openshift-chart` (versions v3.4, v3.5) which handles all dependency resolution automatically. For ArgoCD integration, use:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoai-platform
spec:
  source:
    repoURL: registry.redhat.io/rhai
    chart: rhai-on-openshift-chart
    targetRevision: v3.5
    helm:
      values: |
        global:
          skipCrdCheck: true
        operator:
          type: rhoai
        components:
          kserve:
            dsc:
              managementState: Managed
  syncPolicy:
    syncOptions:
      - SkipDryRunOnMissingResource=true
```

This is an alternative to the manual Kustomize approach. The chart requires TWO syncs (first installs operators, second creates CRs after CRDs are available). The `SkipDryRunOnMissingResource=true` sync option is required for ArgoCD compatibility.
