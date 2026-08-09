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

<div class="journey-section" markdown>

## Choose Your Journey

<p class="journey-subtitle">
Whether you are evaluating the platform, deploying for production, or building on top of it — start here.
</p>

<div class="journey-grid" markdown>

<a href="concepts/" class="journey-card">
<span class="card-icon">:material-school:</span>
<h3>I'm New to GitOps</h3>
<p>Understand why Git drives infrastructure, how ArgoCD works, and how this repo is structured — before running a single command.</p>
<span class="card-tag tag-beginner">Beginner · 30 min</span>
</a>

<a href="quickstart/" class="journey-card">
<span class="card-icon">:material-rocket-launch:</span>
<h3>I Want to Deploy Now</h3>
<p>Two commands bootstrap a self-healing AI platform. Fork, configure, deploy. Every step explained.</p>
<span class="card-tag tag-intermediate">Intermediate · 15 min</span>
</a>

<a href="capabilities/" class="journey-card">
<span class="card-icon">:material-puzzle:</span>
<h3>I Need Specific Capabilities</h3>
<p>Pick exactly what you need: serving, training, batch inference, MaaS. Deploy only what matters for your use case.</p>
<span class="card-tag tag-intermediate">Intermediate · 10 min</span>
</a>

<a href="architecture/" class="journey-card">
<span class="card-icon">:material-layers-triple:</span>
<h3>I'm Evaluating Architecture</h3>
<p>See how 12 operators (10 via ApplicationSet, 2 via instance CRs), 4 ApplicationSets, and composable overlays create a self-managing AI platform.</p>
<span class="card-tag tag-advanced">Advanced · 20 min</span>
</a>

</div>
</div>

---

## The Story

Most organizations deploying AI on Kubernetes face the same challenges:

<div class="journey-grid" markdown>

<div class="journey-card" style="border-left: 3px solid var(--rh-red);">
<h3>The Problem</h3>
<p>Teams run manual installs, forget steps, create snowflake clusters, and cannot reproduce their AI platform. GPU resources are wasted. Nobody knows what changed or when.</p>
</div>

<div class="journey-card" style="border-left: 3px solid var(--rh-mid-gray);">
<h3>The Solution</h3>
<p>Declare your entire AI platform in Git. Push a change, ArgoCD syncs it. Self-healing, auditable, reproducible. Same manifests work on any cluster.</p>
</div>

<div class="journey-card" style="border-left: 3px solid var(--rh-green);">
<h3>The Result</h3>
<p>A fully managed RHOAI platform deployed via GitOps. Teams get model serving, training capacity, and GPU quotas — all governed by Git with zero manual intervention.</p>
</div>

</div>

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

<div class="journey-grid" markdown>

<div class="journey-card">
<span class="card-icon">:material-numeric-1-circle:</span>
<h3>Declare</h3>
<p>Define your desired state in YAML. Choose your profile: minimal, serving, training, full, maas, or dev. Commit to Git.</p>
</div>

<div class="journey-card">
<span class="card-icon">:material-numeric-2-circle:</span>
<h3>Bootstrap</h3>
<p>Run two commands. ArgoCD installs and begins watching your Git repository for changes.</p>
</div>

<div class="journey-card">
<span class="card-icon">:material-numeric-3-circle:</span>
<h3>Converge</h3>
<p>ArgoCD auto-discovers operators, instances, and workloads. The platform self-assembles in 15-30 minutes.</p>
</div>

<div class="journey-card">
<span class="card-icon">:material-numeric-4-circle:</span>
<h3>Operate</h3>
<p>From this point, Git is your interface. Push changes → ArgoCD syncs → cluster updates. Self-healing, auditable, reproducible.</p>
</div>

</div>

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
