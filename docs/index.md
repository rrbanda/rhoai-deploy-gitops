---
hide:
  - navigation
  - toc
---

<div class="hero" markdown>

# Deploy **Red Hat OpenShift AI** with GitOps

<p class="subtitle">
Production-ready, fully declarative AI/ML platform deployment on OpenShift.
Model serving, distributed training, batch inference, GPU quota management — 
managed entirely through Git.
</p>

<div class="cta-group">
<a href="quickstart/" class="cta-primary">Deploy Now</a>
<a href="concepts/" class="cta-secondary">Learn the Concepts</a>
</div>

</div>

<div class="stats-bar" markdown>
<div class="stat-item">
<span class="stat-number">12</span>
<span class="stat-label">Operators</span>
</div>
<div class="stat-item">
<span class="stat-number">6</span>
<span class="stat-label">DSC Profiles</span>
</div>
<div class="stat-item">
<span class="stat-number">0</span>
<span class="stat-label">Manual Steps</span>
</div>
</div>

---

<div class="grid cards" markdown>

-   :material-school:{ .lg .middle } **I'm New to GitOps**

    ---

    Understand why Git drives infrastructure, how ArgoCD keeps clusters in sync, and how this repository is structured — before running a single command.

    [:octicons-arrow-right-24: Start with the Concepts](concepts/)

-   :material-rocket-launch:{ .lg .middle } **I Want to Deploy Now**

    ---

    Fork the repo, run `configure.sh`, bootstrap ArgoCD. Two commands and your entire AI platform self-assembles in 15-30 minutes.

    [:octicons-arrow-right-24: Quick Start Guide](quickstart/)

-   :material-puzzle:{ .lg .middle } **I Need Specific Capabilities**

    ---

    Pick exactly what you need — model serving, training, batch inference, MaaS, MLflow — and deploy only what matters for your team.

    [:octicons-arrow-right-24: Capabilities Guide](capabilities/)

-   :material-layers-triple:{ .lg .middle } **I'm Evaluating the Architecture**

    ---

    12 operators, 4 ApplicationSets, composable Kustomize overlays, and self-healing sync policies. See how it all fits together.

    [:octicons-arrow-right-24: Architecture Deep Dive](architecture/)

</div>

---

<div class="landing-section" markdown>

## Why GitOps for OpenShift AI?

<span class="section-subtitle">Most organizations deploying AI on Kubernetes face the same challenges. GitOps eliminates them.</span>

<div class="why-grid" markdown>

<div class="why-card why-card--problem" markdown>

### :material-alert-circle: Without GitOps

- Teams run **manual installs** and forget steps
- Every cluster becomes a **unique snowflake**
- Nobody knows **what changed** or when
- GPU resources are **hoarded**, not shared
- Reproducing a setup on a **second cluster** is impossible
- **Audits** have no verifiable trail

</div>

<div class="why-card why-card--solution" markdown>

### :material-check-circle: With This Repository

- **One command** bootstraps the entire AI platform
- **Same manifests** deploy identically on any cluster
- `git log` is your **complete audit trail**
- `git revert` **rolls back** any change instantly
- ArgoCD **self-heals** manual drift automatically
- Kueue provides **fair GPU scheduling** across teams

</div>

</div>

</div>

---

<div class="landing-section landing-alt" markdown>

## What Gets Deployed

<span class="section-subtitle">A single `git push` manages the complete AI/ML stack — from operators to workloads.</span>

<div class="stack-layer stack-layer--operators" markdown>
<span class="stack-label">Operators</span>
<span class="stack-items">cert-manager · ServiceMesh · NFD · GPU Operator · Kueue · JobSet · LWS · CMA · External Secrets · RHDH · RHCL · <strong>RHOAI</strong></span>
</div>

<div class="stack-layer stack-layer--platform" markdown>
<span class="stack-label">AI Platform</span>
<span class="stack-items">Dashboard · KServe · Ray · Training Operator · AI Pipelines · Workbenches · Model Registry · MLflow · TrustyAI</span>
</div>

<div class="stack-layer stack-layer--advanced" markdown>
<span class="stack-label">Advanced</span>
<span class="stack-items">Batch Gateway (llm-d) · Distributed Inference · Hardware Profiles · Models-as-a-Service (AI Gateway)</span>
</div>

<div class="stack-layer stack-layer--infra" markdown>
<span class="stack-label">Infrastructure</span>
<span class="stack-items">GPU node detection · NVIDIA driver installation · Quota management · Auto-scaling</span>
</div>

```mermaid
graph LR
  subgraph operators ["Operators (12)"]
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
    I3["Quota Mgmt"]
    I4["Auto-Scaling"]
  end

  operators --> platform
  operators --> infra
  platform --> Workloads["Your AI Workloads"]
  infra --> Workloads
```

</div>

---

<div class="landing-section" markdown>

## How It Works

<span class="section-subtitle">From zero to a production AI platform in four steps.</span>

<div class="step-flow" markdown>

<div class="step-card" markdown>

#### Declare

Choose your profile — `minimal`, `serving`, `training`, `full`, `maas`, or `dev`. Define your desired state in YAML. Commit to Git.

</div>

<div class="step-card" markdown>

#### Bootstrap

Run `configure.sh` and apply the bootstrap manifests. ArgoCD installs and starts watching your repository.

</div>

<div class="step-card" markdown>

#### Converge

ArgoCD auto-discovers operators, instances, and workloads via ApplicationSets. The platform self-assembles in 15-30 minutes.

</div>

<div class="step-card" markdown>

#### Operate

From this point, **Git is your interface**. Push a change, ArgoCD syncs. Self-healing, auditable, reproducible.

</div>

</div>

</div>

---

!!! info "Prerequisites"

    **OpenShift 4.19+** with cluster-admin access and internet connectivity to Red Hat registries. GPU nodes required for model serving and training workloads. See the [Quick Start](quickstart/) for the complete checklist.

!!! tip "Version Support"

    Defaults to the **`fast` channel** (latest GA release). Switch channels via `configure.sh` or Kustomize patches. See the [Configuration guide](configuration/) and the [official compatibility matrix](https://access.redhat.com/articles/rhoai-supported-configs-3.x).

---

<div class="final-cta" markdown>

## Ready to Deploy?

Start with the concepts to understand the architecture, or jump straight to deploying.

<div class="cta-group">
<a href="quickstart/" class="cta-primary">Quick Start</a>
<a href="concepts/" class="cta-secondary">Concepts</a>
<a href="capabilities/" class="cta-secondary">Capabilities</a>
<a href="usecases/" class="cta-secondary">Use Cases</a>
</div>

</div>
