# BofA Architect Engagement: Technical Discovery Playbook

## Context

New Forward Deployed Engineer, first meeting with BofA architects. Recent incident: OCP 4.20 upgrade caused CUDA driver incompatibility that broke inference serving for several hours. Environment is air-gapped. July 1 is the MVP1 go-live gate.

Your goal: demonstrate principal-level depth in the platform, surface the real blockers, and identify where you can deliver immediate value. Farid's stated concern is that Red Hat is "focused on RHOAI knobs instead of making it work at the bank." Every question must prove you care about the whole platform working end-to-end, not just tuning product settings.

---

## Stakeholder Map (internal intelligence - do not disclose sources)

| Person | Role | What you need to know |
|--------|------|----------------------|
| **Farid Moussavi** | Vinny Patrizio's proxy (confirmed 5/15) | When Farid gives direction, that's Vinny talking. He's not observing. His words: "this is a complex product", "let's be meticulous and verify everything." |
| **Dalbir** | Technical owner, your champion | "One of the main reasons we chose the Red Hat team is because of the connective tissue you have with your colleagues on the other side." Asked for early warning if July is at risk. Said "MVP1 doesn't need all the bells and whistles." |
| **Brooke Phillips** | Owns money/contract | Getting with Finance on budget. "Assume we'll do some type of extension." SOW must be deliverable-based. Contract call Wednesday 5/21. |
| **Satya** | Patching coordination | Assigned post-incident to own patching and pull in RH before platform changes. |
| **Javier & Pedro** | Model config and mesh overlay | They work AFTER Container Engineering completes RHOAI install on managed clusters. |
| **Container Engineering (CE)** | Automates RHOAI install | They go first. Timeline depends on their progress. |

**Deployment sequence:** CE automates RHOAI install → Javier & Pedro overlay model config and mesh → your work hardens the serving layer and observability. You need to know where CE is to know when you can start.

---

## Stakes

**Hit July 1:** Services expansion opens. More clusters, more models, bigger engagement.

**Miss July 1:** They build their own. This is existential for the deal.

Dalbir asked for early warning if July is at risk. Your assessment after this meeting should tell the team: "on track", "at risk because X", or "blocked on Y that we can't solve in 6 weeks."

---

## Timeline Intelligence

| Milestone | Date | Status |
|-----------|------|--------|
| MVP1 go-live (real use case, live customers) | July 1 | Decision gate |
| MaaS service definition approval | June/July | Pre-requisite for UAT |
| UAT onboarding | August | Follows service definition |
| PROD deployment | September | MVP2 gate |
| Full RHOAI functionality at the bank | End of September | SOW covers through EOY |

Test clusters are confirmed not production (Dalbir stated 5/15). Deployment to test first.

---

## Validated Facts (from reference OCP 4.20 cluster)

These are confirmed on a live cluster, not assumed. Use them to inform your questions but do not reveal you tested this externally.

| Component | Value | Notes |
|-----------|-------|-------|
| OCP | 4.20.22 | Same major version as BofA incident |
| RHOAI | 3.4.0 GA | Latest available. 3.5 does not exist in any channel. |
| RHOAI channel | stable-3.4, Automatic approval | Default config |
| GPU Operator | v26.3.1 (from v24.9.2) | 2 major version jump, Automatic approval, `stable` channel |
| NVIDIA Driver | 550.144.03 | |
| CUDA reported by nvidia-smi | 12.4 | This is the driver's NATIVE max CUDA support |
| CUDA forward compat libs | 560.35.05 | Mounted into containers for newer CUDA support |
| vLLM container PyTorch CUDA | 13.0 | Container compiled against CUDA 13.0 |
| Driver version pinned? | NO | `spec.driver.version` is empty |
| Auto-upgrade policy | `autoUpgrade: true` | Will pull new driver on kernel change |
| GPU | NVIDIA L4, 23GB VRAM | |
| Kernel | 5.14.0-570.112.1.el9_6 (RHCOS 9.6) | Driver container is matched to this |
| ClusterPolicy status | notReady (state-driver) | Despite GPU being fully functional |

