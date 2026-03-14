# Deploying OpenShift AI

Deploy **Red Hat OpenShift AI (RHOAI) 3.3** on OpenShift -- from a full GitOps-managed platform to individual capabilities applied manually.

## What This Project Does

This repository provides production-ready Kustomize manifests for deploying Red Hat OpenShift AI and AI use cases on OpenShift. The manifests are composable -- start with a minimal dashboard, add model serving, training, or the full stack -- and work with two deployment methods:

- **GitOps (ArgoCD):** Two commands bootstrap a self-managing app-of-apps. Push to Git, everything syncs automatically.
- **Manual (Kustomize):** Apply manifests directly with `oc apply -k`. No ArgoCD needed. Full control over what gets deployed and when.

**Target audience:** Platform engineers deploying RHOAI, ML engineers who need a reproducible AI platform, and teams evaluating OpenShift AI capabilities.

**What gets deployed:**

- 7 operators (cert-manager, ServiceMesh, NFD, GPU Operator, Kueue, JobSet, RHOAI)
- GPU infrastructure (cloud-specific examples provided for AWS)
- A composable DataScienceCluster (DSC) with 10+ AI capabilities
- 3 models (orchestrator-8b, qwen-math-7b, gpt-oss-120b) independently deployable via GitOps
- 3 services (ToolOrchestra, LlamaStack, GenAI Toolbox) auto-discovered by ArgoCD

## What's Inside

<div class="grid cards" markdown>

-   **Architecture**

    ---

    Layered Kustomize structure (operators, instances, overlays), ArgoCD app-of-apps pattern, and dependency chain.

    [:octicons-arrow-right-24: Architecture](architecture.md)

-   **Quick Start**

    ---

    Deploy the full stack or just what you need. GitOps and manual paths side by side.

    [:octicons-arrow-right-24: Quick Start](quickstart.md)

-   **Capabilities**

    ---

    Pick what you need: model serving, training, pipelines, workbenches, and more. Each has its own guide with composable overlays.

    [:octicons-arrow-right-24: Capabilities](capabilities/index.md)

-   **Use Cases**

    ---

    Pre-built AI applications: NVIDIA ToolOrchestra, Meta LlamaStack, and GenAI Toolbox.

    [:octicons-arrow-right-24: Use Cases](usecases/index.md)

</div>

## Prerequisites

!!! warning "Review before installing"
    These requirements come from the [official RHOAI 3.3 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install). Verify them before deploying.

- **OpenShift Container Platform 4.19 or 4.20** (other versions are not supported)
- **Minimum 2 worker nodes** with 8 CPUs and 32 GiB RAM each
- **Default storage class** with dynamic provisioning configured
- **Identity provider configured** -- `kubeadmin` is not sufficient for RHOAI
- `oc` CLI authenticated as cluster-admin
- **Open Data Hub must NOT be installed** -- RHOAI and ODH cannot coexist on the same cluster
- **No upgrade path from RHOAI 2.x (as of 3.3)** -- 3.0 requires a fresh installation; upgrade support from 2.25 to a stable 3.x is planned for a later release (see [Known Issues #4](reference/known-issues.md))
- **Internet access** to `cdn.redhat.com`, `registry.redhat.io`, `quay.io`, and related Red Hat domains (or a disconnected mirror)
- GPU nodes available (NVIDIA L4, L40S, A100, or H100) -- required for model serving and training workloads
- At least 50Gi storage per model in the GPU node availability zone

## DSC Overlays -- Pick Your Profile

The base DataScienceCluster starts minimal (Dashboard only). Pick an overlay for your needs:

| Overlay | Components | Command |
|---------|-----------|---------|
| `minimal` | Dashboard | `oc apply -k components/instances/rhoai-instance/overlays/minimal/` |
| `serving` | Dashboard, KServe, ModelMesh | `oc apply -k components/instances/rhoai-instance/overlays/serving/` |
| `training` | Dashboard, Ray, Training Operator | `oc apply -k components/instances/rhoai-instance/overlays/training/` |
| `full` | All 10 DSC components | `oc apply -k components/instances/rhoai-instance/overlays/full/` |
| `dev` | All 10 DSC components (default) | `oc apply -k components/instances/rhoai-instance/overlays/dev/` |

See [Composing a Custom Profile](capabilities/index.md#composing-a-custom-profile) for building your own overlay.

## References

- [RHOAI 3.3 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
- [ToolOrchestra Paper](https://arxiv.org/abs/2503.02495) -- NVIDIA's multi-model orchestration approach
- [verl Framework](https://github.com/volcengine/verl) -- Reinforcement learning training framework
