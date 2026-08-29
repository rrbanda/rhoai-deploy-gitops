# RHOAI 3.4 -- Helm Chart GitOps Deployment

Deploy Red Hat OpenShift AI **3.4** using the official Helm chart managed by
OpenShift GitOps (ArgoCD). The chart is committed to this branch -- ArgoCD
reads it directly from Git with no OCI registry auth needed at deploy time.

| | Details |
|---|---|
| **RHOAI version** | 3.4 (chart v3.4.4, appVersion v3.4.4) |
| **Chart source** | `oci://registry.redhat.io/rhai/rhai-on-openshift-chart:v3.4` |
| **Chart digest** | `sha256:438f4d4e74de9b97f5a2e86e455de491e61b816d6b5294a765b1e611d9995838` |
| **OCP requirement** | 4.19+ |
| **Branch** | `helm-deploy-v3.4` |
| **For RHOAI 3.5** | Switch to branch `helm-deploy-v3.5` |

## Quick Start

### 1. Bootstrap (one-time)

```bash
oc apply -k helm-deploy/bootstrap/

# Wait for GitOps operator, then apply ArgoCD instance
until oc apply -f helm-deploy/bootstrap/argocd-instance.yaml; do sleep 10; done

# Wait for ArgoCD
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
```

### 2. Deploy RHOAI 3.4

**Full platform** (all components):

```bash
oc apply -f helm-deploy/applications/rhoai-platform.yaml
```

**Inference only** (KServe + dependencies):

```bash
oc apply -f helm-deploy/applications/rhoai-inference.yaml
```

### 3. Monitor

```bash
oc get application -n openshift-gitops -w
oc get csv -A | grep -E "(rhods|cert-manager|leader-worker|kueue|rhcl)"
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
```

## Upgrading from 3.4 to 3.5

Change `targetRevision` in your Application manifest:

```yaml
# From:
targetRevision: helm-deploy-v3.4
# To:
targetRevision: helm-deploy-v3.5
```

Commit and push. ArgoCD detects the branch change and syncs the new chart.

## Differences from v3.5

| Aspect | v3.4 (this branch) | v3.5 |
|---|---|---|
| Operator channel | `stable-3.4` | `stable-3.5` |
| MaaS gateway | Under `kserve.modelsAsService` | Separate `aigateway` component |
| LlamaStack/OGX | `llamastackoperator` | Renamed to `ogx` |
| Kueue channel | `stable-v1.2` | `stable-v1.4` |
| KServe LWS dep | `true` (always) | `false` (opt-in for WideEP) |

## Disconnected Environments

Override the catalog source for air-gapped clusters:

```yaml
olm:
  source: my-mirrored-catalog
  sourceNamespace: openshift-marketplace
```

## Files

```
helm-deploy/
├── chart/              # Official RHOAI 3.4 Helm chart (unmodified)
├── bootstrap/          # GitOps operator + Sealed Secrets + ArgoCD instance
├── applications/       # ArgoCD Application manifests
│   ├── rhoai-platform.yaml    # Full platform
│   └── rhoai-inference.yaml   # Inference only
├── values/             # Standalone values files for reference
│   ├── full-platform.yaml
│   └── inference-only.yaml
└── sealed-secrets/     # Available for any secrets you need
```

## Troubleshooting

**CRs not created on first sync**: Expected. ArgoCD retries automatically
(limit=10, 30s backoff). Operators need ~2-5 min to register CRDs.

**Force re-sync**:
```bash
oc annotate application rhoai-platform -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite
```
