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
│       └── rhoai-instance/ # DataScienceCluster (v1)
└── usecases/               # AI application deployments
    └── toolorchestra/      # NVIDIA ToolOrchestra multi-model orchestrator
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

# 3. Apply cluster configuration (triggers ArgoCD to sync everything)
oc apply -k clusters/overlays/dev/

# 4. Monitor convergence (~15-30 min for full stack)
watch oc get application.argoproj.io -n openshift-gitops
```

ArgoCD will automatically install all operators, create instances, and deploy use cases.
Retry policies handle ordering dependencies (operators must install before instances).

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

Retry policies: operators retry 5x (30s-5m), instances retry 10x (60s-10m), use cases retry 10x (60s-10m).

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

2. **DSC API version**: RHOAI 3.3 installs the `v1` DSC CRD. Fields like
   `modelsasservice`, `trainer`, `mlflowoperator` are not yet available in v1.
   Use `datasciencepipelines` (not `aipipelines`), `modelmeshserving`, `codeflare`.

3. **GPU ClusterPolicy v25.x**: Requires `spec.daemonsets` and `spec.dcgm` fields
   that were optional in earlier versions.

4. **Kueue v1.2**: Requires `spec.config.integrations.frameworks` with supported
   framework list (BatchJob, RayJob, RayCluster, JobSet, PyTorchJob, TrainJob).

5. **Stale Tekton webhooks**: After teardown, Tekton validating/mutating webhooks
   may persist and block namespace creation. Delete them explicitly.

6. **servicemeshoperator3**: May reappear after teardown if RHDH operator is installed,
   as it declares servicemesh as an OLM dependency.

7. **RHOAI admission webhooks**: InferenceService annotations referencing non-existent
   `connections` secrets or `hardware-profile` names will be rejected. Remove these
   annotations if the backing resources don't exist.

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
         kustomization.yaml
   ```

2. Each profile directory is a Kustomize target. ArgoCD auto-discovers it via the
   `cluster-usecases-appset` ApplicationSet, or deploy manually with
   `oc apply -k usecases/my-app/profiles/default/`.

3. For model download jobs, always add `nodeSelector: nvidia.com/gpu.present: "true"`
   to ensure PVCs are provisioned in the GPU availability zone.

## References

- [RHOAI 3.3 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
