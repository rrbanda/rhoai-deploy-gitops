# Known Issues

## 1. PVC Zone Affinity

With `WaitForFirstConsumer` StorageClass, PVCs are provisioned in the zone of the first pod that binds them. If download jobs run on non-GPU nodes in a different zone, the PVC may not be accessible by GPU-node InferenceService pods. If this occurs, add a `nodeSelector` to download jobs to schedule them in the GPU node zone, or use a StorageClass with `Immediate` binding mode.

## 2. RWO PVC and Download Jobs

Model download jobs share RWO PVCs with predictor pods. Sync waves (download at wave 0, InferenceService at wave 1) ensure downloads complete before predictors start. Download jobs have no TTL so they persist as completed, preventing ArgoCD from recreating them into a Multi-Attach conflict.

## 3. DataScienceCluster (DSC) API Version -- v1 vs v2

The official RHOAI 3.3 documentation shows `apiVersion: datasciencecluster.opendatahub.io/v2`, which uses different component names (e.g., `aipipelines` instead of `datasciencepipelines`) and drops `modelmeshserving` and `codeflare`.

This repository uses the **v1 API** (`datasciencecluster.opendatahub.io/v1`), which the RHOAI 3.3 operator still accepts. The v1 API uses `datasciencepipelines`, `modelmeshserving`, and `codeflare` as component names. If you migrate to v2, rename these components accordingly and add new v2 fields (`argoWorkflowsControllers`, `registriesNamespace`, `workbenchNamespace`, `defaultClusterQueueName`, `defaultLocalQueueName`).

## 4. No Upgrade Path from RHOAI 2.x to 3.x (as of 3.3)

You cannot upgrade from OpenShift AI 2.25 or any earlier version to 3.0. OpenShift AI 3.0 introduces significant technology and component changes and is intended for new installations only. Install the RHOAI Operator on a cluster running OpenShift 4.19 or later and select the `fast-3.x` channel. The official docs state that support for upgrades from 2.25 to a stable 3.x version will be available in a later release. See the [official documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install) for details.

## 5. GPU ClusterPolicy v25.x

Requires `spec.daemonsets` and `spec.dcgm` fields that were optional in earlier versions.

## 6. Kueue v1.2

Requires `spec.config.integrations.frameworks` with supported framework list (BatchJob, RayJob, RayCluster, JobSet, PyTorchJob, TrainJob).

## 7. Stale Tekton Webhooks

After teardown, Tekton validating/mutating webhooks may persist and block namespace creation. Delete them explicitly:

```bash
oc delete validatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
oc delete mutatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
```

## 8. servicemeshoperator3

May reappear after teardown if RHDH operator is installed, as it declares servicemesh as an OLM dependency.

## 9. RHOAI Admission Webhooks

InferenceService annotations referencing non-existent `connections` secrets or `hardware-profile` names will be rejected. Remove these annotations if the backing resources don't exist.

## 10. Job Spec Immutability

If a download job's spec changes in Git while a completed job exists on the cluster, ArgoCD cannot update it (Kubernetes Jobs are immutable). Delete the existing job manually, then let ArgoCD recreate it:

```bash
oc delete job <name> -n <namespace>
```
