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

    !!! warning "Using a fork? Update the repo URL first"
        The ArgoCD manifests reference `https://github.com/rrbanda/rhoai-deploy-gitops.git`. If you forked this repo, run `./setup.sh <your-repo-url>` to update all references automatically, or manually edit `repoURL` in these files:

        - `clusters/overlays/dev/bootstrap-app.yaml`
        - `clusters/overlays/dev/rhoai-instance-app.yaml`
        - `clusters/overlays/dev/training-workloads-app.yaml`
        - `components/argocd/apps/cluster-operators-appset.yaml`
        - `components/argocd/apps/cluster-instances-appset.yaml`
        - `components/argocd/apps/cluster-models-appset.yaml`
        - `components/argocd/apps/cluster-services-appset.yaml`
        - `components/argocd/projects/base/platform-project.yaml`
        - `components/argocd/projects/base/usecases-project.yaml`

=== "Manual (no ArgoCD)"

    ```bash
    # Phase 1 -- Pre-RHOAI Operators
    # Install all operators and wait for CSVs before proceeding.
    oc apply -k components/operators/cert-manager/
    oc apply -k components/operators/servicemesh/           # Required for LlamaStack
    oc apply -k components/operators/nfd/
    oc apply -k components/operators/gpu-operator/
    oc apply -k components/operators/kueue-operator/
    oc apply -k components/operators/jobset-operator/
    oc apply -k components/operators/rhoai-operator/

    # Verify all operator CSVs are Succeeded (re-run until all show Succeeded)
    watch "oc get csv -A | grep -E 'cert-manager|servicemesh|nfd|gpu-operator|kueue|jobset|rhods'"
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

    oc apply -k components/instances/dashboard-config/      # Enables GenAI Studio (Tech Preview, not enabled by default)
    oc apply -k components/instances/mcp-servers/            # Registers MCP servers in GenAI Studio

    # Phase 4 -- Use Cases (deploy models first, then services)
    oc apply -k usecases/models/orchestrator-8b/profiles/tier1-minimal/
    oc apply -k usecases/models/qwen-math-7b/profiles/tier1-minimal/
    oc apply -k usecases/services/toolorchestra-app/profiles/tier1-minimal/

    # Wait for models to download and become Ready
    oc wait --for=condition=Ready inferenceservice/orchestrator-8b \
      -n orchestrator-8b --timeout=1800s
    oc wait --for=condition=Ready inferenceservice/qwen-math-7b \
      -n qwen-math-7b --timeout=1800s
    ```

## What Gets Deployed

The full stack installs ArgoCD Applications across four layers:

- **7 operators** -- cert-manager, ServiceMesh, NFD, GPU Operator, Kueue, JobSet, RHOAI
- **9 instances** -- NFD, GPU ClusterPolicy, ClusterAutoscaler, Kueue, Kueue Config, JobSet, DataScienceCluster, Dashboard Config, MCP Servers
- **3 models** -- orchestrator-8b, qwen-math-7b, gpt-oss-120b (auto-discovered by `cluster-models` AppSet)
- **3 services** -- toolorchestra-app, llamastack, genai-toolbox (auto-discovered by `cluster-services` AppSet)
- **1 bootstrap** -- self-managing app-of-apps

See [ArgoCD Applications](reference/argocd-apps.md) for the complete list.

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