**Critical CUDA compatibility chain (fragile):**
The vLLM container requires CUDA 13.0 but the node driver natively supports only CUDA 12.4. This works through NVIDIA's forward compatibility mechanism: the driver container includes compat libraries (version 560.35.05) that bridge the gap. If ANY upgrade breaks this chain - new driver without compat libs, new driver container that doesn't mount the right libraries, or toolkit config change - inference dies instantly while nvidia-smi still reports healthy.

---

## Phase 1: The Incident (lead here because it's their active pain)

Start with a precise question grounded in the known failure mechanism. The default ClusterPolicy ships with `autoUpgrade: true` and no driver version pin. The CUDA forward compatibility chain is fragile. In an air-gapped environment, there's an additional failure mode: the mirror may not have the correct driver container for a new kernel.

**Opening question:**

"For the driver issue on 4.20 - the default ClusterPolicy ships with `autoUpgrade: true` and no driver version pin. Was that your configuration when the upgrade ran? I'm trying to determine whether the OCP upgrade delivered a new kernel version that caused the GPU Operator to pull a different pre-compiled driver container, or whether the GPU Operator itself was upgraded at the same time - which would bring an entirely new driver catalog."

Why this works:
- States "the default ships with" rather than "your config likely has" - you're not assuming their state, you're demonstrating you know the default
- Shows you know the GPU Operator architecture: ClusterPolicy CR, driver daemonset, pre-compiled containers matched to kernel version
- Distinguishes between two distinct failure modes that require different fixes
- Asks "was that your configuration" which is respectful - they may have already fixed it
- Directly addresses Farid's concern: you care about why the platform broke, not about tuning RHOAI knobs

**Follow-ups based on their answer:**

If it was "OCP upgrade changed the kernel, operator pulled new driver":
- "Was the driver version pinned in ClusterPolicy, or was it empty? And in your air-gap environment - was the new driver container image already in your mirror, or did the pod fail to pull it?"
- "What CUDA version does your vLLM image expect? The default image ships with PyTorch compiled against CUDA 13.0, which relies on forward compatibility libraries in the driver container. If those compat libs weren't in the new driver build, inference would fail even though nvidia-smi reports healthy."

If it was "GPU Operator itself was upgraded":
- "Was the GPU Operator subscription on automatic approval? Because going from one major version to another ships an entirely different driver container catalog."
- "In your air-gap, did the new operator images get pulled from the mirror, or did the upgrade fail at the image pull stage?"

If they aren't sure:
- "Two things to check: first, did the GPU Operator CSV version change during the window? Second, does the driver daemonset pod name include the kernel build? If it changed from the previous pod name, the kernel triggered a new driver."

**Second question on symptoms:**

"What was the actual symptom? Did nvidia-smi still report the GPU while the inference pods failed, or did the node lose GPU visibility entirely?"

Why this matters:
- nvidia-smi works, inference pods fail = CUDA forward compatibility chain broken. The driver is loaded but the container's CUDA runtime can't use it. This is the most common failure in version mismatches.
- nvidia-smi fails entirely = driver not loaded. Either wrong driver container for this kernel, or in air-gap: the driver image wasn't in the mirror.
- Pod starts but gets CUDA errors during model load = PyTorch/vLLM compiled against CUDA features the runtime doesn't have.

**Technical background (do not say this out loud):**

On the reference cluster, the CUDA chain is:
- Node driver: 550.144.03 (native CUDA 12.4 support)
- Forward compat libraries in driver container: 560.35.05 (bridges to higher CUDA)
- vLLM container: PyTorch compiled against CUDA 13.0
- This works TODAY but is fragile - any change to the driver container version could remove or break the compat libs
- The driver daemonset pod name includes the kernel build: `nvidia-driver-daemonset-9.6.20260504-0`

---

## Phase 2: Current State of the Platform

These establish ground truth. You know the likely defaults but you're confirming, not assuming.

**Reference baseline (validated):**
- RHOAI: 3.4.0 GA on `stable-3.4` channel, Automatic approval
- GPU Operator: v26.3.1, `stable` channel, Automatic approval
- Driver: 550.144.03, no version pinning, auto-upgrade enabled
- CUDA compat chain: 12.4 (driver) → 560.35.05 (compat libs) → 13.0 (container)
- RHOAI 3.5 does not exist in any operator channel - not GA, not EA, not beta. It is a roadmap item only.

**"What GPU Operator version and driver version are you running today - after the rollback?"**

