# Complete Teardown Procedure

Complete removal of Red Hat OpenShift AI (RHOAI) and all managed operators. Run steps in order.

!!! danger "Destructive operation"
    This procedure deletes all RHOAI components, operator data, CRDs, and namespaces. It is not reversible.

## Procedure

```bash
# 1. Delete use case namespaces
oc delete namespace orchestrator-rhoai --wait=true --timeout=300s
oc delete namespace llamastack --wait=true --timeout=300s 2>/dev/null || true

# 2. Delete DataScienceCluster and DSCInitialization
oc delete datasciencecluster default-dsc --wait=true --timeout=300s
oc delete dsci default-dsci --wait=true --timeout=120s

# 3. Delete GPU MachineSets and ClusterAutoscaler
oc delete machineautoscaler --all -n openshift-machine-api 2>/dev/null || true
oc delete clusterautoscaler default 2>/dev/null || true
oc delete machineset -l machine.openshift.io/gpu -n openshift-machine-api 2>/dev/null || true

# 4. Delete operator instances
oc delete clusterpolicy gpu-cluster-policy --timeout=120s
oc delete nodefeaturediscovery nfd-instance -n openshift-nfd
oc delete kueues.kueue.openshift.io cluster
oc delete jobsetoperator cluster

# 5. Delete operator subscriptions
oc delete sub rhods-operator -n redhat-ods-operator
oc delete sub gpu-operator-certified -n nvidia-gpu-operator
oc delete sub nfd -n openshift-nfd
oc delete sub kueue-operator -n openshift-kueue-operator
oc delete sub job-set -n openshift-jobset-operator
oc delete sub openshift-cert-manager-operator -n cert-manager-operator

# 6. Delete RHOAI auto-installed dependency operators
oc delete sub authorino-operator -n openshift-operators 2>/dev/null || true
oc delete sub servicemeshoperator3 -n openshift-operators 2>/dev/null || true
oc delete sub serverless-operator -n openshift-serverless 2>/dev/null || true

# 7. Delete CSVs from all namespaces
for ns in redhat-ods-operator openshift-kueue-operator openshift-jobset-operator \
  nvidia-gpu-operator openshift-nfd cert-manager-operator openshift-operators \
  openshift-serverless; do
  oc delete csv --all -n "$ns" 2>/dev/null || true
done

# 8. Clean up InstallPlans
oc delete installplan --all -n openshift-operators 2>/dev/null || true

# 9. Delete operator namespaces
for ns in redhat-ods-operator redhat-ods-applications redhat-ods-monitoring \
  openshift-kueue-operator openshift-jobset-operator nvidia-gpu-operator \
  openshift-nfd cert-manager-operator cert-manager openshift-serverless \
  knative-serving knative-serving-ingress knative-eventing openshift-pipelines \
  rhoai-model-registries rhods-notebooks; do
  oc delete namespace "$ns" --wait=true --timeout=120s 2>/dev/null || true
done

# 10. Delete CRDs (batch by domain)
oc delete crd $(oc get crd -o name | grep -E "opendatahub|kserve|kubeflow" | tr '\n' ' ')
oc delete crd $(oc get crd -o name | grep -E "kueue|nvidia|nfd\.|jobset" | tr '\n' ' ')
oc delete crd $(oc get crd -o name | grep -E "tekton|istio|sailoperator|authorino|certmanager|knative" | tr '\n' ' ')

# 11. Fix stuck CRDs (if any remain in Terminating state)
for crd in $(oc get crd -o name | grep -E "opendatahub|kserve|kubeflow|kueue|nvidia|nfd|jobset"); do
  oc patch "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done

# 12. Delete stale webhooks (may block future installs)
oc delete validatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
oc delete mutatingwebhookconfigurations -l operator.tekton.dev/operand-name 2>/dev/null || true
```

## Remove ArgoCD (if using GitOps)

```bash
# 13. Delete ArgoCD resources
oc delete -k clusters/overlays/dev/
oc delete sub openshift-gitops-operator -n openshift-gitops-operator
oc delete namespace openshift-gitops-operator openshift-gitops
```
