# Quick Start Guide

Two paths to deploy the full Red Hat OpenShift AI (RHOAI) stack. Both use the same manifests.

!!! warning "Prerequisites"
    Before deploying, verify your cluster meets the [official RHOAI 3.4 requirements](index.md):

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

    !!! warning "Using a fork? Update the repo URL first"
        The ArgoCD manifests reference `https://github.com/rrbanda/rhoai-deploy-gitops.git`. If you forked this repo, run `./setup.sh --repo <your-repo-url>` to update all references automatically, or manually edit `repoURL` in these files:

        - `clusters/overlays/dev/bootstrap-app.yaml`
        - `clusters/overlays/dev/rhoai-instance-app.yaml`
        - `components/argocd/apps/cluster-operators-appset.yaml`
        - `components/argocd/apps/cluster-instances-appset.yaml`
        - `components/argocd/projects/base/platform-project.yaml`

=== "Manual (no ArgoCD)"

    ```bash
    # Phase 1 -- Pre-RHOAI Operators
    # Install all operators and wait for CSVs before proceeding.
    oc apply -k components/operators/cert-manager/
    oc apply -k components/operators/servicemesh/
    oc apply -k components/operators/nfd/
    oc apply -k components/operators/gpu-operator/
    oc apply -k components/operators/kueue-operator/
    oc apply -k components/operators/jobset-operator/
    oc apply -k components/operators/leader-worker-set/
    oc apply -k components/operators/opentelemetry/
    oc apply -k components/operators/tempo/
    oc apply -k components/operators/rhoai-operator/

    # Verify all operator CSVs are Succeeded (re-run until all show Succeeded)
    watch "oc get csv -A | grep -E 'cert-manager|servicemesh|nfd|gpu-operator|kueue|jobset|leader-worker|opentelemetry|tempo|rhods'"
    # IMPORTANT: Do NOT proceed until every CSV shows "Succeeded".

    # Phase 2 -- Pre-DSC Instances (order matters)
    oc apply -k components/instances/nfd-instance/
    oc wait --for=jsonpath='{.status.conditions[0].type}'=Available \
      nodefeaturediscovery/nfd-instance -n openshift-nfd --timeout=300s

    oc apply -k components/instances/gpu-instance/
    oc wait --for=jsonpath='{.status.state}'=ready \
      clusterpolicy/gpu-cluster-policy --timeout=600s

    oc apply -k components/instances/gpu-workers/examples/aws/  # Cloud-specific, see examples/
    oc apply -k components/instances/cluster-autoscaler/

    oc apply -k components/instances/kueue-instance/
    oc apply -k components/instances/kueue-config/
    oc apply -k components/instances/jobset-instance/

    # Phase 3 -- DSC + Post-DSC Instances
    oc apply -k components/instances/rhoai-instance/overlays/dev/
    oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
      datasciencecluster/default-dsc --timeout=600s

    oc apply -k components/instances/dashboard-config/
    oc apply -k components/instances/mcp-servers/
    oc apply -k components/instances/mlflow-instance/
    ```

## What Gets Deployed

The full stack installs ~18 ArgoCD Applications across three layers:

- **10 operators** -- cert-manager, ServiceMesh, NFD, GPU Operator, Kueue, JobSet, Leader Worker Set, OpenTelemetry, Tempo, RHOAI
- **~8 instances** -- NFD, ClusterAutoscaler, Kueue, Kueue Config, JobSet, Dashboard Config, MCP Servers, MLflow (plus DataScienceCluster via explicit App)
- **1 bootstrap** -- self-managing app-of-apps

See [ArgoCD Applications](reference/argocd-apps.md) for the complete list.

!!! tip "Deploying models and services"
    Models, services, and training workloads are managed in the **[rhoai-usecases](https://github.com/rrbanda/rhoai-usecases)** companion repository. Deploy them after the platform is healthy.

## Partial Installs

You don't need the full stack. See [Capabilities](capabilities/index.md) for per-capability guides and the DSC Overlays section for pre-built profiles.

!!! tip "Minimal serving install (CPU-only models)"
    If you only need model serving on CPU nodes (no GPU), install just cert-manager + RHOAI operator, then use the `serving` overlay:
    ```bash
    oc apply -k components/operators/cert-manager/
    oc apply -k components/operators/rhoai-operator/
    oc apply -k components/instances/rhoai-instance/overlays/serving/
    ```
    For GPU-accelerated model serving, also install NFD, GPU Operator, and GPU workers. See [GPU Infrastructure](capabilities/gpu-infrastructure.md).

!!! warning "GPU MachineSet customization"
    GPU worker provisioning is cloud-specific. Example MachineSet manifests for AWS are in `components/instances/gpu-workers/examples/aws/`. Copy and customize them for your cluster, or create your own for other clouds. See [GPU Infrastructure](capabilities/gpu-infrastructure.md) for details.