- You need the specific versions to build the compatibility matrix
- If they hesitate: "It's in the ClusterPolicy CR and the driver daemonset pod name. I can look directly if I have cluster access."

**"Is the RHOAI operator subscription set to manual or automatic install plan approval? Same question for the GPU Operator."**

- On the reference cluster: both are Automatic. This is the default and the risky configuration.
- Manual = controlled upgrades, slower but safer
- Automatic = what likely allowed the unplanned driver change
- If different approval strategies for each, there's a split ownership problem between teams

**"For the air-gap mirror: when a new container image is published on registry.redhat.io, what's the realistic cycle time to get it available inside your environment?"**

- Not "how does your mirror work" (too open) - you're asking for a number
- This number determines your lead time for any fix or upgrade
- Also ask: "Does the mirror include the GPU Operator's driver container images? Those are large (1-2GB each) and kernel-specific."

**"Are the model serving images (vLLM runtime, model weights) already mirrored, or does each new image require a separate security review?"**

- If model weights need per-image approval, July 1 depends on which model is already approved
- This tells you if you can iterate on model versions or are locked to what's in the mirror

---

## Phase 3: July 1 Scope

**"What's the target use case for July 1? Specifically: what model, what inference pattern (sync API, batch, streaming), and who are the consumers?"**

- You need to know if it's a 7B model on one GPU or a 70B model on multi-GPU
- Consumer identity matters: internal team with service account auth vs governed MaaS access with API keys changes the architecture significantly
- The MaaS timeline shows service definition approval in June/July - if the model isn't defined yet, that's the blocker

**"Is there an inference workload running on these test clusters today, or are we starting from Container Engineering's base install?"**

- You know the sequence: CE installs RHOAI, then Javier/Pedro overlay model config. You're asking where in that chain they are.
- If CE hasn't finished the base install yet, everything downstream is blocked
- If the base is done but no model is serving, you need to know what's blocking Javier/Pedro

**"What does the promotion path look like from test to production? Are there defined environments with validation gates for AI workloads specifically, or does that still use the standard application promotion process?"**

- At BofA there WILL be a defined path (regulated bank) - but it may not be defined for GPU/AI workloads
- If not defined for AI workloads, that's a deliverable you can own
- Key sub-question: "Does the promotion gate include an inference smoke test, or just pod health checks?"
- You already know: test clusters first (Dalbir confirmed not production), then promote

---

## Phase 4: Observability (their current blind spot)

**"The timeout issues that were raised - can you tell me where in the request path they're being observed? Is it the caller seeing latency, the gateway returning 504s, or the inference pod itself taking too long to respond?"**

- They likely cannot pinpoint this. That IS the problem you're solving.
- Let them tell you what they know - don't say "you probably can't answer this"
- This is the pain point from the 5/13 call: request-level observability is missing in 3.4

**"What's currently being collected from the vLLM pods? Are you scraping the Prometheus metrics endpoint, capturing structured request logs, or only seeing Kubernetes-level pod metrics?"**

- vLLM exposes metrics at the `/metrics` endpoint including:
  - `vllm:time_to_first_token_seconds` (TTFT)
  - `vllm:time_per_output_token_seconds` (inter-token latency)
  - `vllm:num_requests_waiting` (queue depth)
  - `vllm:gpu_cache_usage_perc` (KV cache utilization)
  - `vllm:num_requests_running` (active batch size)
- If these aren't being collected, they're diagnosing performance issues without the data that matters
- The difference between "model is slow" and "model has full KV cache causing queueing" is only visible in these metrics

**"I've built observability for vLLM serving before. The standard approach is a ServiceMonitor scraping the metrics endpoint, structured request logging, and a dashboard showing the metrics that actually diagnose LLM latency issues - TTFT, queue depth, KV cache pressure. Is that something worth scoping for your environment?"**

Why this phrasing:
- States experience concretely
- Names the specific solution components so they can evaluate fit
- Asks permission to scope, doesn't commit to a deadline
- If they say yes, your first deliverable is defined
- This solves the observability gap WITHOUT needing 3.5

---

## Phase 5: Security and Compliance (critical at BofA, easy to miss)

**"What's the current process for approving new container images for GPU workloads? Is there a scanning requirement - vulnerability, malware, license compliance - before images are admitted to production?"**

