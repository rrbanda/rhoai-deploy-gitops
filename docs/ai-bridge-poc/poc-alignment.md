# AI Bridge PoC: GitOps Alignment and Gaps

## Architecture

```
End Users -> Apigee -> AI Bridge (MaaS) -> Model Endpoints (llm-d / vLLM)
                       ^^^^^^^^^^^^^^^
                       This is what we deploy via GitOps
```

Single-cluster deployment on the lab GPU cluster. AI Bridge components are CPU workloads
running alongside model serving on the same cluster.

## What GitOps Deploys (Fully Automated)

| Stage | Component | GitOps Path | Sync Wave |
|-------|-----------|-------------|-----------|
| A | RHOAI 3.4 Operator | `components/operators/rhoai-operator/` | 0 |
| A | RHCL Operator | `components/operators/rhcl/` | 0 |
| A | GPU Operator | `components/operators/gpu-operator/` | 0 |
| A | Kuadrant Instance | `components/instances/rhcl-instance/` | 1 |
| A | DSC (MaaS + TrustyAI) | `components/instances/rhoai-instance/overlays/maas/` | 2 |
| A | User Workload Monitoring | `components/instances/monitoring-config/` | 2 |
| A | PostgreSQL for MaaS | `components/instances/maas-postgres/` | 2 |
| A | MaaS Gateway | `components/instances/maas-gateway/` | 3 |
| A | DNS Patch CronJob | `components/instances/maas-dns-patch/` | 3 |
| A | Reference Model (gemma2-9b-fp8) | `usecases/models/gemma2-9b-fp8/` | 4 |
| B1 | Admin Subscription | `usecases/models/gemma2-9b-fp8/manifests/maas-subscription.yaml` | 3 |
| B1 | MaaSAuthPolicy | `usecases/models/gemma2-9b-fp8/manifests/maas-auth-policy.yaml` | 3 |
| B1/B3 | Team Subscriptions (tiered) | `usecases/models/gemma2-9b-fp8/manifests/team-subscriptions.yaml` | 4 |
| B2 | TokenRateLimitPolicy | Auto-created by MaaS controller from subscription specs | Auto |
| B4 | ServiceMonitors | `components/instances/observability/` | 5 |
| C3 | Dashboard | `components/instances/observability/dashboard-configmap.yaml` | 5 |
| Extra | Guardrails Gateway | `usecases/services/guardrails-gateway/` | 7 |

## What Requires Customer Input (Blocked)

### C1: OIDC/SSO Federation

**Blocked on:** Enterprise IdP test tenant details.

**Required information:**
- IdP type: Okta, Azure AD, or ADFS
- OIDC client ID and client secret for test tenant
- Issuer URL / well-known endpoint
- Group claims mapping (admin vs engineer roles)

**GitOps artifact when provided:**
```yaml
# components/instances/oauth-config/oauth.yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
    - name: enterprise-idp
      type: OpenID
      openID:
        clientID: REPLACE
        clientSecret:
          name: enterprise-oidc-secret
        issuer: https://REPLACE.identity-provider.com
        claims:
          preferredUsername: ["preferred_username"]
          name: ["name"]
          email: ["email"]
          groups: ["groups"]
```

### C2: External Secrets Operator + Vault

**Blocked on:** Enterprise HashiCorp Vault instance accessible from lab cluster.

**Required information:**
- Vault URL (reachable from cluster)
- Authentication method (Kubernetes auth, AppRole, or Token)
- Secret path for model provider credentials
- Vault namespace (if using Vault Enterprise)

**GitOps artifact when provided:**
```yaml
# components/instances/external-secrets/
- SecretStore (connection to Vault)
- ExternalSecret (maps Vault path -> K8s Secret)
- ClusterSecretStore (if cluster-wide)
```

### Disconnected Environment Adaptations

The lab cluster is air-gapped. The following must be adapted before deployment:

