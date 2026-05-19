---
name: Publish MaaS Demo to GitHub
overview: "Restructure and push the AI Bridge (MaaS) demo content to https://github.com/rrbanda/maas-demo.git as a clean, self-contained, reusable demo repository. Remove all customer references, include complete documentation and validation scripts."
todos:
  - id: sanitize-content
    content: Remove all customer names (CML40, bofa, etc) from docs. Exclude docs/bofa/ directory entirely. Replace CML40 references with generic 'target cluster'.
    status: pending
  - id: structure-repo
    content: Create clean directory layout in maas-demo repo with README, docs, manifests, scripts, and profiles
    status: pending
  - id: push-content
    content: Clone maas-demo repo, copy sanitized content, commit, and push
    status: pending
  - id: verify-no-customer-refs
    content: Final grep for any customer names or sensitive info before push
    status: pending
isProject: false
---

# Publish AI Bridge (MaaS) Demo to GitHub

## Goal

Push a clean, structured, reusable demo repository to `https://github.com/rrbanda/maas-demo.git` that anyone can use to deploy and validate the AI Bridge (MaaS) capabilities on their own RHOAI 3.4 clusters.

---

## Target Repository Structure

```
maas-demo/
├── README.md                          # Overview, quick start, architecture diagram
├── docs/
│   ├── architecture.md                # Detailed architecture (from ai-bridge-demo-environment.md)
│   ├── poc-validation.md              # PoC alignment table + evidence
│   └── gaps-and-considerations.md     # Production vs demo gaps
├── manifests/
│   ├── platform/                      # Platform prerequisites
│   │   ├── rhoai-instance/            # DataScienceCluster with MaaS enabled
│   │   ├── maas-postgres/             # PostgreSQL for MaaS backend
│   │   ├── monitoring-config/         # User workload monitoring
│   │   └── observability/             # ServiceMonitors + Dashboard ConfigMap
│   ├── model/                         # Model deployment
│   │   ├── llm-inference-service.yaml # LLMInferenceService CR
│   │   ├── pvc.yaml                   # Model weights storage
│   │   ├── download-job.yaml          # HuggingFace download job
│   │   └── subscriptions.yaml         # MaaSSubscription (3 tiers)
│   ├── llm-d/                         # llm-d Endpoint Picker
│   │   ├── rbac.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── inference-pool.yaml
│   │   └── inference-model.yaml
│   ├── ai-gateway/                    # Multi-cluster routing (Istio)
│   │   ├── namespace.yaml
│   │   ├── gateway.yaml
│   │   ├── httproute.yaml
│   │   ├── service-entry.yaml         # PLACEHOLDER for remote hostname
│   │   └── destination-rule.yaml      # PLACEHOLDER for remote hostname
│   ├── guardrails/                    # Content safety gateway
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── oidc/                          # OIDC integration
│   │   └── authconfig.yaml            # PLACEHOLDER for Keycloak issuer
│   └── vault-eso/                     # External Secrets + Vault
│       ├── vault-deployment.yaml
│       ├── eso-subscription.yaml
│       ├── secretstore.yaml
│       └── external-secrets.yaml
├── scripts/
│   ├── deploy-all.sh                  # One-shot deploy script
│   ├── validate-poc.sh                # PoC validation (all 8 criteria)
│   └── teardown.sh                    # Clean removal
├── profiles/                          # Kustomize profiles for different scenarios
│   ├── single-cluster/                # Everything on one cluster
│   │   └── kustomization.yaml
│   └── multi-cluster/                 # Gateway + inference split
│       ├── gateway-cluster/
│       └── inference-cluster/
└── .gitignore
```

---

## Content Source Mapping

