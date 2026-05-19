# Forward Deployed Engineer: Role Definition for BofA RHOAI Engagement

## Why This Role Exists

The BofA engagement has a gap. RHOAI is installed and running at the platform level, but it's breaking at the operational boundary: inference fails after upgrades, models don't surface in the management plane, timeouts happen that nobody can diagnose. The existing team covers installation and configuration. Nobody currently covers the space between "product installed" and "product working reliably in production at a regulated bank."

That's what the FDE does.

---

## The Problem the Existing Team Cannot Solve Alone

On 5/15, an OCP 4.20 upgrade broke GPU inference for several hours. The team rolled back, but nobody could explain WHY it broke. The GPU driver, CUDA runtime, and AI serving container have a multi-layer compatibility dependency. Understanding which layer failed requires product-level knowledge of how the GPU Operator selects driver containers, how CUDA forward compatibility works, and how the serving runtime interacts with both.

This isn't a configuration problem. It's a product-depth problem. The consultants on the ground are skilled at deploying and configuring, but diagnosing product-internal failures is not their role and not a reasonable expectation of them.

Similarly: when a model is serving at the pod level but invisible in the Dashboard, the root cause is an interaction between the MaaS controller, the Kuadrant API gateway's authorization layer, and how internal health probes work. Debugging this requires knowledge of how these controllers interact - knowledge that lives in the product engineering team, not in deployment documentation.

The FDE bridges that gap.

---

## Role Boundaries

| Role | Owns | Does NOT own |
|------|------|-------------|
| **Container Engineering** | RHOAI install, cluster lifecycle, OCP upgrades | Why inference breaks after an upgrade |
| **Model consultants (Javier, Pedro)** | Model selection, deployment config, mesh integration | Product-level controller behavior, gateway internals |
| **Patching coordinator (Satya)** | Change scheduling, RH notification, coordination | What to validate after a change, what "safe" means for GPU workloads |
| **FDE** | Product-depth diagnosis, operational hardening, upgrade safety, observability | Platform install, model selection, change scheduling |

The FDE does not install RHOAI. The FDE does not choose which model to deploy. The FDE does not schedule maintenance windows.

The FDE makes sure that when a model IS deployed, it actually works end-to-end through the governed access layer. And when an upgrade DOES happen, there's a validation gate that catches breakage before it reaches production.

---

## What the FDE Delivers (This Engagement)

| Deliverable | Addresses | Who benefits |
|-------------|-----------|-------------|
| Incident root cause for the 4.20 failure | "Why did inference break and how do we prevent it?" | Architects (Farid), patching coordinator (Satya) |
| Driver pinning and upgrade safety recommendation | "How do we upgrade OCP without breaking GPU workloads?" | Container Engineering, Satya |
| Pre-upgrade validation automation | "How do we verify inference still works after any platform change?" | Everyone - this is the gate that prevents recurrence |
| Observability for inference workloads | "When timeouts happen, how do we diagnose them in minutes?" | Model consultants, customer's operations team |
| Promotion gate criteria for AI workloads | "What does 'ready for production' mean for a GPU inference service?" | Container Engineering, customer's approval process |
| Architect-level technical engagement | "Why should we trust this product?" (Farid's concern) | Deal progression, customer confidence |

---

## How It Works in Practice

- The FDE works alongside the existing team, not above them
- The FDE's output is artifacts the team uses: validation jobs, dashboards, compatibility data, documented fix procedures
- The FDE engages directly with the customer's architects on product-level questions that require depth the consultants shouldn't be expected to have
- The FDE feeds discovered issues back to the product team - this is the "connective tissue" Dalbir explicitly values about working with Red Hat
- When the engagement ends, the team has the tools to operate independently

---

## Success Criteria

| Criteria | How we know |
|----------|-------------|
| July 1 gate hit | Model serving live customers on production cluster |
| No repeat of undiagnosed failures | Next OCP upgrade passes validation gate without incident |
| Customer architects trust the platform | Farid stops saying "this is complex" and starts saying "we're confident" |
| Team operates independently | Consultants can deploy new models and diagnose issues using the FDE's artifacts without escalation |

---

## What This Is NOT

- This is not a senior engineer supervising the existing team
- This is not a product support escalation channel
- This is not a temporary replacement for any existing role
- This is a specialized function that fills a specific gap for the duration of this engagement, produces artifacts that outlast the engagement, and creates a repeatable model for future enterprise RHOAI deployments
