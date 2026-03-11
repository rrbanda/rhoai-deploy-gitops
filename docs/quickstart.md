# Quick Start Guide

Two paths to deploy the full Red Hat OpenShift AI (RHOAI) stack. Both use the same manifests.

!!! warning "Prerequisites"
    Before deploying, verify your cluster meets the [official RHOAI 3.3 requirements](index.md):

    - OpenShift 4.19 or 4.20 with at least 2 worker nodes (8 CPUs, 32 GiB RAM each)
    - Default storage class with dynamic provisioning
    - Identity provider configured (not `kubeadmin`)
    - Open Data Hub **not** installed
    - Internet access to Red Hat registries (or a disconnected mirror)

## Deploy

=== "GitOps (ArgoCD)"

    ```bash
    # 1. Install OpenShift GitOps operator
    oc apply -k bootstrap/

    # 2. Wait for GitOps operator to be ready
    oc wait --for=condition=Available deployment/openshift-gitops-server \
      -n openshift-gitops --timeout=300s

    # 3. Bootstrap the cluster (one-time manual apply, self-manages after this)
    oc apply -k clusters/overlays/dev/

    # 4. Monitor convergence (~15-30 min for full stack)
    watch oc get application.argoproj.io -n openshift-gitops
    ```

    After step 3, the `cluster-bootstrap` app-of-apps takes over. Any future
    changes pushed to Git are auto-synced -- no further `oc apply` needed.

=== "Manual (no ArgoCD)"

    ```bash
    # 1. Install operators (wait for each CSV to reach Succeeded)
    oc apply -k components/operators/cert-manager/
    oc apply -k components/operators/nfd/
    oc apply -k components/operators/gpu-operator/
    oc apply -k components/operators/kueue-operator/
    oc apply -k components/operators/jobset-operator/
    oc apply -k components/operators/rhoai-operator/

    # Verify all operator CSVs are Succeeded
    oc get csv -A | grep -E "cert-manager|nfd|gpu-operator|kueue|jobset|rhods"

    # 2. Create operator instances (order matters)
    oc apply -k components/instances/nfd-instance/
    oc wait --for=jsonpath='{.status.conditions[0].type}'=Available \
      nodefeaturediscovery/nfd-instance -n openshift-nfd --timeout=300s

    oc apply -k components/instances/gpu-instance/
    oc wait --for=jsonpath='{.status.state}'=ready \
      clusterpolicy/gpu-cluster-policy --timeout=600s

    oc apply -k components/instances/kueue-instance/
    oc apply -k components/instances/kueue-config/
    oc apply -k components/instances/jobset-instance/
    oc apply -k components/instances/rhoai-instance/overlays/dev/

    oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
      datasciencecluster/default-dsc --timeout=600s

    # 3. Deploy a use case
    oc apply -k usecases/toolorchestra/profiles/tier1-minimal/

    # 4. Wait for models to download and become Ready
    oc wait --for=condition=Ready inferenceservice/orchestrator-8b \
      -n orchestrator-rhoai --timeout=1800s
    oc wait --for=condition=Ready inferenceservice/qwen-math-7b \
      -n orchestrator-rhoai --timeout=1800s
    ```

## What Gets Deployed

The full stack installs **18 ArgoCD Applications** across three layers:

- **6 operators** -- cert-manager, NFD, GPU Operator, Kueue, JobSet, RHOAI
- **8 instances** -- NFD, GPU ClusterPolicy, GPU MachineSets, ClusterAutoscaler, Kueue, Kueue Config, JobSet, DataScienceCluster
- **2 use cases** -- ToolOrchestra serving (auto-sync) + training (manual sync)
- **1 bootstrap** -- self-managing app-of-apps

See [ArgoCD Applications](reference/argocd-apps.md) for the complete list.

## Partial Installs

You don't need the full stack. See [Capabilities](capabilities/index.md) for per-capability guides and the DSC Overlays section for pre-built profiles.

!!! tip "Minimal serving install"
    If you only need model serving, install just cert-manager + RHOAI operator, then use the `serving` overlay:
    ```bash
    oc apply -k components/operators/cert-manager/
    oc apply -k components/operators/rhoai-operator/
    oc apply -k components/instances/rhoai-instance/overlays/serving/
    ```