- At a regulated bank, the answer is always yes
- You need to know: what scanner (Prisma, Aqua, Anchore?), what policy, and whether RHOAI images have already been through it
- If RHOAI images haven't been scanned/approved yet, that's a lead time item for July 1
- This directly addresses the security concern raised 5/13: they need model scanning for malware, vulnerability, and safety

**"For model artifacts specifically - is there a model governance or model risk management process that applies before a model can serve production traffic?"**

- BofA has MRM (Model Risk Management) requirements - this is regulatory, not optional
- If the MVP1 model hasn't been through MRM, July 1 isn't blocked on technology - it's blocked on compliance
- You cannot solve this with engineering - you can only surface it early

**"Are there network policies or egress restrictions in the inference namespace? Specifically, can pods reach the internal registry, the monitoring stack, and any model artifact storage?"**

- Air-gapped environments often have strict NetworkPolicies that block unexpected pod-to-pod traffic
- If you don't ask this, you'll hit walls when deploying and not understand why
- Common failure: inference pod can't pull model weights from internal registry due to egress policy

---

## Phase 6: Process (only after you've demonstrated value in Phases 1-5)

**Context you already know:** Satya has been assigned to own patching coordination and pull in RH before platform changes. The OCP upgrade that broke vLLM was not communicated to the RH team - that's the gap that was flagged. Don't ask "who owns patching coordination" - you already know. Instead, confirm the mechanism:

**"I understand Satya is owning patching coordination going forward. What's the trigger mechanism - does RH get notified at change request approval, or when the maintenance window is scheduled? And what's the lead time we'd need to run a validation pass?"**

- Shows you're already plugged into the org, not discovering it for the first time
- Asks for the specific handoff point, not the abstract process
- Ties back to your validation job offer

**"I can build an automated validation job that runs inference against a test model after any GPU Operator or OCP upgrade, and gates promotion to the next cluster tier if it fails. Would that fit into your existing promotion process?"**

- Concrete offer tied to their process, not imposed from outside
- Addresses Farid's anxiety directly ("let's be meticulous and verify everything")
- This is a real deliverable you can build in days, not weeks

---

## What NOT to Ask

| Don't ask | Why | What to do instead |
|-----------|-----|-------------------|
| "Can you walk me through your architecture?" | Too open, signals you haven't prepared | Ask specific questions about specific components |
| "What version of OCP are you on?" | You should know from briefing or cluster access | If you don't know, ask your internal team first |
| "What are your goals?" | Already stated: July 1 go-live, make it work | Reference the goals when scoping work |
| "How can we help?" | Passive, puts burden on them to direct you | Offer specific deliverables |
| "What's the timeline?" | You know: July 1 and Sept 30 | Reference the dates directly |
| "Tell me about the incident" | Too open, they've told the story already | Ask specific technical details about the incident |
| "Have you considered upgrading to 3.5?" | 3.5 doesn't exist. You'll look uninformed. | If they mention 3.5, clarify which specific features they need |
| "Who owns patching coordination?" | You already know: Satya | Ask about the trigger mechanism and lead time instead |

---

## Credibility Signals for Principal Level

Things to demonstrate naturally in conversation:

- You know the CUDA forward compatibility chain: driver → compat libs → container runtime. You know it's fragile.
- You know that ClusterPolicy CR controls driver version pinning and `autoUpgrade` behavior
- You know the difference between "driver container for this kernel" vs "GPU Operator version upgrade bringing new catalog"
- You know vLLM exposes Prometheus metrics with specific names (TTFT, queue depth, KV cache)
- You know the difference between KServe Serverless, ModelMesh, and LLMInferenceService CRD
- You know that air-gapped OCP uses ImageDigestMirrorSet (IDMS) for image mirroring, and that GPU driver containers are large and kernel-specific
- You know that OLM subscriptions have `installPlanApproval: Manual|Automatic` and this is the mechanism that gates upgrades
- You know that in air-gap, a missing image in the mirror manifests differently than a compatibility issue (ImagePullBackOff vs CrashLoopBackOff)
- You know the deployment sequence (CE → model overlay → hardening) and where you fit
- You reference the MaaS timeline (service definition → UAT → PROD) as shared context

Things to NOT do:

