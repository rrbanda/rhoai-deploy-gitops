# Concepts

Before deploying, invest 30 minutes understanding the foundations. These concepts will transform you from someone running commands into someone who truly understands their AI platform.

---

## Why This Matters

Most deployment guides tell you *what commands to run*. This section explains *why* those commands work and *what happens* when you run them.

After reading these pages, you will:

- **Diagnose issues** without guessing — you will know exactly what each component does
- **Customize confidently** — compose your own profiles, add operators, change configurations
- **Explain the architecture** to stakeholders who need to approve the deployment
- **Operate the platform** knowing what self-healing and drift detection actually mean

---

## The Learning Path

Read these in order. Each builds on the previous:

<div class="journey-grid" markdown>

<a href="gitops-fundamentals/" class="journey-card">
<span class="card-icon">:material-source-branch:</span>
<h3>1. What is GitOps?</h3>
<p>Why Git drives infrastructure. How ArgoCD keeps clusters in sync. What "self-healing" actually means. Imperative vs declarative.</p>
<span class="card-tag tag-beginner">8 min read</span>
</a>

<a href="app-of-apps/" class="journey-card">
<span class="card-icon">:material-apps:</span>
<h3>2. App-of-Apps Pattern</h3>
<p>How one ArgoCD Application bootstraps an entire platform. Why ApplicationSets auto-discover new content from Git directories.</p>
<span class="card-tag tag-beginner">6 min read</span>
</a>

<a href="kustomize-overlays/" class="journey-card">
<span class="card-icon">:material-layers:</span>
<h3>3. Kustomize and Overlays</h3>
<p>How this repo composes manifests without templating. Bases, patches, replacements. Building your own custom profiles.</p>
<span class="card-tag tag-intermediate">7 min read</span>
</a>

<a href="gpu-scheduling/" class="journey-card">
<span class="card-icon">:material-chip:</span>
<h3>4. GPU Scheduling</h3>
<p>The full lifecycle: NFD labels nodes → GPU Operator installs drivers → Kueue manages quotas → job runs on GPU. End to end.</p>
<span class="card-tag tag-intermediate">10 min read</span>
</a>

<a href="rhoai-architecture/" class="journey-card">
<span class="card-icon">:material-cube-outline:</span>
<h3>5. RHOAI Architecture</h3>
<p>Operators all the way down. The DSC as control plane. What RHOAI installs internally vs what this repo declares.</p>
<span class="card-tag tag-advanced">8 min read</span>
</a>

</div>

---

## How These Concepts Connect

```mermaid
graph LR
  GitOps["1. GitOps"] -->|"drives"| AppOfApps["2. App-of-Apps"]
  AppOfApps -->|"uses"| Kustomize["3. Kustomize"]
  Kustomize -->|"composes"| RHOAI["5. RHOAI Architecture"]
  RHOAI -->|"schedules on"| GPU["4. GPU Scheduling"]
```

Once you understand all five, the [Quick Start](../quickstart.md) will make complete sense — every command maps to a concept you already know.