1. **Image references**: All images must use `@sha256:` digests pointing to internal mirrors
2. **RHOAI operator source**: Must reference mirrored catalog (`CatalogSource` pointing to internal registry)
3. **PostgreSQL image**: Replace `registry.redhat.io/rhel9/postgresql-15:latest` with mirrored digest
4. **Guardrails Gateway image**: Already uses `@sha256:` digest but needs mirror path
5. **Authorino WASM plugin**: Requires disconnected workaround (documented, resolved in RHCL 1.5)

**Template for disconnected image patch:**
```yaml
# clusters/overlays/ai-bridge-poc/image-overrides.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
images:
  - name: registry.redhat.io/rhel9/postgresql-15
    newName: internal-registry.example.com/rhoai/postgresql-15
    digest: sha256:REPLACE_WITH_MIRRORED_DIGEST
```

### Team/Use-Case Names for Subscriptions

Current placeholders in `team-subscriptions.yaml`:

| Placeholder | Needs Customer Input |
|---|---|
| `team-a` / `team-a-ml-engineering` | Actual team name (e.g., "risk-analytics") |
| `team-b` / `team-b-data-science` | Actual team name |
| `team-c` / `team-c-app-developers` | Actual team name |
| Token limits (500K/100K/50K per hour) | Actual target TPM/RPM values |
| Priority values (1/5/10) | Actual tier definitions |

**Customer to confirm:** How many subscriptions? Which teams? What differentiates tiers beyond rate limits?

## Validation Scripts

Located in `demo/`:

| Script | PoC Stage | What It Validates |
|--------|-----------|-------------------|
| `stage-a-validate.sh` | A | Model listing, chat completion, OpenAI SDK compatibility |
| `stage-b-load-test.sh` | B1-B4 | Auth rejection, subscriptions, rate limiting, burst isolation, metrics |
| `stage-c-observability.sh` | C | Monitoring stack, ServiceMonitors, dashboards, IdP status |

## Multi-Cluster Architecture (Beyond PoC Scope)

The `usecases/services/ai-gateway/` and `usecases/services/llm-d-epp/` directories contain
manifests for the multi-cluster architecture demonstrated on our sandbox clusters. This is
a preview of RHOAI 3.5 (August 2026) capabilities:

- **ai-gateway**: Istio-based routing from a gateway cluster to remote inference endpoints
- **llm-d-epp**: Endpoint Picker Pod for intelligent request routing within an inference cluster

These are NOT part of the single-cluster PoC but validate the target architecture for
centralized control plane patterns with multi-cluster HA.

## Lab Cluster Current vs Required Configuration

| Component | Current | Required for PoC | GitOps Manages |
|-----------|---------|------------------|----------------|
| RHOAI | 3.3.0 | 3.4.0 | Yes (operator channel) |
| Service Mesh 3 | 3.2.2 | 3.2.2+ | No (pre-existing) |
| RHCL | 1.3.0 | 1.3.0+ | Yes (operator) |
| Authorino | 1.3.0 | 1.3.0 (workaround) | Yes (via RHCL) |
| GPU Operator | 25.3.4 | 25.3.4+ | Yes (operator) |
| MetalLB | 2.20.0 | 2.20.0 | No (pre-existing) |
| Cert Manager | 1.18.1 | 1.18.1+ | Yes (operator) |
| PostgreSQL | Not deployed | Required | Yes (new) |
| MaaS (modelsAsService) | Not enabled | Required | Yes (DSC overlay) |
| TrustyAI | Not enabled | Required | Yes (DSC overlay) |

## Success Criteria Mapping

| # | Criteria | How GitOps Addresses It |
|---|----------|------------------------|
| 1 | Per-use-case auth | `team-subscriptions.yaml` + `maas-auth-policy.yaml` |
| 2 | Token rate limiting | Subscription `tokenRateLimits` -> auto-created TRLP |
| 3 | Usage tracking | `observability/` ServiceMonitors + dashboard |
| 4 | Tiered access | Subscription `priority` field + per-tier limits |
| 5 | OIDC/SSO | **Blocked on customer** |
| 6 | Observability | `observability/dashboard-configmap.yaml` |
| 7 | API compatibility | `demo/stage-a-validate.sh` (OpenAI SDK test) |
| 8 | Secret rotation | **Blocked on customer** (ESO + Vault) |