- Don't name-drop Red Hat internal teams or roadmap details they shouldn't know
- Don't promise timelines until you've seen the actual environment
- Don't correct their terminology - use THEIR words for things
- Don't say "that's easy" about anything in an air-gapped, regulated bank environment
- Don't reference this repo, the reference cluster, or specific driver daemonset names
- Don't say "3.5 will fix this" - 3.5 doesn't exist as a shippable artifact
- Don't talk about "RHOAI knobs" - talk about making the platform work end-to-end

---

## Clarification: Is the Customer Asking for RHOAI 3.5?

**No.** And 3.5 does not exist.

### Verified from the operator catalog:

There is NO RHOAI 3.5 in any channel - not GA, not EA, not beta. The latest available versions:
- `stable-3.4`: rhods-operator.3.4.0 (what we're running - this is the newest)
- `stable-3.x`: rhods-operator.3.4.0 (same)
- `beta`: rhods-operator.3.4.0-ea.2 (OLDER than 3.4.0 GA - it's the EA that preceded GA)

3.5 is a product roadmap item only. It is not available to install anywhere.

### What was said on 5/13 (call with Priyanka and Sameer):

BofA is evaluating specific features they've seen on the 3.5 ROADMAP. They are not requesting an upgrade to something that doesn't exist. Three items were flagged:

| Feature | Roadmap Target | Verdict |
|---------|---------------|---------|
| VSR (vLLM Serving Runtime improvements) | November 2026 | Too late for MVP1 or MVP2. Not actionable. |
| External endpoint registry | August 2026 | Possibly relevant for MVP2, not blocking. |
| Request-level observability | Missing in 3.4 | The only real pain point. Solvable WITHOUT 3.5. |

### What the customer is actually saying:

- "We have pain points in 3.4 we can't solve today" (observability, security scanning)
- "We looked at the roadmap to see when these problems get addressed"
- "We are NOT committing to upgrade cycles because upgrades are expensive and fragile here"

### What they are NOT saying:

- "We need 3.5 before we go live"
- "Upgrade us to 3.5"
- "3.4 is insufficient"

### The real risk:

The risk is not that BofA demands 3.5. The risk is that the consulting team says "3.5 will fix this" without checking whether 3.5 even exists yet. That burns credibility and wastes weeks chasing something that isn't shippable.

### Why the only path to July 1 is hardening 3.4:

1. 3.5 does not exist as a shippable artifact. There is nothing to upgrade to.
2. Even if it appeared tomorrow: air-gapped upgrade cycle (mirror, scan, approve, deploy) takes 2-4 weeks minimum.
3. The 4.20 incident proved upgrades carry real operational risk in this environment.
4. Dalbir said "MVP1 doesn't need all the bells and whistles." Deliver with what works today.

### The correct framing if anyone mentions 3.5:

"3.5 isn't available yet - the latest GA is 3.4.0 which is what's deployed. The observability and security gaps you're hitting are solvable on 3.4 with targeted solutions we can deploy within your current approval pipeline. When 3.5 reaches GA, we plan the upgrade path for MVP2 after validating it safely on test clusters."

This answer demonstrates you actually checked the catalog instead of repeating marketing slides.

---

## After the Meeting: Your Assessment

Based on Dalbir's request for "early warning if July is at risk," your debrief should answer:

1. **Is July 1 on track?** Based on: where CE is in the install, whether a model is already serving on test, and whether the mirror pipeline can support the remaining images.
2. **What's blocking?** Specifically: compliance (MRM), infrastructure (mirror cycle time), or engineering (observability gap).
3. **What can you deliver in the next 2 weeks?** Concretely: validation job, observability stack, driver pinning recommendation.

Frame this against the deal stakes: July 1 = expansion, miss = they build their own.

---

## Summary: Your Posture

You are not there to learn. You are there to diagnose, propose, and deliver. Every question should either:

1. Confirm a specific technical fact you need to make a decision
2. Surface a gap that you already have a solution for
3. Offer a concrete deliverable tied to their stated pain

If a question doesn't do one of those three things, don't ask it.

You are positioned between Container Engineering (who installs) and the customer's production serving layer (where it must work). Your value is making the handoff work reliably: the right driver config, the right observability, the right promotion gates, the right coordination with Satya's patching process. That's what "connective tissue" means.
