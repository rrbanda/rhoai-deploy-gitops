# RHOAI GitOps Deploy

Deploy **Red Hat OpenShift AI (RHOAI) 3.5** on OpenShift using a fully declarative, GitOps-driven approach. This repository provides production-ready Kustomize manifests that are composable, portable, and educational -- designed so you understand *what* you are deploying and *why*.

## What This Project Does

This repository gives you everything needed to deploy RHOAI on any OpenShift 4.19+ cluster:

- **Operators** -- All required operators installed via OLM Subscriptions
- **GPU Infrastructure** -- NFD, GPU Operator, auto-scaling, and Kueue quota management
- **DataScienceCluster** -- Composable profiles (serving-only, training-only, or full platform)
- **AI Workloads** -- Model serving, distributed inference, and training jobs
- **GitOps Management** -- ArgoCD app-of-apps pattern with self-healing and auto-discovery

Two deployment methods use the same manifests:

- **GitOps (ArgoCD):** Two commands bootstrap a self-managing platform. Push to Git, everything syncs.
- **Manual (Kustomize):** Apply manifests directly with `oc apply -k`. Full control, no ArgoCD needed.

## Who This Is For

- **Platform engineers** deploying RHOAI for their organization
- **ML engineers** who need a reproducible, version-controlled AI platform
- **Architects** evaluating how RHOAI components fit together
- **Anyone learning** GitOps patterns for AI/ML infrastructure

## What Gets Deployed

The full stack includes:

| Layer | Components |
|-------|-----------|
| **Operators** | cert-manager, ServiceMesh, NFD, GPU Operator, Kueue, JobSet, LeaderWorkerSet, CMA/KEDA, AI Gateway, RHCL, RHOAI |
| **GPU Infrastructure** | Node labeling, driver installation, device plugin, cluster autoscaling |
| **AI Platform** | Dashboard, KServe, ModelMesh, Ray, Training Operator, Pipelines, Workbenches, Model Registry, MLflow, TrustyAI |
| **Advanced Inference** | Batch Gateway (llm-d), AI Gateway, distributed inference, hardware profiles |
| **Workloads** | Model deployments, training jobs, AI applications |

## Start Here

<div class="grid cards" markdown>

-   **New to GitOps?**

    ---

    Start with the Concepts section. Learn why GitOps matters for AI platforms, how ArgoCD works, and how this repository is structured.

    [:octicons-arrow-right-24: Concepts](concepts/index.md)

-   **Ready to Deploy?**

    ---

    Follow the guided Quick Start. Every step includes an explanation of what is happening and why.

    [:octicons-arrow-right-24: Quick Start](quickstart.md)

-   **Pick Your Profile**

    ---

    Deploy only what you need. Choose from serving-only, training-only, or the full platform with all capabilities.

    [:octicons-arrow-right-24: Capabilities](capabilities/index.md)

-   **Understand the Architecture**

    ---

    See how the repo is structured, how applications are auto-discovered, and how dependencies flow.

    [:octicons-arrow-right-24: Architecture](architecture.md)

</div>

## DSC Profiles

The DataScienceCluster (DSC) controls which RHOAI capabilities are active. Choose a pre-built profile or compose your own:

| Profile | What It Enables | Use Case |
|---------|----------------|----------|
| `minimal` | Dashboard only | Exploration, start here |
| `serving` | Dashboard, KServe, ModelMesh | Model serving without training overhead |
| `training` | Dashboard, Ray, Training Operator | Distributed training without serving |
| `full` | All components (12+) | Complete AI platform |
| Custom | Your choice | [Compose your own](concepts/kustomize-overlays.md#composing-a-custom-profile) |

## Prerequisites

!!! warning "Verify before deploying"
    These requirements come from the [RHOAI 3.5 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3-latest/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install).

- **OpenShift Container Platform 4.19 or later**
- **Minimum 2 worker nodes** with 8 CPUs and 32 GiB RAM each
- **Default StorageClass** with dynamic provisioning
- **Identity provider configured** (kubeadmin is not sufficient)
- `oc` CLI authenticated as cluster-admin
- **Internet access** to registry.redhat.io, quay.io, cdn.redhat.com (or disconnected mirror)
- **GPU nodes** (NVIDIA L4, L40S, A100, H100) for inference and training workloads
- Open Data Hub must NOT be installed (RHOAI and ODH cannot coexist)

## Version Support

| RHOAI Version | Branch/Tag | OCP Versions | Channel |
|--------------|-----------|--------------|---------|
| 3.5 EA2 | `main` / `v3.5.0-ea2` | 4.19, 4.20 | `beta` |
| 3.4 (archived) | `archive/v3.4.0` | 4.19, 4.20 | `beta` |

## How to Use This Site

1. **Learn the concepts** -- Read [Concepts](concepts/index.md) to build your mental model
2. **Deploy** -- Follow the [Quick Start](quickstart.md) with understanding
3. **Customize** -- Use [Capabilities](capabilities/index.md) to enable exactly what you need
4. **Troubleshoot** -- Check [Known Issues](reference/known-issues.md) and [Troubleshooting](reference/troubleshooting.md) when things go wrong
5. **Contribute** -- Submit issues and PRs on [GitHub](https://github.com/rrbanda/rhoai-deploy-gitops)
