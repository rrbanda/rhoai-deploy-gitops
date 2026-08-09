---
hide:
  - navigation
  - toc
---

<div class="hero" markdown>

# Deploy Red Hat OpenShift AI with GitOps

<p class="subtitle">
A production-ready, fully declarative deployment of Red Hat OpenShift AI on OpenShift — 
model serving, distributed training, batch inference, and GPU quota management — 
managed entirely through Git.
</p>

<div class="cta-group">
<a href="quickstart/" class="cta-primary">Get Started</a>
<a href="concepts/" class="cta-secondary">Learn the Concepts</a>
</div>

</div>

<div class="stats-bar" markdown>
<div class="stat-item">
<span class="stat-number">12</span>
<span class="stat-label">Operators Managed</span>
</div>
<div class="stat-item">
<span class="stat-number">12+</span>
<span class="stat-label">AI Capabilities</span>
</div>
<div class="stat-item">
<span class="stat-number">6</span>
<span class="stat-label">DSC Profiles</span>
</div>
<div class="stat-item">
<span class="stat-number">0</span>
<span class="stat-label">Manual Steps After</span>
</div>
</div>

---

## Choose Your Journey

<div class="grid cards" markdown>

-   :material-school: **I'm New to GitOps**

    ---

    Understand why Git drives infrastructure, how ArgoCD works, and how this repo is structured — before running a single command.

    [:octicons-arrow-right-24: Learn the Concepts](concepts/)

-   :material-rocket-launch: **I Want to Deploy Now**

    ---

    Two commands bootstrap a self-healing AI platform. Fork, configure, deploy. Every step explained.

    [:octicons-arrow-right-24: Quick Start](quickstart/)

-   :material-puzzle: **I Need Specific Capabilities**

    ---

    Pick exactly what you need: serving, training, batch inference, MaaS. Deploy only what matters for your use case.

    [:octicons-arrow-right-24: Capabilities Guide](capabilities/)

-   :material-layers-triple: **I'm Evaluating Architecture**

    ---

    See how 12 operators, 4 ApplicationSets, and composable overlays create a self-managing AI platform.

    [:octicons-arrow-right-24: Repository Architecture](architecture/)

</div>

---

## The Story

Most organizations deploying AI on Kubernetes face the same challenges:

| | Challenge | How GitOps Solves It |
|---|-----------|---------------------|
| :material-alert-circle: | Teams run manual installs, forget steps, create snowflake clusters. GPU resources are wasted. Nobody knows what changed. | Declare your entire AI platform in Git. Push a change, ArgoCD syncs it. Self-healing, auditable, reproducible. |
| :material-check-circle: | A second cluster needs the same setup — nobody remembers all the steps. An audit asks "who changed what?" and there is no answer. | Same manifests work on any cluster. `git log` is your audit trail. `git revert` rolls back any change. |
| :material-star: | The result: a fully managed RHOAI platform deployed via GitOps. Teams get model serving, training capacity, and GPU quotas — all governed by Git with zero manual intervention. | |

---

## What Gets Deployed

A single `git push` manages the complete stack:

```mermaid
graph LR
  subgraph operators ["Operators"]
    direction TB
    O1["cert-manager"]
    O2["NFD"]
    O3["GPU Operator"]
    O4["Kueue"]
    O5["RHOAI"]
    O6["+ 7 more"]
  end

  subgraph platform ["AI Platform"]
    direction TB
    P1["KServe"]
    P2["Batch Gateway"]
    P3["Training"]
    P4["Pipelines"]
    P5["Workbenches"]
    P6["Model Registry"]
  end

  subgraph infra ["GPU Infrastructure"]
    direction TB
    I1["Node Detection"]
    I2["Driver Install"]
    I3["Quota Management"]
    I4["Auto-Scaling"]
  end

  operators --> platform
  operators --> infra
  platform --> Workloads["AI Workloads"]
  infra --> Workloads
```

| Layer | What You Get |
|-------|-------------|
| **Operators** | cert-manager, ServiceMesh, NFD, GPU Operator, Kueue, JobSet, LWS, CMA, External Secrets, RHDH, RHCL, RHOAI |
| **Platform** | Dashboard, KServe, Ray, Training, Pipelines, Workbenches, Registry, MLflow, TrustyAI |
| **Advanced** | Batch Gateway (llm-d), Distributed Inference, Hardware Profiles, MaaS |
| **Infrastructure** | GPU node detection, driver installation, quota management, auto-scaling |

---

## How It Works

| Step | Action | What Happens |
|------|--------|-------------|
| **1. Declare** | Define your desired state in YAML. Choose your profile: minimal, serving, training, full, maas, or dev. Commit to Git. | Your intent is versioned, reviewable, and reproducible. |
| **2. Bootstrap** | Run two commands on your cluster. | ArgoCD installs and begins watching your Git repository. |
| **3. Converge** | Wait 15-30 minutes. | ArgoCD auto-discovers operators, instances, and workloads. The platform self-assembles. |
| **4. Operate** | Push changes to Git. | ArgoCD syncs the cluster automatically. Self-healing, auditable, reproducible. |

---

## Prerequisites

!!! warning "Prerequisites"

    OpenShift 4.19+ with GPU nodes, cluster-admin access, and internet connectivity to Red Hat registries. See the [Quick Start](quickstart/) for the complete checklist.

---

## Version Support

This repo defaults to the `fast` channel (latest GA). See the [Configuration guide](configuration/) for channel options and the [official supported configurations](https://access.redhat.com/articles/rhoai-supported-configs-3.x) for the compatibility matrix.

---

<div style="text-align: center; padding: 2rem 0;" markdown>

**Ready?** Start with the [Concepts](concepts/) to understand the architecture, jump to the [Quick Start](quickstart/) to deploy, or explore [Capabilities](capabilities/) and [Use Cases](usecases/).

[:material-arrow-right: Get Started](quickstart/){ .md-button .md-button--primary }

</div>
