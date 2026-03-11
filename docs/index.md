# RHOAI Deploy GitOps

End-to-end GitOps deployment of **Red Hat OpenShift AI 3.3** and AI use cases on OpenShift.

This repository contains everything needed to install, configure, and manage an RHOAI platform and deploy AI applications on top of it -- using either ArgoCD (GitOps) or plain `oc apply -k` (manual).

## What's Inside

<div class="grid cards" markdown>

-   **Architecture**

    ---

    App-of-apps pattern, ApplicationSets, dependency chain, and how the pieces fit together.

    [:octicons-arrow-right-24: Architecture](architecture.md)

-   **Quick Start**

    ---

    Two commands to deploy the full stack. GitOps and manual paths side by side.

    [:octicons-arrow-right-24: Quick Start](quickstart.md)

-   **Capabilities**

    ---

    Pick what you need: model serving, training, pipelines, workbenches, and more. Each has its own guide.

    [:octicons-arrow-right-24: Capabilities](capabilities/index.md)

-   **Use Cases**

    ---

    Pre-built AI applications deployed on the platform. Currently: NVIDIA ToolOrchestra.

    [:octicons-arrow-right-24: Use Cases](usecases/index.md)

</div>

## Prerequisites

- OpenShift Container Platform 4.19+
- `oc` CLI authenticated as cluster-admin
- GPU nodes available (NVIDIA L4, L40S, A100, or H100)
- At least 50Gi storage per model in the GPU node availability zone

## DSC Overlays -- Pick Your Profile

The base DataScienceCluster starts minimal (Dashboard only). Pick an overlay for your needs:

| Overlay | Components | Command |
|---------|-----------|---------|
| `minimal` | Dashboard | `oc apply -k components/instances/rhoai-instance/overlays/minimal/` |
| `serving` | Dashboard, KServe, ModelMesh | `oc apply -k components/instances/rhoai-instance/overlays/serving/` |
| `training` | Dashboard, Ray, Training Operator | `oc apply -k components/instances/rhoai-instance/overlays/training/` |
| `full` | All components | `oc apply -k components/instances/rhoai-instance/overlays/full/` |
| `dev` | All components (default) | `oc apply -k components/instances/rhoai-instance/overlays/dev/` |

See [Composing a Custom Profile](capabilities/index.md#composing-a-custom-profile) for building your own overlay.

## References

- [RHOAI 3.3 Install Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) -- Kustomize bases for operators
- [ToolOrchestra Paper](https://arxiv.org/abs/2503.02495) -- NVIDIA's multi-model orchestration approach
- [verl Framework](https://github.com/volcengine/verl) -- Reinforcement learning training framework
