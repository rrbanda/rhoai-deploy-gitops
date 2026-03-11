# Known Issues

## 1. PVC Zone Affinity

With `WaitForFirstConsumer` StorageClass, model download jobs must schedule on GPU nodes (via `nodeSelector: nvidia.com/gpu.present: "true"`) to ensure PVCs are provisioned in the same zone as GPU nodes.

## 2. RWO PVC and Download Jobs

Model download jobs share RWO PVCs with predictor pods. Sync waves (download at wave 0, InferenceService at wave 1) ensure downloads complete before predictors start. Download jobs have no TTL so they persist as completed, preventing ArgoCD from recreating them into a Multi-Attach conflict.

## 3. DSC API Version

RHOAI 3.3 installs the `v1` DSC CRD. Fields like `modelsasservice`, `trainer`, `mlflowoperator` are not yet available in v1. Use `datasciencepipelines` (not `aipipelines`), `modelmeshserving`, `codeflare`.

## 4. GPU ClusterPolicy v25.x

Requires `spec.daemonsets` and `spec.dcgm` fields that were optional in earlier versions.

## 5. Kueue v1.2

Requires `spec.config.integrations.frameworks` with supported framework list (BatchJob, RayJob, RayCluster, JobSet, PyTorchJob, TrainJob).

## 6. Stale Tekton Webhooks

After teardown, Tekton validating/mutating webhooks may persist and block namespace creation. Delete them explicitly:

```bash
oc delete validatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
oc delete mutatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
```

## 7. servicemeshoperator3

May reappear after teardown if RHDH operator is installed, as it declares servicemesh as an OLM dependency.

## 8. RHOAI Admission Webhooks

InferenceService annotations referencing non-existent `connections` secrets or `hardware-profile` names will be rejected. Remove these annotations if the backing resources don't exist.

## 9. Job Spec Immutability

If a download job's spec changes in Git while a completed job exists on the cluster, ArgoCD cannot update it (Kubernetes Jobs are immutable). Delete the existing job manually, then let ArgoCD recreate it:

```bash
oc delete job <name> -n <namespace>
```