| Target | Source in rhoai-deploy-gitops-1 |
|--------|-------------------------------|
| `docs/architecture.md` | `docs/ai-bridge-demo-environment.md` (sanitized, remove CML40 refs) |
| `docs/poc-validation.md` | PoC alignment section from same doc |
| `manifests/platform/rhoai-instance/` | `components/instances/rhoai-instance/overlays/maas/` |
| `manifests/platform/maas-postgres/` | `components/instances/maas-postgres/` |
| `manifests/platform/monitoring-config/` | `components/instances/monitoring-config/` |
| `manifests/platform/observability/` | `components/instances/observability/` |
| `manifests/model/` | `usecases/models/qwen25-7b-instruct/manifests/` + subscriptions |
| `manifests/llm-d/` | `usecases/services/llm-d-epp/manifests/` |
| `manifests/ai-gateway/` | `usecases/services/ai-gateway/manifests/` |
| `manifests/guardrails/` | `usecases/services/guardrails-gateway/manifests/` |
| `manifests/oidc/` | `components/instances/oidc-integration/` |
| `manifests/vault-eso/` | `components/instances/vault-dev/` + `external-secrets-config/` + `components/operators/external-secrets/` |
| `scripts/validate-poc.sh` | `demo/poc-validation.sh` (sanitized) |

---

## Files to EXCLUDE (customer-specific or irrelevant)

- `docs/bofa/` — customer-specific content
- `docs/ai-bridge-poc/poc-alignment.md` — references specific PoC engagement
- `usecases/services/toolorchestra-app/` — unrelated use case
- `usecases/services/llamastack/` — unrelated use case
- `usecases/services/rhokp/` — unrelated use case
- `usecases/services/genai-toolbox/` — unrelated use case
- `components/instances/rhdh-instance/` — unrelated
- `components/instances/evalhub/` — unrelated
- `components/instances/mcp-servers/` — unrelated
- `components/instances/mlflow-instance/` — unrelated
- `components/instances/gpu-workers/` — infra-specific
- `components/instances/cluster-autoscaler/` — contains customer ref
- Any `.tessl/` or `.cursor/` config

---

## Sanitization Required

1. **`docs/ai-bridge-demo-environment.md`**: Replace "CML40" with "target cluster" in the gaps table
2. **`demo/poc-validation.sh`**: Replace hardcoded cluster hostnames with variables (already uses variables at top)
3. **All manifests with cluster-specific hostnames**: Convert back to `REPLACE_WITH_*` placeholders with clear comments explaining what to fill in
4. **Remove**: Any reference to specific sandbox cluster names (`cluster-4l6x6`, `cluster-6crhb`, specific ELB hostnames)

---

## README.md Content Plan

```markdown
# AI Bridge (MaaS) Demo — Red Hat OpenShift AI 3.4

Complete demonstration of Models-as-a-Service governance capabilities.

## What This Demonstrates
- Per-use-case API key authentication + subscriptions
- Token-based rate limiting (TPM/RPM per team)
- Tiered access (premium/standard/basic)
- Usage tracking via Prometheus
- OIDC/SSO federation (Keycloak)
- Secret rotation (Vault + External Secrets Operator)
- Content safety guardrails (PII detection)
- Multi-cluster routing (Istio gateway → remote model)
- Full GitOps lifecycle

## Prerequisites
- OpenShift 4.19+ with RHOAI 3.4
- RHCL (Kuadrant) operator
- GPU node (for model serving)
- (Optional) Second cluster for multi-cluster demo

## Quick Start
1. Clone this repo
2. Edit `scripts/config.env` with your cluster details
3. Run `./scripts/deploy-all.sh`
4. Validate: `./scripts/validate-poc.sh`

## Architecture
[diagram]

## Directory Structure
[table]
```

---

## Execution Steps

1. **Sanitize** — Remove/replace all customer names in source files
2. **Clone** `https://github.com/rrbanda/maas-demo.git` locally
3. **Copy** files according to the mapping above
4. **Create** README.md, deploy-all.sh, config.env template
5. **Convert** hardcoded hostnames to PLACEHOLDER variables
6. **Verify** — grep for any remaining customer refs or cluster-specific values
7. **Commit and push**
